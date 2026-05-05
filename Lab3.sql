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
    '-----BEGIN PGP PUBLIC KEY BLOCK-----\nREPLACE_WITH_REAL_PUBLIC_KEY\n-----END PGP PUBLIC KEY BLOCK-----',
    '-----BEGIN PGP PRIVATE KEY BLOCK-----\nREPLACE_WITH_REAL_PRIVATE_KEY\n-----END PGP PRIVATE KEY BLOCK-----',
    'REPLACE_WITH_PASSPHRASE'
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

-- Расшифровка с private key (+ passphrase).
DO $$
DECLARE
    v_priv text;
    v_pass text;
BEGIN
    SELECT priv, pass
    INTO v_priv, v_pass
    FROM app.pgpkeys
    WHERE id = 1;

    IF v_priv LIKE '%REPLACE_WITH_REAL_PRIVATE_KEY%' THEN
        RAISE NOTICE 'Расшифровка location_desc пропущена: вставьте реальный private key.';
    ELSE
        RAISE NOTICE 'Пример запроса расшифровки:';
        RAISE NOTICE 'SELECT id, hw_serial, pgp_pub_decrypt(dearmor(location_desc), dearmor((SELECT priv FROM app.pgpkeys WHERE id=1)), (SELECT pass FROM app.pgpkeys WHERE id=1)) FROM app.devices ORDER BY id LIMIT 10;';
    END IF;
END;
$$;

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

