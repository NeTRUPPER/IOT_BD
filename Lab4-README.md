# Лабораторная работа №4 — ручной порядок действий

PITR (Point-in-Time Recovery) и шифрование архивов WAL.  
Проект: Docker Compose, PostgreSQL 16, БД `iot`.

Автопроверка (не обязательна для отчёта): `./lab4-pitr-demo.sh`  
SQL-фрагменты: `Lab4.sql`

---

## Как это устроено

1. **Базовый бэкап** (`pg_basebackup`) — снимок файлов кластера на момент T₀.
2. **Архивы WAL** — журнал всех изменений после T₀; у нас сжаты и зашифрованы (`archive_wal.sh` → `db/archive/*.gz.enc`).
3. **Авария** — логические изменения после контрольной точки (DROP, новые данные).
4. **PITR** — разворачиваем бэкап в PGDATA и «накатываем» WAL **только до** записанной точки (`recovery_target_lsn` или `recovery_target_time`).

### Скрипты

| Файл | Назначение |
|------|------------|
| `db/scripts/archive_wal.sh` | Вызывается PostgreSQL при архивировании сегмента WAL |
| `db/scripts/restore_wal.sh` | Вызывается PostgreSQL при PITR для каждого нужного WAL |
| `db/conf/postgresql.conf` | `wal_level`, `archive_mode`, `archive_command` |
| `Lab4.sql` | SQL для заданий 1–2 |
| `lab4-pitr-demo.sh` | Полный автоматический прогон (опционально) |

---

## Подготовка (один раз или «с чистого листа»)

Из корня репозитория:

```bash
cd /path/to/IOT_BD

# Сборка образа с openssl
docker compose build db

# Чистый кластер с контрольными суммами (УДАЛИТ данные в томе!)
docker compose down -v
docker compose up -d db

# Права на каталог архива (postgres должен писать в db/archive)
docker run --rm -v "$(pwd)/db/archive:/a" iot_postgres:16 chown postgres:postgres /a

# Очистка старых WAL-архивов (если перезапускали кластер раньше)
docker run --rm -v "$(pwd)/db/archive:/a" iot_postgres:16 sh -c 'rm -f /a/*.gz.enc'

# Дождаться готовности
docker exec iot_postgres pg_isready -U iot_dba
```

Подключение к БД:

```bash
docker exec -it iot_postgres psql -U iot_dba -d iot
```

Или с хоста: `psql "host=127.0.0.1 user=iot_dba password=iot_dba dbname=iot"`.

---

## Задание 1. Инфраструктура и шифрование WAL

### 1.1 Контрольные суммы

В `psql`:

```sql
SHOW data_checksums;   -- должно быть on
```

Если `off` — том создавался до `POSTGRES_INITDB_ARGS: "--data-checksums"`. Нужен `docker compose down -v` и снова `up`.

### 1.2 Параметры архивирования

```sql
SHOW wal_level;        -- replica
SHOW archive_mode;     -- on
SHOW archive_command;  -- /usr/local/bin/archive_wal.sh %f %p
```

Для отчёта: фрагмент `db/conf/postgresql.conf` (строки с `wal_level`, `archive_mode`, `archive_command`).

### 1.3 Как работает шифрование

При закрытии сегмента WAL PostgreSQL вызывает:

```text
/usr/local/bin/archive_wal.sh %f %p
```

- `%f` — имя файла (например `000000010000000000000001`)
- `%p` — путь к WAL в `pg_wal`

Скрипт: `gzip` → `openssl enc -aes-256-cbc` → `db/archive/<имя>.gz.enc`.

Проверка — принудительное переключение WAL:

```sql
SELECT pg_switch_wal();
```

На хосте:

```bash
ls -la db/archive/
# должны появиться файлы *.gz.enc
```

Статистика архиватора:

```sql
SELECT * FROM pg_stat_archiver;
```

`failed_count` должен быть 0. Если архивы не появляются — снова `chown postgres:postgres` на `db/archive`.

Проверка расшифровки вручную (для отчёта):

```bash
# подставьте реальное имя файла из db/archive
openssl enc -d -aes-256-cbc -pass pass:MySecretPassword \
  -in db/archive/000000010000000000000006.gz.enc | gunzip | wc -c
```

---

## Задание 2. Бэкап, контрольная точка, авария

### 2.1 Базовый бэкап (на хосте)

```bash
docker exec iot_postgres rm -rf /tmp/pg_backup
docker exec iot_postgres pg_basebackup -D /tmp/pg_backup -U iot_dba -Fp -Xs -P
```

- `-Fp` — plain (каталог с файлами)
- `-Xs` — потоковый WAL во время бэкапа
- `-P` — прогресс

При `data_checksums=on` в PG 16 проверка сумм при бэкапе включена по умолчанию.

Скопировать на хост:

```bash
rm -rf ./db/backups/lab4-base
mkdir -p ./db/backups
docker cp iot_postgres:/tmp/pg_backup/. ./db/backups/lab4-base/
ls ./db/backups/lab4-base/
```

**Записать в отчёт:** время бэкапа, что это «точка опоры» для PITR.

### 2.2 Контрольная запись и точка восстановления

В `psql` (см. также `Lab4.sql`):

```sql
DROP TABLE IF EXISTS public.important_data;

CREATE TABLE public.important_data (
    id   serial PRIMARY KEY,
    note text NOT NULL,
    ts   timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.important_data (note)
VALUES ('Данные до аварии');

-- ОБЯЗАТЕЛЬНО записать в блокнот / отчёт:
SELECT pg_current_wal_insert_lsn() AS recovery_target_lsn;
SELECT now() AS recovery_target_time;

SELECT pg_switch_wal();

SELECT * FROM public.important_data;
```

**Важно:**

- `recovery_target_lsn` — надёжная цель PITR (рекомендуется).
- `recovery_target_time` — для описания момента времени в отчёте; при ручном прогоне время может «промахнуться».

Пример записи:

```text
recovery_target_lsn  = 0/60261D8
recovery_target_time = 2026-05-17 16:20:30.695415+00
```

### 2.3 Имитация аварии

Подождите **1–2 минуты**, затем:

```sql
DROP TABLE public.important_data;

CREATE TABLE public.important_data (
    id   serial PRIMARY KEY,
    note text NOT NULL,
    ts   timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.important_data (note)
VALUES ('Данные после аварии');

SELECT * FROM public.important_data;
SELECT pg_switch_wal();
```

Проверка «всё сломано»:

```sql
SELECT note FROM public.important_data;
-- «Данные после аварии»
```

На хосте: `ls db/archive/` — архивов стало больше.

---

## Задание 3. PITR вручную

### 3.1 Остановить PostgreSQL

```bash
docker compose stop db
```

### 3.2 Подготовить PGDATA из бэкапа

Узнать имя тома:

```bash
docker volume ls | grep db_data
# обычно: iot_bd_db_data
```

Подставьте **своё** имя тома и **свой** LSN из шага 2.2:

```bash
export TARGET_LSN='0/60261D8'   # ваш LSN
export VOL=iot_bd_db_data         # ваш том
export ROOT="$(pwd)"

docker run --rm \
  -v "$VOL:/pgdata" \
  -v "$ROOT/db/backups/lab4-base:/backup:ro" \
  -v "$ROOT/db/scripts/restore_wal.sh:/usr/local/bin/restore_wal.sh:ro" \
  -v "$ROOT/db/archive:/var/lib/postgresql/archive:ro" \
  -e WAL_ARCHIVE_PASSWORD=MySecretPassword \
  -e PGARCHIVE=/var/lib/postgresql/archive \
  iot_postgres:16 sh -eu -c "
    find /pgdata -mindepth 1 -maxdepth 1 ! -name 'lost+found' -exec rm -rf {} +
    cp -a /backup/. /pgdata/
    touch /pgdata/recovery.signal
    if [ -f /pgdata/postgresql.auto.conf ]; then
      grep -v -E '^(restore_command|recovery_target|recovery_target_)' \
        /pgdata/postgresql.auto.conf > /pgdata/postgresql.auto.conf.tmp || true
      mv /pgdata/postgresql.auto.conf.tmp /pgdata/postgresql.auto.conf
    fi
    {
      echo \"restore_command = '/usr/local/bin/restore_wal.sh %f %p'\"
      echo \"recovery_target_lsn = '${TARGET_LSN}'\"
      echo \"recovery_target_inclusive = on\"
      echo \"recovery_target_action = promote\"
    } >> /pgdata/postgresql.auto.conf
    chown -R postgres:postgres /pgdata
  "
```

| Параметр | Зачем |
|----------|--------|
| `recovery.signal` | Режим восстановления (PostgreSQL 12+) |
| `restore_command` | Расшифровка WAL из `db/archive` |
| `recovery_target_lsn` | Остановиться после INSERT «до аварии» |
| `recovery_target_inclusive = on` | Включить запись на целевом LSN |
| `recovery_target_action = promote` | После recovery — обычный RW-сервер |

**Альтернатива (как в методичке)** — только время, без LSN:

```text
recovery_target_time = '2026-05-17 16:20:30.695415+00'
```

Указывается **только один** тип цели: либо LSN, либо time.

### 3.3 Запуск и проверка

```bash
docker compose start db
docker logs iot_postgres 2>&1 | tail -40
```

В логах ожидаются строки:

- `restored log file ... from archive`
- `recovery stopping after WAL location`
- `archive recovery complete`
- `database system is ready to accept connections`

Проверка:

```bash
docker exec -it iot_postgres psql -U iot_dba -d iot -c \
  "SELECT * FROM public.important_data;"
```

**Ожидаемый результат:** одна строка `Данные до аварии` (не «после аварии»).

```sql
SELECT pg_is_in_recovery();  -- f после promote
```

---

## Чеклист для отчёта

| Раздел | Что включить |
|--------|----------------|
| Цель | PITR, RPO, шифрование WAL |
| Задание 1 | `SHOW data_checksums`, `archive_mode`, схема шифрования, скрин `db/archive/*.gz.enc` |
| Задание 2 | `pg_basebackup`, таблица до/после аварии, записанные LSN и время |
| Задание 3 | `recovery.signal`, `postgresql.auto.conf`, `restore_wal.sh`, лог recovery, SELECT после PITR |
| ИБ | WAL в открытом виде опасен; пароль в env (в проде — файл ключа / Vault) |
| Вывод | PITR откатил логическую аварию |

---

## Типичные ошибки

1. **`db/archive` пустой** — нет прав у `postgres` → `chown postgres:postgres /a`.
2. **Старые `*.gz.enc` от другого кластера** — в логе: `WAL file is from different database system` → очистить `db/archive` перед новым прогоном.
3. **Таблицы нет после PITR** — не вызвали `pg_switch_wal` после INSERT или неверный LSN/время.
4. **`multiple recovery targets specified`** — в `postgresql.auto.conf` дважды прописаны `recovery_target_*` → очистить (см. блок 3.2).
5. **SQL через Docker без `-i`** — heredoc не попадёт в контейнер; используйте `docker exec -it ... psql` или `-f`.

---

## Шпаргалка: порядок команд

```bash
docker compose build db && docker compose up -d db
docker run --rm -v "$(pwd)/db/archive:/a" iot_postgres:16 chown postgres:postgres /a

# Задание 1 — в psql (Lab4.sql, блок 1)

docker exec iot_postgres pg_basebackup -D /tmp/pg_backup -U iot_dba -Fp -Xs -P
docker cp iot_postgres:/tmp/pg_backup/. ./db/backups/lab4-base/

# Задание 2 — в psql (Lab4.sql, блоки 2–3)

docker compose stop db
# docker run ... PITR (блок 3.2)
docker compose start db

# Проверка — SELECT * FROM public.important_data;
```

---

## Связь с автоматическим скриптом

`./lab4-pitr-demo.sh` повторяет эти шаги автоматически. Для отчёта рекомендуется пройти сценарий **вручную** по этому файлу и сделать скриншоты на каждом этапе.
