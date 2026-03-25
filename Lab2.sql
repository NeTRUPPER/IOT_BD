-- Лабораторная работа №2
-- Работа с индексацией и триггерами
-- БД: iot

-- Если запускаешь в psql:
-- \c iot

SET search_path = app, public;

CREATE EXTENSION IF NOT EXISTS pg_trgm;

------------------------------------------------------------
-- ЗАДАНИЕ 1. ИНДЕКСЫ И ЗАМЕРЫ ПРОИЗВОДИТЕЛЬНОСТИ
------------------------------------------------------------

------------------------------------------------------------
-- 1.1 Большая таблица для теста индексов
------------------------------------------------------------

DROP TABLE IF EXISTS app.events_big CASCADE;

CREATE TABLE app.events_big (
    id          bigserial PRIMARY KEY,
    device_id   bigint NOT NULL REFERENCES app.devices(id),
    customer_id bigint NOT NULL REFERENCES app.user_accounts(id),
    event_ts    timestamptz NOT NULL,
    status      text NOT NULL,
    amount      numeric(12,2) NOT NULL,
    payload     jsonb NOT NULL,
    location    point NOT NULL,
    tags        text[] NOT NULL,
    message     text
);

------------------------------------------------------------
-- 1.2 Генерация большого объема данных
-- Количество: 300000 строк
------------------------------------------------------------

WITH dev AS (
  SELECT array_agg(id) AS ids FROM app.devices
),
usr AS (
  SELECT array_agg(id) AS ids FROM app.user_accounts
),
gen AS (
  SELECT gs
  FROM generate_series(1, 300000) AS gs
)
INSERT INTO app.events_big(device_id, customer_id, event_ts, status, amount, payload, location, tags, message)
SELECT
  d.ids[1 + floor(random() * array_length(d.ids, 1))::int] AS device_id,
  u.ids[1 + floor(random() * array_length(u.ids, 1))::int] AS customer_id,
  now() - (random() * interval '365 days')                 AS event_ts,
  -- Чтобы показать пользу индекса: делаем 'error' редким значением.
  CASE
    WHEN random() < 0.02 THEN 'error'
    WHEN random() < 0.22 THEN 'warn'
    WHEN random() < 0.42 THEN 'queued'
    WHEN random() < 0.62 THEN 'acked'
    ELSE 'ok'
  END AS status,
  round((10 + random() * 5000)::numeric, 2)                AS amount,
  jsonb_build_object(
    'source', (ARRAY['sensor','gateway','api'])[1 + floor(random() * 3)::int],
    'batch', floor(random() * 1000)::int,
    'priority', (ARRAY['low','normal','high'])[1 + floor(random() * 3)::int]
  )                                                        AS payload,
  point((random() * 2000 - 1000)::float8, (random() * 2000 - 1000)::float8) AS location,
  ARRAY[
    (ARRAY['critical','telemetry','iot','night','day'])[1 + floor(random() * 5)::int],
    (ARRAY['hot','cold','stable','peak','offpeak'])[1 + floor(random() * 5)::int]
  ]                                                        AS tags,
  md5(random()::text)                                      AS message
FROM gen
CROSS JOIN dev d
CROSS JOIN usr u;

ANALYZE app.events_big;

------------------------------------------------------------
-- 1.3 Замеры ДО индексов (EXPLAIN ANALYZE)
------------------------------------------------------------

-- B-Tree кандидат: фильтр по customer_id + диапазон времени
EXPLAIN ANALYZE
SELECT *
FROM app.events_big
WHERE customer_id = (SELECT min(id) FROM app.user_accounts)
  AND event_ts >= now() - interval '30 days';

-- Hash кандидат: точное равенство по status
EXPLAIN ANALYZE
SELECT count(*)
FROM app.events_big
WHERE status = 'error';

-- GiST кандидат: гео-фильтр по окружности
EXPLAIN ANALYZE
SELECT count(*)
FROM app.events_big
WHERE location <@ circle(point(0,0), 250);

-- SP-GiST кандидат: ближайшие точки (KNN)
EXPLAIN ANALYZE
SELECT id, location
FROM app.events_big
ORDER BY location <-> point(10,10)
LIMIT 200;

-- BRIN кандидат: диапазон по дате на "длинной" таблице
EXPLAIN ANALYZE
SELECT count(*)
FROM app.events_big
WHERE event_ts >= now() - interval '7 days'
  AND event_ts < now();

-- GIN кандидат: JSONB и массив тегов
EXPLAIN ANALYZE
SELECT count(*)
FROM app.events_big
WHERE payload @> '{"source":"sensor"}'::jsonb
  AND tags @> ARRAY['critical']::text[];

------------------------------------------------------------
-- 1.4 Создание индексов всех требуемых типов
------------------------------------------------------------

-- B-Tree
CREATE INDEX IF NOT EXISTS idx_events_big_customer_ts_btree
ON app.events_big USING btree (customer_id, event_ts);

-- Hash
CREATE INDEX IF NOT EXISTS idx_events_big_status_hash
ON app.events_big USING hash (status);

-- GiST
CREATE INDEX IF NOT EXISTS idx_events_big_location_gist
ON app.events_big USING gist (location);

-- SP-GiST
CREATE INDEX IF NOT EXISTS idx_events_big_location_spgist
ON app.events_big USING spgist (location);

-- BRIN
CREATE INDEX IF NOT EXISTS idx_events_big_event_ts_brin
ON app.events_big USING brin (event_ts);

-- GIN (JSONB + массив)
CREATE INDEX IF NOT EXISTS idx_events_big_payload_gin
ON app.events_big USING gin (payload);

CREATE INDEX IF NOT EXISTS idx_events_big_tags_gin
ON app.events_big USING gin (tags);

ANALYZE app.events_big;

------------------------------------------------------------
-- 1.5 Замеры ПОСЛЕ индексов (те же запросы)
------------------------------------------------------------

EXPLAIN ANALYZE
SELECT *
FROM app.events_big
WHERE customer_id = (SELECT min(id) FROM app.user_accounts)
  AND event_ts >= now() - interval '30 days';

EXPLAIN ANALYZE
SELECT count(*)
FROM app.events_big
WHERE status = 'error';

EXPLAIN ANALYZE
SELECT count(*)
FROM app.events_big
WHERE location <@ circle(point(0,0), 250);

EXPLAIN ANALYZE
SELECT id, location
FROM app.events_big
ORDER BY location <-> point(10,10)
LIMIT 200;

EXPLAIN ANALYZE
SELECT count(*)
FROM app.events_big
WHERE event_ts >= now() - interval '7 days'
  AND event_ts < now();

EXPLAIN ANALYZE
SELECT count(*)
FROM app.events_big
WHERE payload @> '{"source":"sensor"}'::jsonb
  AND tags @> ARRAY['critical']::text[];

------------------------------------------------------------
-- ЗАДАНИЕ 2. ТРИГГЕРЫ ДЛЯ ЦЕЛОСТНОСТИ И БЕЗОПАСНОСТИ
------------------------------------------------------------

------------------------------------------------------------
-- 2.0 Учебные таблицы для демонстрации триггеров
------------------------------------------------------------

DROP TABLE IF EXISTS app.orders_lab2 CASCADE;
DROP TABLE IF EXISTS app.products_lab2 CASCADE;
DROP TABLE IF EXISTS app.delete_audit_lab2 CASCADE;
DROP TABLE IF EXISTS app.employees_auth CASCADE;

CREATE TABLE app.products_lab2 (
    id            bigserial PRIMARY KEY,
    sku           text NOT NULL,
    product_name  text NOT NULL,
    price         numeric(12,2) NOT NULL CHECK (price >= 0),
    created_at    timestamptz,
    updated_at    timestamptz
);

CREATE TABLE app.orders_lab2 (
    id             bigserial PRIMARY KEY,
    customer_id    bigint NOT NULL REFERENCES app.user_accounts(id),
    product_id     bigint NOT NULL REFERENCES app.products_lab2(id),
    qty            int NOT NULL CHECK (qty > 0),
    unit_price     numeric(12,2) NOT NULL CHECK (unit_price >= 0),
    total_amount   numeric(12,2) NOT NULL CHECK (total_amount >= 0),
    status         text NOT NULL DEFAULT 'new',
    created_at     timestamptz,
    updated_at     timestamptz
);

CREATE TABLE app.delete_audit_lab2 (
    id          bigserial PRIMARY KEY,
    table_name  text NOT NULL,
    deleted_id  bigint NOT NULL,
    deleted_by  text NOT NULL,
    deleted_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.employees_auth (
    id                     bigserial PRIMARY KEY,
    login                  text NOT NULL,
    password_hash          text NOT NULL,
    can_change_password    boolean NOT NULL DEFAULT false,
    created_at             timestamptz,
    updated_at             timestamptz
);

------------------------------------------------------------
-- 2.1 Триггер уникальности перед INSERT
------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.trg_products_sku_unique()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM app.products_lab2 p
        WHERE lower(p.sku) = lower(NEW.sku)
    ) THEN
        RAISE EXCEPTION 'SKU "%" уже существует. Вставка отменена.', NEW.sku;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_products_sku_unique
BEFORE INSERT ON app.products_lab2
FOR EACH ROW
EXECUTE FUNCTION app.trg_products_sku_unique();

------------------------------------------------------------
-- 2.2 Триггер каскадного обновления цены в связанных заказах
------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.trg_products_price_cascade()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.price <> OLD.price THEN
        UPDATE app.orders_lab2 o
        SET unit_price   = NEW.price,
            total_amount = round((NEW.price * o.qty)::numeric, 2),
            updated_at   = now()
        WHERE o.product_id = NEW.id
          AND o.status IN ('new', 'queued');
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_products_price_cascade
AFTER UPDATE OF price ON app.products_lab2
FOR EACH ROW
EXECUTE FUNCTION app.trg_products_price_cascade();

------------------------------------------------------------
-- 2.3 Триггер на аномальные удаления (блокировка)
------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.trg_orders_detect_mass_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_cnt int;
BEGIN
    INSERT INTO app.delete_audit_lab2(table_name, deleted_id, deleted_by, deleted_at)
    VALUES ('orders_lab2', OLD.id, session_user, now());

    SELECT count(*)
    INTO v_cnt
    FROM app.delete_audit_lab2 a
    WHERE a.table_name = 'orders_lab2'
      AND a.deleted_by = session_user
      AND a.deleted_at >= now() - interval '1 minute';

    IF v_cnt > 5 THEN
        RAISE EXCEPTION 'Подозрительная операция: более 5 удалений за 1 минуту (пользователь: %).', session_user;
    END IF;

    RETURN OLD;
END;
$$;

CREATE TRIGGER trg_orders_detect_mass_delete
AFTER DELETE ON app.orders_lab2
FOR EACH ROW
EXECUTE FUNCTION app.trg_orders_detect_mass_delete();

------------------------------------------------------------
-- 2.4 Триггер автозаполнения даты/времени
------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.trg_set_timestamps()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_at := COALESCE(NEW.created_at, now());
        NEW.updated_at := COALESCE(NEW.updated_at, now());
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.updated_at := now();
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_products_set_timestamps
BEFORE INSERT OR UPDATE ON app.products_lab2
FOR EACH ROW
EXECUTE FUNCTION app.trg_set_timestamps();

CREATE TRIGGER trg_orders_set_timestamps
BEFORE INSERT OR UPDATE ON app.orders_lab2
FOR EACH ROW
EXECUTE FUNCTION app.trg_set_timestamps();

CREATE TRIGGER trg_employees_set_timestamps
BEFORE INSERT OR UPDATE ON app.employees_auth
FOR EACH ROW
EXECUTE FUNCTION app.trg_set_timestamps();

------------------------------------------------------------
-- 2.5 Триггер запрета смены пароля без разрешения
-- Разрешение задается:
--   SET LOCAL app.allow_password_change = 'on';
-- либо флагом can_change_password=true в строке сотрудника.
------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.trg_block_password_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_allow text;
BEGIN
    IF NEW.password_hash IS DISTINCT FROM OLD.password_hash THEN
        v_allow := current_setting('app.allow_password_change', true);

        IF NOT COALESCE(OLD.can_change_password, false)
           AND COALESCE(v_allow, 'off') <> 'on' THEN
            RAISE EXCEPTION 'Смена пароля для "%" запрещена: нет специального разрешения.', OLD.login;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_block_password_change
BEFORE UPDATE OF password_hash ON app.employees_auth
FOR EACH ROW
EXECUTE FUNCTION app.trg_block_password_change();

------------------------------------------------------------
-- 2.6 Демоданные для триггеров
------------------------------------------------------------

INSERT INTO app.products_lab2(sku, product_name, price)
VALUES
('SKU-1001', 'IoT Gateway Basic', 500.00),
('SKU-1002', 'IoT Sensor Kit',    250.00),
('SKU-1003', 'IoT Edge Node',    1300.00);

INSERT INTO app.orders_lab2(customer_id, product_id, qty, unit_price, total_amount, status)
SELECT
  (SELECT min(id) FROM app.user_accounts),
  p.id,
  2,
  p.price,
  round((p.price * 2)::numeric, 2),
  'new'
FROM app.products_lab2 p;

INSERT INTO app.employees_auth(login, password_hash, can_change_password)
VALUES
('emp_a', md5('start_pass_a'), false),
('emp_b', md5('start_pass_b'), true);

------------------------------------------------------------
-- 2.7 Демонстрация работы триггеров
------------------------------------------------------------

-- A) Проверка уникальности SKU (должна быть ошибка, но скрипт продолжит работу)
DO $$
BEGIN
    BEGIN
        INSERT INTO app.products_lab2(sku, product_name, price)
        VALUES ('SKU-1001', 'Duplicated SKU Product', 999.99);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Ожидаемая ошибка уникальности: %', SQLERRM;
    END;
END;
$$;

-- B) Обновление цены и каскад в заказах
UPDATE app.products_lab2
SET price = 777.00
WHERE sku = 'SKU-1001';

SELECT
  p.sku,
  p.price AS product_price,
  o.id AS order_id,
  o.qty,
  o.unit_price,
  o.total_amount,
  o.status
FROM app.products_lab2 p
JOIN app.orders_lab2 o ON o.product_id = p.id
WHERE p.sku = 'SKU-1001'
ORDER BY o.id;

-- C) Массовое удаление (6 удалений за минуту -> блокировка)
INSERT INTO app.orders_lab2(customer_id, product_id, qty, unit_price, total_amount, status)
SELECT
  (SELECT min(id) FROM app.user_accounts),
  (SELECT id FROM app.products_lab2 WHERE sku = 'SKU-1002'),
  1, 250.00, 250.00, 'new'
FROM generate_series(1, 6);

DO $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT id FROM app.orders_lab2 ORDER BY id DESC LIMIT 6) LOOP
        BEGIN
            DELETE FROM app.orders_lab2 WHERE id = r.id;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Ожидаемая блокировка удаления: %', SQLERRM;
            EXIT;
        END;
    END LOOP;
END;
$$;

SELECT *
FROM app.delete_audit_lab2
ORDER BY id DESC
LIMIT 20;

-- D) Автозаполнение дат created_at / updated_at
INSERT INTO app.products_lab2(sku, product_name, price)
VALUES ('SKU-2001', 'Auto Timestamp Product', 333.00);

SELECT id, sku, created_at, updated_at
FROM app.products_lab2
WHERE sku = 'SKU-2001';

-- E) Запрет смены пароля без разрешения
DO $$
BEGIN
    BEGIN
        UPDATE app.employees_auth
        SET password_hash = md5('new_pass_for_emp_a')
        WHERE login = 'emp_a';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Ожидаемая блокировка смены пароля: %', SQLERRM;
    END;
END;
$$;

-- Разрешенная смена пароля через специальный флаг сессии
BEGIN;
SET LOCAL app.allow_password_change = 'on';
UPDATE app.employees_auth
SET password_hash = md5('allowed_change_emp_a')
WHERE login = 'emp_a';
COMMIT;

-- Разрешенная смена пароля у сотрудника с can_change_password=true
UPDATE app.employees_auth
SET password_hash = md5('allowed_change_emp_b')
WHERE login = 'emp_b';

SELECT login, can_change_password, created_at, updated_at
FROM app.employees_auth
ORDER BY id;

------------------------------------------------------------
-- ЗАДАНИЕ 3. Краткие выводы (для отчета)
------------------------------------------------------------
-- 1) B-Tree, Hash, GiST/SP-GiST, BRIN, GIN в соответствующих сценариях
--    уменьшают стоимость и время выполнения запросов.
-- 2) BRIN эффективен на больших "временных" таблицах с естественным ростом дат.
-- 3) GIN ускоряет поиск по JSONB и массивам.
-- 4) Триггеры позволяют централизованно обеспечить контроль целостности,
--    аудирование и блокировку опасных операций.
-- 5) Комбинация индексов + триггеров улучшает производительность и безопасность.

