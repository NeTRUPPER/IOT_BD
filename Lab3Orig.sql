-- Лабораторная работа №3
-- Работа с шифрованием данных (PostgreSQL, БД iot)
-- Запускать от суперпользователя БД (postgres), т.к. есть доступ к pg_authid и ALTER SYSTEM.

SET search_path = app, public;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

------------------------------------------------------------
-- ЗАДАНИЕ 1. Шифрование паролей в PostgreSQL
------------------------------------------------------------

-- Текущая политика хеширования паролей PostgreSQL.
SHOW password_encryption;

-- Проверка фактического формата хеша в pg_authid.
SELECT rolname, rolpassword 
FROM pg_authid 
WHERE rolname IN ('nikita_login', 'slava_login', 'vlad_login', 'auditor_login')
ORDER BY rolname;

-- Решение: использовать SCRAM-SHA-256.
-- Обоснование:
-- 1) MD5 устарел и имеет значительно более слабую криптостойкость.
-- 2) SCRAM-SHA-256 поддерживает безопасную аутентификацию и рекомендуем в новых установках.
-- 3) Совместим с актуальными клиентами PostgreSQL.

------------------------------------------------------------
-- ЗАДАНИЕ 2. Шифрование избранных столбцов
------------------------------------------------------------
-- В этом разделе сразу встроены требования Задания 4 (хранение ключей)
-- и Задания 5 (перфоманс до/после), т.к. они технологически связаны.
--
-- Выбранные таблицы:
-- 1) app.user_accounts.email            -> симметричный ключ (PGP Symmetric)
-- 2) app.devices.location_desc          -> открытый ключ (PGP Public Key)
--
-- Важно: работаем БЕЗ дополнительных колонок, шифруем поля "на месте".
-- Чтобы хранить шифртекст в text-полях, используем armored формат:
-- armor(pgp_*_encrypt(...)) и dearmor(...) при расшифровке.

-- 2.0 Безопасное хранение ключей (часть Задания 4)
-- Рабочие ключи не храним в прикладных таблицах, только метаданные/ссылки на KMS/Vault.
CREATE TABLE IF NOT EXISTS app.keys (
    name      text PRIMARY KEY,
    purpose   text NOT NULL,
    link      text NOT NULL,
    period    interval NOT NULL DEFAULT interval '90 days',
    created   timestamptz NOT NULL DEFAULT now(),
    updated   timestamptz NOT NULL DEFAULT now()
);

INSERT INTO app.keys(name, purpose, link, period)
VALUES
('lab3_sym_email', 'encrypt app.user_accounts.email', 'vault://iot/lab3/sym/email', interval '90 days'),
('lab3_pgp_loc',   'encrypt app.devices.location_desc', 'vault://iot/lab3/pgp/location', interval '180 days')
ON CONFLICT (name) DO NOTHING;

-- 2.0.1 Baseline замеры ДО шифрования (часть Задания 5)
EXPLAIN ANALYZE
SELECT id, username, email
FROM app.user_accounts
WHERE email LIKE '%.com';

EXPLAIN ANALYZE
SELECT id, hw_serial, location_desc
FROM app.devices
WHERE location_desc ILIKE '%Цех%';

EXPLAIN ANALYZE
INSERT INTO app.user_accounts (username, email, last_name, first_name, middle_name)
VALUES ('u_pre', 'u_pre@example.com', 'Perf', 'Pre', NULL)
ON CONFLICT (username) DO NOTHING;

-- 2.1 Симметричное шифрование email
-- Ключ задаем в сессии. Для лабы допустимо; в проде ключи из Vault/KMS/HSM.
SELECT set_config('app.sym_key', 'lab3_sym_key_2026', false);

UPDATE app.user_accounts
SET email = armor(pgp_sym_encrypt(email, current_setting('app.sym_key')))
WHERE email IS NOT NULL;

-- Проверка (должен появиться читаемый email)
SELECT username, 
       pgp_sym_decrypt(dearmor(email), current_setting('app.sym_key')) as decrypted
FROM app.user_accounts LIMIT 10;

-- Без ключа виден только шифртекст.
SELECT id, username, email
FROM app.user_accounts
ORDER BY id
LIMIT 10;

-- С ключом получаем расшифрованный email.
SELECT
    id,
    username,
    pgp_sym_decrypt(dearmor(email), current_setting('app.sym_key')) AS email_decrypted
FROM app.user_accounts
ORDER BY id
LIMIT 10;

-- 2.2 Асимметричное шифрование location_desc (PGP public/private)
-- Вставьте реальные armored-ключи вместо заглушек.
CREATE TABLE IF NOT EXISTS app.pgpkeys (
    id                  smallint PRIMARY KEY DEFAULT 1,
    pub                 text NOT NULL,
    priv                text NOT NULL,
    pass                text
);

INSERT INTO app.pgpkeys(id, pub, priv, pass)
VALUES
(
    1,
    '-----BEGIN PGP PUBLIC KEY BLOCK-----

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
=3dMG
-----END PGP PUBLIC KEY BLOCK-----',
    '-----BEGIN PGP PRIVATE KEY BLOCK-----

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
=xUZ/
-----END PGP PRIVATE KEY BLOCK-----
',
    '321027'
)
ON CONFLICT (id) DO UPDATE
SET pub  = EXCLUDED.pub,
    priv = EXCLUDED.priv,
    pass = EXCLUDED.pass;

DO $$
DECLARE
    v_pub text;
BEGIN
    SELECT pub INTO v_pub
    FROM app.pgpkeys
    WHERE id = 1;
    UPDATE app.devices
    SET location_desc = armor(pgp_pub_encrypt(location_desc, dearmor(v_pub)))
    WHERE location_desc IS NOT NULL;
END;
$$;

-- Без private key виден только ciphertext.
SELECT id, hw_serial, location_desc
FROM app.devices
ORDER BY id
LIMIT 10;

-- Выполните вручную после подстановки реальных ключей:
SELECT
    id,
    hw_serial,
    pgp_pub_decrypt(
        dearmor(location_desc),
        dearmor((SELECT priv FROM app.pgpkeys WHERE id = 1)),
        (SELECT pass FROM app.pgpkeys WHERE id = 1)
     ) AS location_desc_decrypted
FROM app.devices
ORDER BY id
LIMIT 10;

-- 2.3 Замеры ПОСЛЕ шифрования (часть Задания 5)
EXPLAIN ANALYZE
SELECT
    id,
    username,
    pgp_sym_decrypt(dearmor(email), current_setting('app.sym_key')) AS email_decrypted
FROM app.user_accounts
WHERE pgp_sym_decrypt(dearmor(email), current_setting('app.sym_key')) LIKE '%@example.com';

DO $$
DECLARE
    v_priv text;
BEGIN
    SELECT priv INTO v_priv
    FROM app.pgpkeys
    WHERE id = 1;

    IF v_priv LIKE '%REPLACE_WITH_REAL_PRIVATE_KEY%' THEN
        RAISE NOTICE 'EXPLAIN ANALYZE для location_desc с decrypt пропущен: вставьте реальный private key в app.pgpkeys.';
    ELSE
        EXECUTE $q$
            EXPLAIN ANALYZE
            SELECT id, hw_serial,
                   pgp_pub_decrypt(
                       dearmor(location_desc),
                       dearmor((SELECT priv FROM app.pgpkeys WHERE id = 1)),
                       (SELECT pass FROM app.pgpkeys WHERE id = 1)
                   ) AS loc
            FROM app.devices
            WHERE pgp_pub_decrypt(
                      dearmor(location_desc),
                      dearmor((SELECT priv FROM app.pgpkeys WHERE id = 1)),
                      (SELECT pass FROM app.pgpkeys WHERE id = 1)
                  ) ILIKE '%сервер%';
        $q$;
    END IF;
END;
$$;

EXPLAIN ANALYZE
INSERT INTO app.user_accounts (username, email, last_name, first_name, middle_name)
VALUES (
    'u_post',
    armor(pgp_sym_encrypt('u_post@example.com', current_setting('app.sym_key'))),
    'Perf',
    'Post',
    NULL
)
ON CONFLICT (username) DO NOTHING;

------------------------------------------------------------
-- ЗАДАНИЕ 3. SSL при передаче данных (опционально, но для >10 баллов)
------------------------------------------------------------
-- Конфиги у вас в проекте:
-- - db/conf/postgresql.conf
-- - db/conf/pg_hba.conf
-- - db/conf/ssl/server.crt
-- - db/conf/ssl/server.key
--
-- Проверка на стороне PostgreSQL:
SHOW ssl;
SHOW ssl_cert_file;
SHOW ssl_key_file;

-- Проверка SSL для текущего подключения.
SELECT ssl, version, cipher, bits
FROM pg_stat_ssl
WHERE pid = pg_backend_pid();

-- Для демонстрации в psql дополнительно:
-- \conninfo
-- В выводе должна быть строка с "SSL connection ...".

------------------------------------------------------------
-- ЗАДАНИЕ 4. Безопасное хранение ключей
------------------------------------------------------------
-- Выполнено в разделе 2 (блок 2.0):
-- создана таблица app.keys и добавлены записи о ключах.
SELECT *
FROM app.keys
ORDER BY name;

------------------------------------------------------------
-- ЗАДАНИЕ 5. Тесты производительности до/после шифрования
------------------------------------------------------------
-- Выполнено в разделе 2:
-- 2.0.1 baseline замеры до шифрования и 2.3 замеры после шифрования.

-- 5.2 Влияние SSL-шифрования канала (через pg_stat_statements/pgbench)
-- Рекомендуемый сценарий для отчета:
-- 1) Прогнать одинаковый набор запросов при sslmode=disable и sslmode=require.
-- 2) Сравнить latency/throughput (например, pgbench -T 30).
-- 3) Подтвердить SSL-сессию через pg_stat_ssl.
--
-- Пример команд:
-- pgbench -h 127.0.0.1 -p 5432 -U postgres -d iot -c 5 -j 2 -T 30 "sslmode=disable"
-- pgbench -h 127.0.0.1 -p 5432 -U postgres -d iot -c 5 -j 2 -T 30 "sslmode=require"

------------------------------------------------------------
-- ЗАДАНИЕ 6. Выводы по методам и влиянию на производительность
------------------------------------------------------------
-- 1) MD5-хеши паролей:
--    + совместимость со старыми клиентами
--    - низкая криптостойкость, не рекомендуется для новых систем
--
-- 2) SCRAM-SHA-256:
--    + современный и безопасный стандарт для паролей PostgreSQL
--    + защита лучше, чем у MD5
--    - может потребовать обновления очень старых клиентов
--
-- 3) Симметричное шифрование (pgp_sym_encrypt):
--    + быстрее асимметричного, удобно для массовых данных
--    - ключ должен быть доступен приложению, риск компрометации ключа
--
-- 4) Асимметричное шифрование (pgp_pub_encrypt):
--    + разделение прав: шифровать можно по public key, расшифровать только private key
--    - медленнее, сложнее управление ключами
--
-- 5) SSL/TLS при передаче:
--    + защищает канал от перехвата/подмены
--    - небольшие накладные расходы на handshake и шифрование трафика
--
-- 6) Влияние на вашу предметную область (IoT):
--    + оправдано для чувствительных полей (email, location, токены, ключи)
--    + SSL обязателен для удаленных подключений и телеметрии
--    - дешифрование в WHERE/SELECT и шифрование в INSERT/UPDATE повышают CPU-нагрузку и latency
--    - требуется стратегия ротации и хранения ключей (Vault/KMS/HSM)

