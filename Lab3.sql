-- Лабораторная работа №3
-- Работа с шифрованием данных (PostgreSQL, БД iot)
-- Запускать от суперпользователя БД (iot_dba), т.к. есть доступ к pg_authid и ALTER SYSTEM.

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

-- Для шифртекста в "исходных" колонках увеличиваем тип до text.
-- Иначе armored PGP-строки не помещаются в varchar.
ALTER TABLE app.user_accounts
ALTER COLUMN email TYPE text;

ALTER TABLE app.devices
ALTER COLUMN location_desc TYPE text;

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
-- Ключи грузим как в проде: из Vault (через psql-переменные).
vault server -dev -dev-root-token-id=root
vault kv get secret/iot/lab3
-- Пример перед запуском скрипта:
-- export VAULT_ADDR='http://127.0.0.1:8200'
-- export VAULT_TOKEN='root'
-- \set sym_key  `vault kv get -field=sym  secret/iot/lab3`
-- \set pgp_pub  `vault kv get -field=pub  secret/iot/lab3`
-- \set pgp_priv `vault kv get -field=priv secret/iot/lab3`
-- \set pgp_pass `vault kv get -field=pass secret/iot/lab3`
SELECT set_config('app.sym_key',  :'sym_key',  false);
SELECT set_config('app.pgp_pub',  :'pgp_pub',  false);
SELECT set_config('app.pgp_priv', :'pgp_priv', false);
SELECT set_config('app.pgp_pass', :'pgp_pass', false);

DO $$
DECLARE
    v_sym text;
BEGIN
    v_sym := current_setting('app.sym_key', true);

    IF v_sym IS NULL OR length(v_sym) = 0 THEN
        RAISE NOTICE 'Симметричное шифрование email пропущено: не задан app.sym_key (Vault).';
    ELSE
        UPDATE app.user_accounts
        SET email = armor(pgp_sym_encrypt(email, v_sym))
        WHERE email IS NOT NULL
          AND email NOT LIKE '-----BEGIN PGP MESSAGE-----%';
    END IF;
END;
$$;

-- Без ключа виден только шифртекст.
SELECT id, username, email
FROM app.user_accounts
ORDER BY id
LIMIT 10;

-- С ключом получаем расшифрованный email.
DO $$
DECLARE
    v_sym text;
BEGIN
    v_sym := current_setting('app.sym_key', true);

    IF v_sym IS NULL OR length(v_sym) = 0 THEN
        RAISE NOTICE 'Расшифровка email пропущена: не задан app.sym_key (Vault).';
    ELSE
        RAISE NOTICE 'Пример запроса расшифровки email:';
        RAISE NOTICE 'SELECT id, username, pgp_sym_decrypt(dearmor(email), current_setting(''app.sym_key'')) AS email_decrypted FROM app.user_accounts WHERE email LIKE ''-----BEGIN PGP MESSAGE-----%%'' ORDER BY id LIMIT 10;';
    END IF;
END;
$$;

-- 2.2 Асимметричное шифрование location_desc (PGP public/private)
-- Ключи берем из текущей сессии (подтянуты из Vault).

DO $$
DECLARE
    v_pub text;
BEGIN
    v_pub := current_setting('app.pgp_pub', true);

    IF v_pub IS NULL OR length(v_pub) = 0 THEN
        RAISE NOTICE 'PGP public-key шифрование пропущено: не задан app.pgp_pub (загрузите ключ из Vault).';
    ELSIF v_pub NOT LIKE '-----BEGIN PGP PUBLIC KEY BLOCK-----%' OR v_pub NOT LIKE '%-----END PGP PUBLIC KEY BLOCK-----' OR position('...' IN v_pub) > 0 THEN
        RAISE NOTICE 'PGP public-key шифрование пропущено: app.pgp_pub не похож на валидный armored public key.';
    ELSE
        UPDATE app.devices
        SET location_desc = armor(pgp_pub_encrypt(location_desc, dearmor(v_pub)))
        WHERE location_desc IS NOT NULL;
    END IF;
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
    v_priv := current_setting('app.pgp_priv', true);
    v_pass := current_setting('app.pgp_pass', true);

    IF v_priv IS NULL OR length(v_priv) = 0 THEN
        RAISE NOTICE 'Расшифровка location_desc пропущена: не задан app.pgp_priv (загрузите ключ из Vault).';
    ELSIF v_priv NOT LIKE '-----BEGIN PGP PRIVATE KEY BLOCK-----%' OR v_priv NOT LIKE '%-----END PGP PRIVATE KEY BLOCK-----' OR position('...' IN v_priv) > 0 THEN
        RAISE NOTICE 'Расшифровка location_desc пропущена: app.pgp_priv не похож на валидный armored private key.';
    ELSE
        RAISE NOTICE 'Пример запроса расшифровки:';
        RAISE NOTICE 'SELECT id, hw_serial, pgp_pub_decrypt(dearmor(location_desc), dearmor(current_setting(''app.pgp_priv'')), current_setting(''app.pgp_pass'')) FROM app.devices ORDER BY id LIMIT 10;';
    END IF;
END;
$$;

-- Выполните вручную после подстановки реальных ключей:
SELECT
     id,
     hw_serial,
     pgp_pub_decrypt(
         dearmor(location_desc),
         dearmor(current_setting('app.pgp_priv')),
         current_setting('app.pgp_pass')
     ) AS location_desc_decrypted
FROM app.devices
ORDER BY id
LIMIT 10;

-- 2.3 Замеры ПОСЛЕ шифрования (часть Задания 5)
DO $$
DECLARE
    v_sym text;
BEGIN
    v_sym := current_setting('app.sym_key', true);

    IF v_sym IS NULL OR length(v_sym) = 0 THEN
        RAISE NOTICE 'EXPLAIN ANALYZE для email с decrypt пропущен: не задан app.sym_key (Vault).';
    ELSE
        EXECUTE $q$
            EXPLAIN ANALYZE
            SELECT
                id,
                username,
                pgp_sym_decrypt(dearmor(email), current_setting('app.sym_key')) AS email_decrypted
            FROM app.user_accounts
            WHERE email LIKE '-----BEGIN PGP MESSAGE-----%'
              AND pgp_sym_decrypt(dearmor(email), current_setting('app.sym_key')) LIKE '%@example.com';
        $q$;
    END IF;
END;
$$;

DO $$
DECLARE
    v_priv text;
BEGIN
    v_priv := current_setting('app.pgp_priv', true);

    IF v_priv IS NULL OR length(v_priv) = 0 THEN
        RAISE NOTICE 'EXPLAIN ANALYZE для location_desc с decrypt пропущен: не задан app.pgp_priv (Vault).';
    ELSIF v_priv NOT LIKE '-----BEGIN PGP PRIVATE KEY BLOCK-----%' OR v_priv NOT LIKE '%-----END PGP PRIVATE KEY BLOCK-----' OR position('...' IN v_priv) > 0 THEN
        RAISE NOTICE 'EXPLAIN ANALYZE для location_desc с decrypt пропущен: app.pgp_priv невалидный.';
    ELSE
        EXECUTE $q$
            EXPLAIN ANALYZE
            SELECT id, hw_serial,
                   pgp_pub_decrypt(
                       dearmor(location_desc),
                       dearmor(current_setting('app.pgp_priv')),
                       current_setting('app.pgp_pass')
                   ) AS loc
            FROM app.devices
            WHERE pgp_pub_decrypt(
                      dearmor(location_desc),
                      dearmor(current_setting('app.pgp_priv')),
                      current_setting('app.pgp_pass')
                  ) ILIKE '%сервер%';
        $q$;
    END IF;
END;
$$;

DO $$
DECLARE
    v_sym text;
BEGIN
    v_sym := current_setting('app.sym_key', true);

    IF v_sym IS NULL OR length(v_sym) = 0 THEN
        RAISE NOTICE 'EXPLAIN ANALYZE INSERT с шифрованием email пропущен: не задан app.sym_key (Vault).';
    ELSE
        EXECUTE $q$
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
        $q$;
    END IF;
END;
$$;

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
-- pgbench -h 127.0.0.1 -p 5432 -U iot_dba -d iot -c 5 -j 2 -T 30 "sslmode=disable"
-- pgbench -h 127.0.0.1 -p 5432 -U iot_dba -d iot -c 5 -j 2 -T 30 "sslmode=require"

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

