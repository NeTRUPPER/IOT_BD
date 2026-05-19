-- Лабораторная работа №4
-- PITR и шифрование архивов WAL (PostgreSQL 16, БД iot)
-- Инфраструктура: docker compose (см. db/conf/postgresql.conf, db/scripts/).
-- Полный сценарий с авто-проверкой: ./lab4-pitr-demo.sh
-- Ручной порядок действий (для отчёта): Lab4-README.md

------------------------------------------------------------
-- ЗАДАНИЕ 1. Проверка инфраструктуры
------------------------------------------------------------

-- Контрольные суммы страниц (должно быть on; иначе пересоздайте том: docker compose down -v).
SHOW data_checksums;

SHOW wal_level;
SHOW archive_mode;
SHOW archive_command;

-- После перезапуска с archive_mode=on в каталоге db/archive появятся *.gz.enc
-- (на хосте) при переключении WAL:
SELECT pg_switch_wal();

------------------------------------------------------------
-- ЗАДАНИЕ 2. Базовый бэкап и фиксация точки восстановления
------------------------------------------------------------

-- Бэкап выполняется с хоста (не из SQL):
--   docker exec iot_postgres rm -rf /tmp/pg_backup
--   docker exec iot_postgres pg_basebackup -D /tmp/pg_backup -U postgres -Fp -Xs -P
--   (при data_checksums=on проверка сумм включена по умолчанию в PG 16)
--   docker cp iot_postgres:/tmp/pg_backup ./db/backups/lab4-base

DROP TABLE IF EXISTS public.important_data;

CREATE TABLE public.important_data (
    id   serial PRIMARY KEY,
    note text NOT NULL,
    ts   timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.important_data (note)
VALUES ('Данные до аварии');

-- ЗАПИШИТЕ LSN и время — целевая точка PITR (после INSERT):
SELECT pg_current_wal_insert_lsn() AS recovery_target_lsn;
SELECT now() AS recovery_target_time;

SELECT pg_switch_wal();

SELECT * FROM public.important_data;

------------------------------------------------------------
-- ЗАДАНИЕ 2 (продолжение). Имитация инцидента
------------------------------------------------------------

-- Подождите 1–2 минуты, затем выполните:

DROP TABLE public.important_data;

CREATE TABLE public.important_data (
    id   serial PRIMARY KEY,
    note text NOT NULL,
    ts   timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.important_data (note)
VALUES ('Данные после аварии');

SELECT * FROM public.important_data;

-- Принудительная архивация текущего сегмента WAL:
SELECT pg_switch_wal();

------------------------------------------------------------
-- ЗАДАНИЕ 3. PITR (выполняется на хосте, не в psql)
------------------------------------------------------------

-- 1) docker compose stop db
-- 2) Развернуть базовый бэкап в PGDATA, создать recovery.signal и postgresql.auto.conf:
--    restore_command = '/usr/local/bin/restore_wal.sh %f %p'
--    recovery_target_lsn = '<ваш LSN>'
--    recovery_target_inclusive = on
--    recovery_target_action = 'promote'
--    (см. lab4-pitr-demo.sh)
-- 3) docker compose start db
-- 4) Проверка:

SELECT * FROM public.important_data;
-- Ожидается одна строка: «Данные до аварии»
