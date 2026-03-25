-- Лабораторная работа №1. Секционирование и аналитика
-- БД: iot (твоя текущая БД)
-- ВАЖНО: запускать под пользователем, который имеет права на схему app (postgres / security_admin).

------------------------------------------------------------
-- ШАГ 0. Контекст: выбираем БД и search_path
------------------------------------------------------------

-- Если запускаешь из psql:
-- \c iot

SET search_path = app, ref, public;

------------------------------------------------------------
-- ШАГ 1. Базовая таблица заказов (операции)
-- Клиенты = app.user_accounts, товары = app.devices
------------------------------------------------------------

CREATE TABLE IF NOT EXISTS app.orders (
    id          bigserial PRIMARY KEY,
    customer_id bigint NOT NULL REFERENCES app.user_accounts(id),
    device_id   bigint NOT NULL REFERENCES app.devices(id),
    order_ts    timestamptz NOT NULL,
    quantity    int NOT NULL CHECK (quantity > 0),
    amount      numeric(12,2) NOT NULL CHECK (amount >= 0)
);

-- На случай повторного запуска очищаем демоданные
TRUNCATE app.orders RESTART IDENTITY;

------------------------------------------------------------
-- ШАГ 2. Наполняем исходную таблицу заказов демоданными
-- Даты подобраны так, чтобы часть попала в архив, часть – в "текущий" месяц (февраль 2026)
------------------------------------------------------------

INSERT INTO app.orders (customer_id, device_id, order_ts, quantity, amount)
VALUES
-- 2025‑11 (архив)
(
  (SELECT id FROM app.user_accounts WHERE username = 'nikita_login'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-001'),
  '2025-11-10 10:00+00', 1, 300.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'slava_login'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-101'),
  '2025-11-15 12:30+00', 2, 500.00
),

-- 2025‑12 (архив)
(
  (SELECT id FROM app.user_accounts WHERE username = 'vlad_login'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-201'),
  '2025-12-05 09:15+00', 1, 800.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'vlad_login'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-202'),
  '2025-12-20 16:45+00', 1, 900.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'ops_user1'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-301'),
  '2025-12-22 18:10+00', 3, 450.00
),

-- 2026‑01 (архив)
(
  (SELECT id FROM app.user_accounts WHERE username = 'ops_user2'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-401'),
  '2026-01-03 11:00+00', 1, 700.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'viewer1'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-302'),
  '2026-01-10 13:20+00', 2, 260.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'viewer2'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-301'),
  '2026-01-17 09:40+00', 1, 150.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'service1'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-501'),
  '2026-01-25 19:05+00', 1, 1500.00
),

-- 2026‑02 (текущий месяц, секция current)
(
  (SELECT id FROM app.user_accounts WHERE username = 'nikita_login'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-002'),
  '2026-02-02 10:05+00', 1, 320.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'nikita_login'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-001'),
  '2026-02-05 14:30+00', 2, 640.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'slava_login'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-101'),
  '2026-02-08 09:50+00', 1, 260.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'vlad_login'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-201'),
  '2026-02-12 17:20+00', 1, 850.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'ops_user1'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-301'),
  '2026-02-15 08:10+00', 4, 600.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'ops_user2'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-401'),
  '2026-02-18 19:45+00', 1, 750.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'viewer1'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-302'),
  '2026-02-20 12:00+00', 1, 130.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'viewer2'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-301'),
  '2026-02-21 15:35+00', 2, 320.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'service1'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-501'),
  '2026-02-22 16:10+00', 1, 1600.00
),
(
  (SELECT id FROM app.user_accounts WHERE username = 'service2'),
  (SELECT id FROM app.devices       WHERE hw_serial = 'GW-601'),
  '2026-02-23 18:25+00', 1, 1400.00
);

------------------------------------------------------------
-- ШАГ 3. Создаём секционированную таблицу заказов
-- PARTITION BY RANGE(order_ts):
--   archive    : до 2026-02-01
--   current    : с 2026-02-01 по 2026-03-01
------------------------------------------------------------

DROP TABLE IF EXISTS app.orders_p CASCADE;

CREATE TABLE app.orders_p (
    id          bigserial PRIMARY KEY,
    customer_id bigint NOT NULL REFERENCES app.user_accounts(id),
    device_id   bigint NOT NULL REFERENCES app.devices(id),
    order_ts    timestamptz NOT NULL,
    quantity    int NOT NULL CHECK (quantity > 0),
    amount      numeric(12,2) NOT NULL CHECK (amount >= 0)
)
PARTITION BY RANGE (order_ts);

-- Архивная секция (все заказы до 01.02.2026 не включительно)
CREATE TABLE app.orders_p_archive
    PARTITION OF app.orders_p
    FOR VALUES FROM ('2025-01-01') TO ('2026-02-01');

-- Текущая секция (февраль 2026 – отчётный период)
CREATE TABLE app.orders_p_current
    PARTITION OF app.orders_p
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

-- Индексы (создаём на родительской таблице – PostgreSQL сделает локальные на партициях)
CREATE INDEX IF NOT EXISTS idx_orders_p_customer_ts
    ON app.orders_p (customer_id, order_ts);

CREATE INDEX IF NOT EXISTS idx_orders_p_device_ts
    ON app.orders_p (device_id, order_ts);

-- Переносим данные из несекционированной таблицы
INSERT INTO app.orders_p (id, customer_id, device_id, order_ts, quantity, amount)
SELECT id, customer_id, device_id, order_ts, quantity, amount
FROM app.orders;

------------------------------------------------------------
-- ШАГ 4. МЕТРИКИ (Task 2)
-- Все запросы используют CTE. Выполняются ПО ОТДЕЛЬНОСТИ!
------------------------------------------------------------

-------------------------------
-- 4.1 LTV (Lifetime Value)
-------------------------------
/*
Результат: клиент, его LTV (общая выручка), диапазон дат.
*/
WITH customer_ltv AS (
    SELECT
        o.customer_id,
        MIN(o.order_ts) AS first_order_ts,
        MAX(o.order_ts) AS last_order_ts,
        SUM(o.amount)   AS ltv_total
    FROM app.orders_p o
    GROUP BY o.customer_id
)
SELECT
    ua.id          AS customer_id,
    ua.username    AS customer_username,
    ua.first_name,
    ua.last_name,
    customer_ltv.first_order_ts,
    customer_ltv.last_order_ts,
    customer_ltv.ltv_total AS ltv
FROM customer_ltv
JOIN app.user_accounts ua ON ua.id = customer_ltv.customer_id
ORDER BY customer_ltv.ltv_total DESC;

-------------------------------
-- 4.2 AOV (Average Order Value)
-------------------------------
/*
Результат: ТОП‑5 клиентов по среднему чеку.
*/
WITH customer_stats AS (
    SELECT
        o.customer_id,
        COUNT(*)      AS orders_count,
        SUM(o.amount) AS total_amount
    FROM app.orders_p o
    GROUP BY o.customer_id
),
customer_aov AS (
    SELECT
        customer_id,
        total_amount / orders_count AS avg_order_value
    FROM customer_stats
)
SELECT
    ua.id       AS customer_id,
    ua.username,
    customer_aov.avg_order_value
FROM customer_aov
JOIN app.user_accounts ua ON ua.id = customer_aov.customer_id
ORDER BY customer_aov.avg_order_value DESC
LIMIT 5;

-------------------------------
-- Общие параметры периода для "текущей" секции (февраль 2026)
-------------------------------
/*
Для всех запросов Блока Б используем один и тот же период:
[2026‑02‑01, 2026‑03‑01).
*/
-- Примечание: это просто вспомогательный CTE, сам по себе ничего не делает.

-------------------------------
-- 4.3 ARPU за последний месяц
-------------------------------
WITH params AS (
    SELECT
        DATE '2026-02-01' AS period_start,
        DATE '2026-03-01' AS period_end
),
revenue_last_month AS (
    SELECT
        SUM(o.amount) AS revenue
    FROM app.orders_p o, params p
    WHERE o.order_ts >= p.period_start
      AND o.order_ts <  p.period_end
),
active_users AS (
    -- активные клиенты = делали хотя бы один заказ за всю историю
    SELECT COUNT(DISTINCT o.customer_id) AS cnt
    FROM app.orders_p o
),
arpu AS (
    SELECT
        r.revenue,
        a.cnt AS active_users,
        CASE WHEN a.cnt > 0 THEN r.revenue / a.cnt ELSE 0 END AS arpu_value
    FROM revenue_last_month r, active_users a
)
SELECT * FROM arpu;

-------------------------------
-- 4.4 ARPPU за последний месяц + EXPLAIN ANALYZE
-------------------------------
/*
При выполнении этого запроса:

EXPLAIN ANALYZE
WITH ...
SELECT ...

в плане должен быть Partition Pruning: будет сканироваться только секция app.orders_p_current.
*/
EXPLAIN ANALYZE
WITH params AS (
    SELECT
        DATE '2026-02-01' AS period_start,
        DATE '2026-03-01' AS period_end
),
monthly_orders AS (
    SELECT o.*
    FROM app.orders_p o, params p
    WHERE o.order_ts >= p.period_start
      AND o.order_ts <  p.period_end
),
revenue_last_month AS (
    SELECT SUM(amount) AS revenue
    FROM monthly_orders
),
paying_users_month AS (
    SELECT COUNT(DISTINCT customer_id) AS cnt
    FROM monthly_orders
),
arppu AS (
    SELECT
        r.revenue,
        p.cnt AS paying_users,
        CASE WHEN p.cnt > 0 THEN r.revenue / p.cnt ELSE 0 END AS arppu_value
    FROM revenue_last_month r, paying_users_month p
)
SELECT * FROM arppu;

-------------------------------
-- 4.5 Топ‑3 популярных товаров за месяц
-------------------------------
WITH params AS (
    SELECT
        DATE '2026-02-01' AS period_start,
        DATE '2026-03-01' AS period_end
),
monthly_orders AS (
    SELECT o.*
    FROM app.orders_p o, params p
    WHERE o.order_ts >= p.period_start
      AND o.order_ts <  p.period_end
),
product_stats AS (
    SELECT
        device_id,
        SUM(quantity) AS total_qty
    FROM monthly_orders
    GROUP BY device_id
)
SELECT
    d.id        AS device_id,
    d.hw_serial,
    d.model,
    product_stats.total_qty
FROM product_stats
JOIN app.devices d ON d.id = product_stats.device_id
ORDER BY product_stats.total_qty DESC
LIMIT 3;

-------------------------------
-- 4.6 Топ‑3 непопулярных товаров за месяц
-------------------------------
WITH params AS (
    SELECT
        DATE '2026-02-01' AS period_start,
        DATE '2026-03-01' AS period_end
),
monthly_orders AS (
    SELECT o.*
    FROM app.orders_p o, params p
    WHERE o.order_ts >= p.period_start
      AND o.order_ts <  p.period_end
),
product_stats AS (
    SELECT
        device_id,
        SUM(quantity) AS total_qty
    FROM monthly_orders
    GROUP BY device_id
)
SELECT
    d.id        AS device_id,
    d.hw_serial,
    d.model,
    product_stats.total_qty
FROM product_stats
JOIN app.devices d ON d.id = product_stats.device_id
ORDER BY product_stats.total_qty ASC
LIMIT 3;

------------------------------------------------------------
-- ШАГ 5. ИЗМЕНЕНИЯ СХЕМЫ И ДАННЫХ (Task 3)
-- 3 решения:
-- 1) признак VIP‑клиента по LTV
-- 2) скидка для непопулярных товаров
-- 3) сегментация клиентов по AOV
------------------------------------------------------------

-------------------------------
-- 5.1 Добавляем признак VIP‑клиента и выставляем его по LTV
-------------------------------

ALTER TABLE app.user_accounts
ADD COLUMN IF NOT EXISTS is_vip boolean DEFAULT false;

WITH customer_ltv AS (
    SELECT
        o.customer_id,
        SUM(o.amount) AS ltv_total
    FROM app.orders_p o
    GROUP BY o.customer_id
),
vip_candidates AS (
    -- Порог можно менять; здесь условно LTV >= 2000
    SELECT customer_id
    FROM customer_ltv
    WHERE ltv_total >= 2000
)
UPDATE app.user_accounts ua
SET is_vip = TRUE
FROM vip_candidates v
WHERE ua.id = v.customer_id;

-------------------------------
-- 5.2 Скидка для непопулярных товаров (по статистике за месяц)
-------------------------------

ALTER TABLE app.devices
ADD COLUMN IF NOT EXISTS discount_percent numeric(5,2) DEFAULT 0;

WITH params AS (
    SELECT
        DATE '2026-02-01' AS period_start,
        DATE '2026-03-01' AS period_end
),
monthly_orders AS (
    SELECT o.*
    FROM app.orders_p o, params p
    WHERE o.order_ts >= p.period_start
      AND o.order_ts <  p.period_end
),
product_stats AS (
    SELECT
        device_id,
        SUM(quantity) AS total_qty
    FROM monthly_orders
    GROUP BY device_id
),
unpopular AS (
    -- Берём 3 наименее популярных товара
    SELECT device_id
    FROM product_stats
    ORDER BY total_qty ASC
    LIMIT 3
)
UPDATE app.devices d
SET discount_percent = 15.0
FROM unpopular u
WHERE d.id = u.device_id;

-------------------------------
-- 5.3 Сегментация клиентов по AOV
-------------------------------

ALTER TABLE app.user_accounts
ADD COLUMN IF NOT EXISTS segment text;

WITH customer_stats AS (
    SELECT
        o.customer_id,
        COUNT(*)      AS orders_count,
        SUM(o.amount) AS total_amount
    FROM app.orders_p o
    GROUP BY o.customer_id
),
customer_aov AS (
    SELECT
        customer_id,
        total_amount / orders_count AS avg_order_value
    FROM customer_stats
)
UPDATE app.user_accounts ua
SET segment = CASE
    WHEN a.avg_order_value >= 800 THEN 'premium'
    WHEN a.avg_order_value >= 300 THEN 'standard'
    ELSE 'basic'
END
FROM customer_aov a
WHERE ua.id = a.customer_id;

------------------------------------------------------------
-- ШАГ 6. Привязка решений к бизнес‑процессу (расчёт цены)
-- Требование:
-- - скидка на неликвид берётся из app.devices.discount_percent
-- - VIP получает ДОП. скидку на неликвидный товар
-- - premium/standard получают скидку на любые покупки
-- Итог нужно уметь показать в виде конкретного вывода.
------------------------------------------------------------

-- 6.1 Добавляем базовую "лист‑цену" на устройство (для расчётов)
ALTER TABLE app.devices
ADD COLUMN IF NOT EXISTS list_price numeric(12,2) DEFAULT 0;

-- Заполняем лист‑цены (пример; можно менять)
UPDATE app.devices
SET list_price = CASE
  WHEN model ILIKE '%Edge%'       THEN 1600.00
  WHEN model ILIKE '%Industrial%' THEN 900.00
  WHEN model ILIKE '%Raspberry%'  THEN 320.00
  WHEN model ILIKE '%ESP32%'      THEN 260.00
  WHEN model ILIKE '%LoRa%'       THEN 150.00
  WHEN model ILIKE '%NB-IoT%'     THEN 700.00
  ELSE 500.00
END
WHERE list_price = 0;

-- 6.2 Функция расчёта цены с учётом скидок
CREATE OR REPLACE FUNCTION app.calc_order_price(
  p_customer_id bigint,
  p_device_id   bigint,
  p_quantity    int,
  p_order_ts    timestamptz
)
RETURNS TABLE(
  customer_id bigint,
  customer_username text,
  segment text,
  is_vip boolean,
  device_id bigint,
  hw_serial text,
  model text,
  quantity int,
  list_price numeric(12,2),
  base_amount numeric(12,2),
  device_discount_percent numeric(5,2),
  segment_discount_percent numeric(5,2),
  vip_extra_discount_percent numeric(5,2),
  total_discount_percent numeric(6,2),
  final_amount numeric(12,2)
)
LANGUAGE sql
STABLE
AS $$
WITH c AS (
  SELECT id, username, coalesce(segment,'basic') AS segment, coalesce(is_vip,false) AS is_vip
  FROM app.user_accounts
  WHERE id = p_customer_id
),
d AS (
  SELECT id, hw_serial, model, coalesce(discount_percent,0) AS device_disc, coalesce(list_price,0) AS list_price
  FROM app.devices
  WHERE id = p_device_id
),
rates AS (
  SELECT
    c.id AS customer_id,
    c.username AS customer_username,
    c.segment,
    c.is_vip,
    d.id AS device_id,
    d.hw_serial,
    d.model,
    p_quantity AS quantity,
    d.list_price,
    round((d.list_price * p_quantity)::numeric, 2) AS base_amount,
    round(d.device_disc::numeric, 2) AS device_discount_percent,
    round(
      CASE c.segment
        WHEN 'premium'  THEN 10.00
        WHEN 'standard' THEN  5.00
        ELSE 0.00
      END::numeric, 2
    ) AS segment_discount_percent,
    round(
      CASE
        -- VIP получает доп. скидку только на неликвид (т.е. где device_disc > 0)
        WHEN c.is_vip AND d.device_disc > 0 THEN 5.00
        ELSE 0.00
      END::numeric, 2
    ) AS vip_extra_discount_percent
  FROM c CROSS JOIN d
)
SELECT
  customer_id,
  customer_username,
  segment,
  is_vip,
  device_id,
  hw_serial,
  model,
  quantity,
  list_price,
  base_amount,
  device_discount_percent,
  segment_discount_percent,
  vip_extra_discount_percent,
  round((device_discount_percent + segment_discount_percent + vip_extra_discount_percent)::numeric, 2) AS total_discount_percent,
  round(
    (base_amount * (1 - (device_discount_percent + segment_discount_percent + vip_extra_discount_percent) / 100))::numeric,
    2
  ) AS final_amount
FROM rates;
$$;

-- 6.3 Демонстрационная "витрина" по заказам последнего месяца
CREATE OR REPLACE VIEW app.v_monthly_order_pricing AS
WITH params AS (
  SELECT DATE '2026-02-01' AS period_start, DATE '2026-03-01' AS period_end
),
orders_m AS (
  SELECT o.id AS order_id, o.customer_id, o.device_id, o.quantity, o.order_ts
  FROM app.orders_p o, params p
  WHERE o.order_ts >= p.period_start
    AND o.order_ts <  p.period_end
),
priced AS (
  SELECT
    om.order_id,
    (app.calc_order_price(om.customer_id, om.device_id, om.quantity, om.order_ts)).*
  FROM orders_m om
)
SELECT * FROM priced
ORDER BY order_id;

-- 6.4 Гарантируем наличие кейсов для демонстрации:
-- - VIP покупает неликвид (discount_percent > 0) в текущем месяце
WITH vip_user AS (
  SELECT id AS customer_id
  FROM app.user_accounts
  WHERE is_vip = true
  ORDER BY id
  LIMIT 1
),
unpopular_device AS (
  SELECT id AS device_id
  FROM app.devices
  WHERE coalesce(discount_percent,0) > 0
  ORDER BY id
  LIMIT 1
)
INSERT INTO app.orders_p (customer_id, device_id, order_ts, quantity, amount)
SELECT
  v.customer_id,
  u.device_id,
  '2026-02-24 10:00+00'::timestamptz,
  1,
  0
FROM vip_user v, unpopular_device u
WHERE NOT EXISTS (
  SELECT 1
  FROM app.orders_p o
  WHERE o.customer_id = v.customer_id
    AND o.device_id   = u.device_id
    AND o.order_ts   >= '2026-02-01'
    AND o.order_ts   <  '2026-03-01'
);

------------------------------------------------------------
-- ШАГ 7. КОНКРЕТНЫЕ ВЫВОДЫ ДЛЯ ОТЧЁТА (что “всё применилось”)
------------------------------------------------------------

-- 7.1 Показать, какие клиенты стали VIP и какие сегменты назначены
SELECT
  id,
  username,
  is_vip,
  segment
FROM app.user_accounts
ORDER BY is_vip DESC, segment, id;

-- 7.2 Показать неликвидные товары и назначенную скидку из devices.discount_percent
SELECT
  id AS device_id,
  hw_serial,
  model,
  list_price,
  discount_percent
FROM app.devices
ORDER BY discount_percent DESC, id;

-- 7.3 Показать расчёт цены: VIP клиент + неликвидный товар (видно 3 скидки)
WITH vip_user AS (
  SELECT id AS customer_id
  FROM app.user_accounts
  WHERE is_vip = true
  ORDER BY id
  LIMIT 1
),
unpopular_device AS (
  SELECT id AS device_id
  FROM app.devices
  WHERE coalesce(discount_percent,0) > 0
  ORDER BY id
  LIMIT 1
)
SELECT *
FROM app.calc_order_price(
  (SELECT customer_id FROM vip_user),
  (SELECT device_id FROM unpopular_device),
  1,
  '2026-02-24 10:00+00'
);

-- 7.4 Показать расчёт цены: premium и standard на ЛЮБОЙ покупке (скидка сегмента применяется всегда)
WITH any_device AS (
  SELECT id AS device_id
  FROM app.devices
  ORDER BY id
  LIMIT 1
),
premium_user AS (
  SELECT id AS customer_id
  FROM app.user_accounts
  WHERE segment = 'premium'
  ORDER BY id
  LIMIT 1
),
standard_user AS (
  SELECT id AS customer_id
  FROM app.user_accounts
  WHERE segment = 'standard'
  ORDER BY id
  LIMIT 1
)
SELECT 'premium' AS demo_case, *
FROM app.calc_order_price(
  (SELECT customer_id FROM premium_user),
  (SELECT device_id FROM any_device),
  1,
  '2026-02-24 11:00+00'
)
UNION ALL
SELECT 'standard' AS demo_case, *
FROM app.calc_order_price(
  (SELECT customer_id FROM standard_user),
  (SELECT device_id FROM any_device),
  1,
  '2026-02-24 11:05+00'
);

-- 7.5 Показать витрину по заказам за последний месяц: видно, что скидки реально считаются на заказах
SELECT
  order_id,
  customer_username,
  segment,
  is_vip,
  hw_serial,
  model,
  quantity,
  list_price,
  base_amount,
  device_discount_percent,
  segment_discount_percent,
  vip_extra_discount_percent,
  total_discount_percent,
  final_amount
FROM app.v_monthly_order_pricing
ORDER BY order_id;