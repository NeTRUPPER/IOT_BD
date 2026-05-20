#!/usr/bin/env bash
# Lab 4: демонстрация PITR с зашифрованными архивами WAL.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

DB_SERVICE=db
CONTAINER=iot_postgres
IMAGE=iot_postgres:16
BACKUP_DIR="$ROOT/db/backups/lab4-base"
TARGET_FILE="$ROOT/db/backups/lab4-recovery_target.txt"
ARCHIVE_DIR="$ROOT/db/archive"
WAL_PASSWORD="${WAL_ARCHIVE_PASSWORD:-MySecretPassword}"

log() { printf '\n==> %s\n' "$*"; }

clear_wal_archive() {
  docker run --rm -v "$ARCHIVE_DIR:/a" "$IMAGE" sh -c 'rm -f /a/*.gz.enc' 2>/dev/null || \
    find "$ARCHIVE_DIR" -maxdepth 1 -name '*.gz.enc' -delete 2>/dev/null || true
}

fix_archive_permissions() {
  docker run --rm -v "$ARCHIVE_DIR:/a" "$IMAGE" chown postgres:postgres /a
}

need_checksums() {
  local cs
  if ! docker exec "$CONTAINER" pg_isready -U iot_dba -q 2>/dev/null; then
    return 1
  fi
  cs="$(docker exec "$CONTAINER" psql -U iot_dba -tAc "SHOW data_checksums;" 2>/dev/null || echo off)"
  [[ "${cs// /}" != "on" ]]
}

volume_name() {
  docker volume ls -q --filter "label=com.docker.compose.project=$(basename "$ROOT" | tr '[:upper:]' '[:lower:]')" --filter "label=com.docker.compose.volume=db_data" | head -1
}

wait_pg() {
  for _ in $(seq 1 120); do
    if docker exec "$CONTAINER" pg_isready -U iot_dba -q 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "PostgreSQL did not become ready in time" >&2
  exit 1
}

clear_wal_archive

if need_checksums; then
  log "data_checksums=off — пересоздаём том с POSTGRES_INITDB_ARGS=--data-checksums"
  docker compose down -v
  docker compose build "$DB_SERVICE"
  docker compose up -d "$DB_SERVICE"
  wait_pg
else
  log "Пересборка образа и перезапуск (archive_mode)"
  docker compose build "$DB_SERVICE"
  docker compose up -d "$DB_SERVICE"
  wait_pg
  docker compose restart "$DB_SERVICE"
  wait_pg
fi

fix_archive_permissions

log "Проверка задания 1"
docker exec "$CONTAINER" psql -U iot_dba -d iot -v ON_ERROR_STOP=1 -c "
  SHOW data_checksums;
  SHOW wal_level;
  SHOW archive_mode;
  SHOW archive_command;
"

log "Базовый бэкап (pg_basebackup --checksum)"
rm -rf "$BACKUP_DIR"
mkdir -p "$(dirname "$BACKUP_DIR")"
docker exec "$CONTAINER" rm -rf /tmp/pg_backup
# При data_checksums=on контрольные суммы проверяются по умолчанию (PG 16).
docker exec "$CONTAINER" pg_basebackup -D /tmp/pg_backup -U iot_dba -Fp -Xs -P
docker cp "$CONTAINER:/tmp/pg_backup/." "$BACKUP_DIR/"

log "Контрольная запись и фиксация точки восстановления (LSN + время)"
docker exec -i "$CONTAINER" psql -U iot_dba -d iot -v ON_ERROR_STOP=1 <<'SQL'
DROP TABLE IF EXISTS public.important_data;
CREATE TABLE public.important_data (
    id serial PRIMARY KEY,
    note text NOT NULL,
    ts timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.important_data (note) VALUES ('Данные до аварии');
SQL

TARGET_LSN="$(docker exec "$CONTAINER" psql -U iot_dba -d iot -tAc "SELECT pg_current_wal_insert_lsn();" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
TARGET_TIME="$(docker exec "$CONTAINER" psql -U iot_dba -d iot -tAc "SELECT now();" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
printf 'lsn=%s\ntime=%s\n' "$TARGET_LSN" "$TARGET_TIME" >"$TARGET_FILE"
log "recovery_target_lsn = $TARGET_LSN"
log "recovery_target_time = $TARGET_TIME (для отчёта)"

log "Архивация WAL с контрольной точкой"
docker exec "$CONTAINER" psql -U iot_dba -d iot -v ON_ERROR_STOP=1 -c "SELECT pg_switch_wal();"
sleep 3
docker exec "$CONTAINER" psql -U iot_dba -d iot -tAc \
  "SELECT archived_count, failed_count, last_archived_wal FROM pg_stat_archiver;"

log "Пауза 70 с перед «аварией»"
sleep 70

log "Имитация инцидента"
docker exec -i "$CONTAINER" psql -U iot_dba -d iot -v ON_ERROR_STOP=1 <<'SQL'
DROP TABLE public.important_data;
CREATE TABLE public.important_data (
    id serial PRIMARY KEY,
    note text NOT NULL,
    ts timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.important_data (note) VALUES ('Данные после аварии');
SELECT pg_switch_wal();
SQL

ARCHIVE_COUNT="$(find "$ARCHIVE_DIR" -name '*.gz.enc' 2>/dev/null | wc -l)"
log "Зашифрованных WAL-архивов в db/archive: $ARCHIVE_COUNT"
if [[ "$ARCHIVE_COUNT" -lt 1 ]]; then
  echo "Нет архивов WAL — проверьте archive_command и права на db/archive" >&2
  exit 1
fi

log "Остановка PostgreSQL и подготовка PITR"
docker compose stop "$DB_SERVICE"

VOL="$(volume_name)"
if [[ -z "$VOL" ]]; then
  VOL="$(docker volume ls -q | grep '_db_data$' | head -1)"
fi
[[ -n "$VOL" ]] || { echo "Не найден том db_data" >&2; exit 1; }

docker run --rm \
  -v "$VOL:/pgdata" \
  -v "$BACKUP_DIR:/backup:ro" \
  -v "$ROOT/db/scripts/restore_wal.sh:/usr/local/bin/restore_wal.sh:ro" \
  -v "$ARCHIVE_DIR:/var/lib/postgresql/archive:ro" \
  -e WAL_ARCHIVE_PASSWORD="$WAL_PASSWORD" \
  -e PGARCHIVE=/var/lib/postgresql/archive \
  "$IMAGE" sh -eu -c "
    find /pgdata -mindepth 1 -maxdepth 1 ! -name 'lost+found' -exec rm -rf {} +
    cp -a /backup/. /pgdata/
    touch /pgdata/recovery.signal
    if [ -f /pgdata/postgresql.auto.conf ]; then
      grep -v -E '^(restore_command|recovery_target|recovery_target_)' /pgdata/postgresql.auto.conf \
        > /pgdata/postgresql.auto.conf.tmp || true
      mv /pgdata/postgresql.auto.conf.tmp /pgdata/postgresql.auto.conf
    fi
    {
      echo \"restore_command = '/usr/local/bin/restore_wal.sh %f %p'\"
      echo \"recovery_target_lsn = '${TARGET_LSN}'\"
      echo \"recovery_target_inclusive = on\"
      echo \"recovery_target_action = 'promote'\"
    } >> /pgdata/postgresql.auto.conf
    chown -R postgres:postgres /pgdata
  "

log "Запуск восстановления"
docker compose start "$DB_SERVICE"
wait_pg

log "Проверка результата PITR"
docker exec "$CONTAINER" psql -U iot_dba -d iot -v ON_ERROR_STOP=1 -c "
  SELECT * FROM public.important_data;
  SELECT pg_is_in_recovery() AS still_in_recovery;
"

RESULT="$(docker exec "$CONTAINER" psql -U iot_dba -d iot -tAc "SELECT note FROM public.important_data LIMIT 1;")"
if [[ "$RESULT" == "Данные до аварии" ]]; then
  log "УСПЕХ: PITR восстановил состояние до аварии"
else
  echo "ОШИБКА: ожидалось «Данные до аварии», получено: $RESULT" >&2
  exit 1
fi

docker compose up -d 2>/dev/null || true
