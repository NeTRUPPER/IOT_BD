-- 002_seed.sql
-- Наполнение БД тестовыми данными

SET search_path = app, public;

-- =========================================================
-- Справочники ref.*
-- =========================================================

INSERT INTO ref.units (code, name, symbol)
VALUES
  ('C',    'Градусы Цельсия', '°C'),
  ('F',    'Градусы Фаренгейта', '°F'),
  ('PERC', 'Проценты', '%'),
  ('PA',   'Паскаль', 'Pa'),
  ('HPA',  'Гектопаскаль', 'hPa'),
  ('MPS',  'Метры в секунду', 'm/s'),
  ('LUX',  'Люкс', 'lx'),
  ('PPM',  'Части на миллион', 'ppm'),
  ('V',    'Вольт', 'V'),
  ('A',    'Ампер', 'A')
ON CONFLICT (code) DO NOTHING;

INSERT INTO ref.sensor_types (code, name, description)
VALUES
  ('TEMP',   'Датчик температуры', 'Измеряет температуру окружающей среды'),
  ('HUM',    'Датчик влажности',   'Измеряет относительную влажность воздуха'),
  ('PRESS',  'Датчик давления',    'Атмосферное давление'),
  ('CO2',    'Датчик CO2',         'Измеряет концентрацию CO2'),
  ('LIGHT',  'Датчик освещённости','Яркость в люксах'),
  ('MOTION', 'Датчик движения',    'Фиксация движения'),
  ('SMOKE',  'Датчик дыма',        'Пожарный датчик'),
  ('POWER',  'Датчик мощности',    'Мощность потребления'),
  ('VOLT',   'Датчик напряжения',  'Напряжение питания'),
  ('CURR',   'Датчик тока',        'Ток потребления')
ON CONFLICT (code) DO NOTHING;

-- =========================================================
-- Пользователи приложений (должны совпадать с login‑ролями)
-- =========================================================

INSERT INTO app.user_accounts (username, email, last_name, first_name, middle_name)
VALUES
  ('nikita_login', 'nikita@example.com', 'Иванов',  'Никита',  'Сергеевич'),
  ('slava_login',  'slava@example.com',  'Петров',  'Вячеслав','Игоревич'),
  ('vlad_login',   'vlad@example.com',   'Сидоров', 'Владимир','Алексеевич'),
  ('auditor_login','audit@example.com',  'Кузнецов','Максим',  'Олегович'),
  ('ops_user1',    'ops1@example.com',   'Орлов',   'Дмитрий', 'Павлович'),
  ('ops_user2',    'ops2@example.com',   'Егоров',  'Андрей',  'Ильич'),
  ('viewer1',      'viewer1@example.com','Фёдоров', 'Сергей',  'Николаевич'),
  ('viewer2',      'viewer2@example.com','Романов', 'Антон',   'Сергеевич'),
  ('service1',     'service1@example.com','Морозов','Олег',    'Петрович'),
  ('service2',     'service2@example.com','Волков', 'Илья',    'Андреевич')
ON CONFLICT (username) DO NOTHING;

-- =========================================================
-- Устройства
-- =========================================================

INSERT INTO app.devices (owner_id, hw_serial, model, location_desc)
SELECT u.id, v.hw_serial, v.model, v.location_desc
FROM app.user_accounts u
JOIN (
  VALUES
    ('nikita_login', 'GW-001', 'Raspberry Pi 4', 'Лаборатория, стойка 1'),
    ('nikita_login', 'GW-002', 'Raspberry Pi 4', 'Лаборатория, стойка 2'),
    ('slava_login',  'GW-101', 'ESP32 Gateway',  'Офис, переговорка'),
    ('vlad_login',   'GW-201', 'Industrial PLC', 'Цех №1, щитовая'),
    ('vlad_login',   'GW-202', 'Industrial PLC', 'Цех №2, щитовая'),
    ('ops_user1',    'GW-301', 'LoRa Gateway',   'Склад, северная стена'),
    ('ops_user1',    'GW-302', 'LoRa Gateway',   'Склад, южная стена'),
    ('ops_user2',    'GW-401', 'NB-IoT Hub',     'Котельная'),
    ('service1',     'GW-501', 'Edge Server',    'Серверная'),
    ('service2',     'GW-601', 'Edge Server',    'Резервная серверная')
) AS v(username, hw_serial, model, location_desc)
  ON u.username = v.username
ON CONFLICT (hw_serial) DO NOTHING;

-- =========================================================
-- Датчики
-- =========================================================

INSERT INTO app.sensors (device_id, sensor_type_id, unit_id, name)
VALUES
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-001'),
    (SELECT id FROM ref.sensor_types WHERE code = 'TEMP'),
    (SELECT id FROM ref.units        WHERE code = 'C'),
    'temp_room'
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-001'),
    (SELECT id FROM ref.sensor_types WHERE code = 'HUM'),
    (SELECT id FROM ref.units        WHERE code = 'PERC'),
    'hum_room'
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-001'),
    (SELECT id FROM ref.sensor_types WHERE code = 'CO2'),
    (SELECT id FROM ref.units        WHERE code = 'PPM'),
    'co2_room'
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-101'),
    (SELECT id FROM ref.sensor_types WHERE code = 'TEMP'),
    (SELECT id FROM ref.units        WHERE code = 'C'),
    'temp_meeting'
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-101'),
    (SELECT id FROM ref.sensor_types WHERE code = 'LIGHT'),
    (SELECT id FROM ref.units        WHERE code = 'LUX'),
    'light_meeting'
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-201'),
    (SELECT id FROM ref.sensor_types WHERE code = 'PRESS'),
    (SELECT id FROM ref.units        WHERE code = 'HPA'),
    'press_ceh1'
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-202'),
    (SELECT id FROM ref.sensor_types WHERE code = 'PRESS'),
    (SELECT id FROM ref.units        WHERE code = 'HPA'),
    'press_ceh2'
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-301'),
    (SELECT id FROM ref.sensor_types WHERE code = 'MOTION'),
    (SELECT id FROM ref.units        WHERE code = 'PERC'),
    'motion_sklad_n'
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-302'),
    (SELECT id FROM ref.sensor_types WHERE code = 'MOTION'),
    (SELECT id FROM ref.units        WHERE code = 'PERC'),
    'motion_sklad_s'
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-401'),
    (SELECT id FROM ref.sensor_types WHERE code = 'TEMP'),
    (SELECT id FROM ref.units        WHERE code = 'C'),
    'temp_boiler'
  )
ON CONFLICT (device_id, name) DO NOTHING;

-- =========================================================
-- ACL: доступ пользователей к устройствам
-- =========================================================

INSERT INTO app.device_user_acl (device_id, user_id, role_in_device, granted_by)
VALUES
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-001'),
    (SELECT id FROM app.user_accounts WHERE username = 'slava_login'),
    'viewer',
    (SELECT id FROM app.user_accounts WHERE username = 'nikita_login')
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-001'),
    (SELECT id FROM app.user_accounts WHERE username = 'vlad_login'),
    'operator',
    (SELECT id FROM app.user_accounts WHERE username = 'nikita_login')
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-002'),
    (SELECT id FROM app.user_accounts WHERE username = 'vlad_login'),
    'viewer',
    (SELECT id FROM app.user_accounts WHERE username = 'nikita_login')
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-101'),
    (SELECT id FROM app.user_accounts WHERE username = 'nikita_login'),
    'operator',
    (SELECT id FROM app.user_accounts WHERE username = 'slava_login')
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-201'),
    (SELECT id FROM app.user_accounts WHERE username = 'ops_user1'),
    'operator',
    (SELECT id FROM app.user_accounts WHERE username = 'vlad_login')
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-201'),
    (SELECT id FROM app.user_accounts WHERE username = 'viewer1'),
    'viewer',
    (SELECT id FROM app.user_accounts WHERE username = 'vlad_login')
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-202'),
    (SELECT id FROM app.user_accounts WHERE username = 'ops_user2'),
    'operator',
    (SELECT id FROM app.user_accounts WHERE username = 'vlad_login')
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-301'),
    (SELECT id FROM app.user_accounts WHERE username = 'viewer2'),
    'viewer',
    (SELECT id FROM app.user_accounts WHERE username = 'ops_user1')
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-302'),
    (SELECT id FROM app.user_accounts WHERE username = 'viewer1'),
    'viewer',
    (SELECT id FROM app.user_accounts WHERE username = 'ops_user1')
  ),
  (
    (SELECT id FROM app.devices WHERE hw_serial = 'GW-401'),
    (SELECT id FROM app.user_accounts WHERE username = 'service1'),
    'owner',
    (SELECT id FROM app.user_accounts WHERE username = 'ops_user2')
  )
ON CONFLICT (device_id, user_id) DO NOTHING;

-- =========================================================
-- Секреты устройств
-- =========================================================

INSERT INTO app.device_secrets (device_id, secret_ciphertext, secret_type, expires_at)
SELECT d.id,
       digest(d.hw_serial || '_secret', 'sha256')::bytea,
       'auth_token',
       now() + interval '90 days'
FROM app.devices d
LIMIT 10
ON CONFLICT DO NOTHING;

-- =========================================================
-- API‑ключи пользователей
-- =========================================================

INSERT INTO app.api_keys (user_id, key_hash, key_name, expires_at)
SELECT ua.id,
       digest(ua.username || '_api_key1', 'sha256')::bytea,
       'default_key',
       now() + interval '30 days'
FROM app.user_accounts ua
WHERE ua.username IN ('nikita_login','slava_login','vlad_login','ops_user1','ops_user2',
                      'viewer1','viewer2','service1','service2','auditor_login')
ON CONFLICT DO NOTHING;

-- =========================================================
-- Команды к устройствам
-- =========================================================

INSERT INTO app.device_commands (device_id, issued_by, cmd, cmd_params_json, status)
SELECT d.id,
       ua.id,
       v.cmd,
       v.params::jsonb,
       v.status
FROM (
  VALUES
    ('GW-001','nikita_login','reboot',    '{"delay_sec":10}',   'queued'),
    ('GW-001','nikita_login','set_mode',  '{"mode":"eco"}',     'sent'),
    ('GW-101','slava_login', 'set_limit', '{"sensor":"temp","max":28}','acked'),
    ('GW-201','vlad_login',  'reboot',    '{"delay_sec":5}',    'error'),
    ('GW-201','ops_user1',   'set_mode',  '{"mode":"performance"}','queued'),
    ('GW-202','ops_user2',   'set_mode',  '{"mode":"standby"}', 'queued'),
    ('GW-301','ops_user1',   'ping',      '{"count":5}',        'acked'),
    ('GW-302','ops_user2',   'ping',      '{"count":3}',        'sent'),
    ('GW-401','service1',    'update_fw', '{"version":"1.2.3"}','queued'),
    ('GW-501','service2',    'update_fw', '{"version":"1.2.3"}','queued')
) AS v(hw_serial, username, cmd, params, status)
JOIN app.devices d        ON d.hw_serial = v.hw_serial
JOIN app.user_accounts ua ON ua.username = v.username
ON CONFLICT DO NOTHING;

-- =========================================================
-- Показания датчиков
-- 10 показаний на каждый датчик
-- =========================================================

INSERT INTO app.sensor_readings (sensor_id, ts, value, quality)
SELECT s.id,
       now() - g * interval '5 minutes' AS ts,
       20.0 + (random() * 5.0)         AS value,
       90 + (g % 10)                   AS quality
FROM app.sensors s
JOIN generate_series(1,10) AS g ON true
ON CONFLICT (sensor_id, ts) DO NOTHING;

-- =========================================================
-- Сырые данные ingest_raw
-- =========================================================

INSERT INTO stg.ingest_raw (payload_json, source, processed)
SELECT
  jsonb_build_object(
    'device', d.hw_serial,
    'ts',     now() - (g * interval '1 minute'),
    'payload', jsonb_build_object('test', g)
  ),
  'test_source',
  false
FROM app.devices d
JOIN generate_series(1,10) AS g ON true
LIMIT 100;

