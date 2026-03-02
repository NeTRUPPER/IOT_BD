-- 001_schema.sql
-- Инициализация схемы БД iot: роли, схемы, таблицы, функции, политики

-- Подключаем расширение для функции digest()
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

-- =========================================================
-- Роли
-- =========================================================

-- Прикладные роли (без логина)
CREATE ROLE app_owner WITH
  NOLOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

CREATE ROLE app_reader WITH
  NOLOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

CREATE ROLE app_writer WITH
  NOLOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

CREATE ROLE auditor WITH
  NOLOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

CREATE ROLE ddl_admin WITH
  NOLOGIN NOSUPERUSER NOINHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

CREATE ROLE dml_admin WITH
  NOLOGIN NOSUPERUSER NOINHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

CREATE ROLE security_admin WITH
  NOLOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

-- Логин‑роли пользователей
CREATE ROLE auditor_login WITH
  LOGIN PASSWORD 'auditor_pass'
  NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

CREATE ROLE nikita_login WITH
  LOGIN PASSWORD 'nikita_pass'
  NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

CREATE ROLE slava_login WITH
  LOGIN PASSWORD 'slava_pass'
  NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

CREATE ROLE vlad_login WITH
  LOGIN PASSWORD 'vlad_pass'
  NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

-- Связь логин‑ролей с прикладными
GRANT auditor TO auditor_login;
GRANT app_owner TO nikita_login;
GRANT app_reader TO slava_login;
GRANT app_writer TO vlad_login;

-- =========================================================
-- Права на базу (сама БД iot создаётся контейнером через POSTGRES_DB)
-- =========================================================

GRANT CONNECT ON DATABASE iot TO auditor_login;
GRANT CONNECT ON DATABASE iot TO nikita_login;
GRANT ALL     ON DATABASE iot TO postgres;
GRANT CONNECT ON DATABASE iot TO slava_login;
GRANT CONNECT ON DATABASE iot TO vlad_login;

-- =========================================================
-- Схемы
-- =========================================================

-- SCHEMA: app

CREATE SCHEMA IF NOT EXISTS app
    AUTHORIZATION postgres;

COMMENT ON SCHEMA app
    IS 'Бизнес-данные IoT системы';

GRANT USAGE ON SCHEMA app TO app_owner;
GRANT USAGE ON SCHEMA app TO app_reader;
GRANT USAGE ON SCHEMA app TO app_writer;
GRANT USAGE ON SCHEMA app TO ddl_admin;
GRANT USAGE ON SCHEMA app TO dml_admin;
GRANT ALL   ON SCHEMA app TO postgres;
GRANT USAGE ON SCHEMA app TO security_admin;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA app
GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO app_owner;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA app
GRANT SELECT ON TABLES TO app_reader;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA app
GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO app_writer;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA app
GRANT SELECT, USAGE ON SEQUENCES TO app_owner;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA app
GRANT SELECT, USAGE ON SEQUENCES TO app_writer;

-- SCHEMA: audit

CREATE SCHEMA IF NOT EXISTS audit
    AUTHORIZATION postgres;

COMMENT ON SCHEMA audit
    IS 'Аудит и логирование операций';

GRANT USAGE ON SCHEMA audit TO auditor;
GRANT ALL   ON SCHEMA audit TO postgres;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA audit
GRANT SELECT ON TABLES TO auditor;

-- SCHEMA: ref

CREATE SCHEMA IF NOT EXISTS ref
    AUTHORIZATION postgres;

COMMENT ON SCHEMA ref
    IS 'Справочники и справочная информация';

GRANT USAGE ON SCHEMA ref TO app_owner;
GRANT USAGE ON SCHEMA ref TO app_reader;
GRANT USAGE ON SCHEMA ref TO app_writer;
GRANT USAGE ON SCHEMA ref TO ddl_admin;
GRANT USAGE ON SCHEMA ref TO dml_admin;
GRANT ALL   ON SCHEMA ref TO postgres;
GRANT USAGE ON SCHEMA ref TO security_admin;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA ref
GRANT SELECT ON TABLES TO app_owner;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA ref
GRANT SELECT ON TABLES TO app_reader;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA ref
GRANT SELECT ON TABLES TO app_writer;

-- SCHEMA: stg

CREATE SCHEMA IF NOT EXISTS stg
    AUTHORIZATION postgres;

COMMENT ON SCHEMA stg
    IS 'Временные и обслуживающие объекты';

GRANT USAGE ON SCHEMA stg TO app_owner;
GRANT ALL   ON SCHEMA stg TO ddl_admin;
GRANT USAGE ON SCHEMA stg TO dml_admin;
GRANT ALL   ON SCHEMA stg TO postgres;
GRANT USAGE ON SCHEMA stg TO security_admin;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA stg
GRANT DELETE, INSERT, SELECT, TRUNCATE, UPDATE ON TABLES TO dml_admin;

-- =========================================================
-- СЕКВЕНСЫ ДЛЯ ID
-- =========================================================

CREATE SEQUENCE IF NOT EXISTS app.api_keys_id_seq;
CREATE SEQUENCE IF NOT EXISTS app.device_commands_id_seq;
CREATE SEQUENCE IF NOT EXISTS app.device_secrets_id_seq;
CREATE SEQUENCE IF NOT EXISTS app.device_user_acl_id_seq;
CREATE SEQUENCE IF NOT EXISTS app.devices_id_seq;
CREATE SEQUENCE IF NOT EXISTS app.sensor_readings_id_seq;
CREATE SEQUENCE IF NOT EXISTS app.sensors_id_seq;
CREATE SEQUENCE IF NOT EXISTS app.user_accounts_id_seq;
CREATE SEQUENCE IF NOT EXISTS audit.login_log_id_seq;
CREATE SEQUENCE IF NOT EXISTS ref.sensor_types_id_seq;
CREATE SEQUENCE IF NOT EXISTS ref.units_id_seq;
CREATE SEQUENCE IF NOT EXISTS stg.ingest_raw_id_seq;

-- =========================================================
-- ФУНКЦИЯ app.current_username() (нужна в политиках)
-- =========================================================

CREATE OR REPLACE FUNCTION app.current_username()
RETURNS text
LANGUAGE sql
COST 100
STABLE SECURITY DEFINER PARALLEL UNSAFE
SET search_path=app, public
AS $BODY$
  SELECT session_user
$BODY$;

ALTER FUNCTION app.current_username()
    OWNER TO postgres;

GRANT EXECUTE ON FUNCTION app.current_username() TO PUBLIC;
GRANT EXECUTE ON FUNCTION app.current_username() TO app_owner;
GRANT EXECUTE ON FUNCTION app.current_username() TO app_reader;
GRANT EXECUTE ON FUNCTION app.current_username() TO app_writer;
GRANT EXECUTE ON FUNCTION app.current_username() TO postgres;
GRANT EXECUTE ON FUNCTION app.current_username() TO security_admin;

COMMENT ON FUNCTION app.current_username()
    IS 'Возвращает текущее имя пользователя';

-- =========================================================
-- ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ ДЛЯ ТРИГГЕРА updated_at
-- =========================================================

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

ALTER FUNCTION public.update_updated_at_column()
    OWNER TO postgres;

-- =========================================================
-- ТАБЛИЦЫ
-- =========================================================

-- Table: app.user_accounts

CREATE TABLE IF NOT EXISTS app.user_accounts
(
    id bigint NOT NULL DEFAULT nextval('app.user_accounts_id_seq'::regclass),
    username character varying(50) NOT NULL,
    email character varying(100) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    last_name character varying(60) NOT NULL,
    first_name character varying(60) NOT NULL,
    middle_name character varying(60),
    CONSTRAINT user_accounts_pkey PRIMARY KEY (id),
    CONSTRAINT user_accounts_email_key UNIQUE (email),
    CONSTRAINT user_accounts_username_key UNIQUE (username)
);

ALTER TABLE IF EXISTS app.user_accounts
    OWNER TO security_admin;

REVOKE ALL ON TABLE app.user_accounts FROM app_owner;
REVOKE ALL ON TABLE app.user_accounts FROM app_reader;
REVOKE ALL ON TABLE app.user_accounts FROM app_writer;
REVOKE ALL ON TABLE app.user_accounts FROM dml_admin;

GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.user_accounts TO app_owner;
GRANT SELECT ON TABLE app.user_accounts TO app_reader;
GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.user_accounts TO app_writer;
GRANT TRUNCATE ON TABLE app.user_accounts TO dml_admin;
GRANT ALL ON TABLE app.user_accounts TO security_admin;

COMMENT ON TABLE app.user_accounts IS 'Учетные записи пользователей системы';
COMMENT ON COLUMN app.user_accounts.username IS 'Уникальное имя пользователя';
COMMENT ON COLUMN app.user_accounts.email IS 'Email адрес пользователя';
COMMENT ON COLUMN app.user_accounts.is_active IS 'Флаг активности учетной записи';

CREATE OR REPLACE TRIGGER update_user_accounts_updated_at
    BEFORE UPDATE
    ON app.user_accounts
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- Table: app.api_keys

CREATE TABLE IF NOT EXISTS app.api_keys
(
    id bigint NOT NULL DEFAULT nextval('app.api_keys_id_seq'::regclass),
    user_id bigint NOT NULL,
    key_hash bytea NOT NULL,
    key_name character varying(100),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    expires_at timestamp with time zone,
    is_revoked boolean NOT NULL DEFAULT false,
    last_used_at timestamp with time zone,
    CONSTRAINT api_keys_pkey PRIMARY KEY (id),
    CONSTRAINT api_keys_user_id_fkey FOREIGN KEY (user_id)
        REFERENCES app.user_accounts (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE CASCADE
);

ALTER TABLE IF EXISTS app.api_keys
    OWNER TO security_admin;

ALTER TABLE IF EXISTS app.api_keys
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS app.api_keys
    FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE app.api_keys FROM app_owner;
REVOKE ALL ON TABLE app.api_keys FROM app_reader;
REVOKE ALL ON TABLE app.api_keys FROM app_writer;
REVOKE ALL ON TABLE app.api_keys FROM dml_admin;

GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.api_keys TO app_owner;
GRANT SELECT ON TABLE app.api_keys TO app_reader;
GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.api_keys TO app_writer;
GRANT TRUNCATE ON TABLE app.api_keys TO dml_admin;
GRANT ALL ON TABLE app.api_keys TO security_admin;

COMMENT ON TABLE app.api_keys IS 'API ключи пользователей (хранится хэш)';
COMMENT ON COLUMN app.api_keys.user_id IS 'Владелец ключа';
COMMENT ON COLUMN app.api_keys.key_hash IS 'SHA-256 хэш ключа';
COMMENT ON COLUMN app.api_keys.key_name IS 'Имя ключа для идентификации';
COMMENT ON COLUMN app.api_keys.expires_at IS 'Дата истечения ключа';
COMMENT ON COLUMN app.api_keys.is_revoked IS 'Флаг отзыва ключа';

CREATE UNIQUE INDEX IF NOT EXISTS idx_api_keys_user_hash
    ON app.api_keys USING btree
    (user_id ASC NULLS LAST, key_hash ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True);

CREATE POLICY p_api_keys_owner
    ON app.api_keys
    AS PERMISSIVE
    FOR ALL
    TO public
    USING ((EXISTS ( SELECT 1
                     FROM app.user_accounts u
                     WHERE ((u.id = api_keys.user_id)
                            AND ((u.username)::text = app.current_username())))));

-- Table: app.devices

CREATE TABLE IF NOT EXISTS app.devices
(
    id bigint NOT NULL DEFAULT nextval('app.devices_id_seq'::regclass),
    owner_id bigint NOT NULL,
    hw_serial character varying(64) NOT NULL,
    model character varying(100) NOT NULL,
    location_desc character varying(255),
    registered_at timestamp with time zone NOT NULL DEFAULT now(),
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT devices_pkey PRIMARY KEY (id),
    CONSTRAINT devices_hw_serial_key UNIQUE (hw_serial),
    CONSTRAINT devices_owner_id_fkey FOREIGN KEY (owner_id)
        REFERENCES app.user_accounts (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE RESTRICT
);

ALTER TABLE IF EXISTS app.devices
    OWNER TO security_admin;

ALTER TABLE IF EXISTS app.devices
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS app.devices
    FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE app.devices FROM app_owner;
REVOKE ALL ON TABLE app.devices FROM app_reader;
REVOKE ALL ON TABLE app.devices FROM app_writer;
REVOKE ALL ON TABLE app.devices FROM dml_admin;

GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.devices TO app_owner;
GRANT SELECT ON TABLE app.devices TO app_reader;
GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.devices TO app_writer;
GRANT TRUNCATE ON TABLE app.devices TO dml_admin;
GRANT ALL ON TABLE app.devices TO security_admin;

COMMENT ON TABLE app.devices IS 'IoT устройства (шлюзы, контроллеры)';
COMMENT ON COLUMN app.devices.owner_id IS 'Владелец устройства';
COMMENT ON COLUMN app.devices.hw_serial IS 'Серийный номер оборудования';
COMMENT ON COLUMN app.devices.model IS 'Модель устройства';
COMMENT ON COLUMN app.devices.location_desc IS 'Описание местоположения устройства';
COMMENT ON COLUMN app.devices.registered_at IS 'Дата регистрации устройства';

-- Table: app.device_user_acl

CREATE TABLE IF NOT EXISTS app.device_user_acl
(
    id bigint NOT NULL DEFAULT nextval('app.device_user_acl_id_seq'::regclass),
    device_id bigint NOT NULL,
    user_id bigint NOT NULL,
    role_in_device character varying(20) NOT NULL,
    granted_by bigint,
    granted_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT device_user_acl_pkey PRIMARY KEY (id),
    CONSTRAINT device_user_acl_device_id_user_id_key UNIQUE (device_id, user_id),
    CONSTRAINT device_user_acl_device_id_fkey FOREIGN KEY (device_id)
        REFERENCES app.devices (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE CASCADE,
    CONSTRAINT device_user_acl_granted_by_fkey FOREIGN KEY (granted_by)
        REFERENCES app.user_accounts (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT device_user_acl_user_id_fkey FOREIGN KEY (user_id)
        REFERENCES app.user_accounts (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE CASCADE,
    CONSTRAINT device_user_acl_role_in_device_check CHECK (role_in_device::text = ANY (ARRAY['viewer'::text, 'operator'::text, 'owner'::text]))
);

ALTER TABLE IF EXISTS app.device_user_acl
    OWNER TO security_admin;

ALTER TABLE IF EXISTS app.device_user_acl
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS app.device_user_acl
    FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE app.device_user_acl FROM app_owner;
REVOKE ALL ON TABLE app.device_user_acl FROM app_reader;
REVOKE ALL ON TABLE app.device_user_acl FROM app_writer;
REVOKE ALL ON TABLE app.device_user_acl FROM dml_admin;

GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.device_user_acl TO app_owner;
GRANT SELECT ON TABLE app.device_user_acl TO app_reader;
GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.device_user_acl TO app_writer;
GRANT TRUNCATE ON TABLE app.device_user_acl TO dml_admin;
GRANT ALL ON TABLE app.device_user_acl TO security_admin;

COMMENT ON TABLE app.device_user_acl IS 'Матрица доступа пользователей к устройствам';
COMMENT ON COLUMN app.device_user_acl.device_id IS 'Устройство';
COMMENT ON COLUMN app.device_user_acl.user_id IS 'Пользователь';
COMMENT ON COLUMN app.device_user_acl.role_in_device IS 'Роль пользователя на устройстве';
COMMENT ON COLUMN app.device_user_acl.granted_by IS 'Кто предоставил доступ';

CREATE POLICY p_acl_self_or_owner
    ON app.device_user_acl
    AS PERMISSIVE
    FOR ALL
    TO public
    USING (((EXISTS ( SELECT 1
                      FROM app.user_accounts u
                      WHERE ((u.id = device_user_acl.user_id)
                          AND ((u.username)::text = app.current_username()))))
            OR (EXISTS ( SELECT 1
                         FROM (app.devices d
                                  JOIN app.user_accounts u ON ((u.id = d.owner_id)))
                         WHERE ((d.id = device_user_acl.device_id)
                             AND ((u.username)::text = app.current_username()))))));

-- Table: app.device_commands

CREATE TABLE IF NOT EXISTS app.device_commands
(
    id bigint NOT NULL DEFAULT nextval('app.device_commands_id_seq'::regclass),
    device_id bigint NOT NULL,
    issued_by bigint NOT NULL,
    issued_at timestamp with time zone NOT NULL DEFAULT now(),
    cmd character varying(100) NOT NULL,
    cmd_params_json jsonb,
    status character varying(16) NOT NULL DEFAULT 'queued'::text,
    executed_at timestamp with time zone,
    error_message character varying(255),
    CONSTRAINT device_commands_pkey PRIMARY KEY (id),
    CONSTRAINT device_commands_device_id_fkey FOREIGN KEY (device_id)
        REFERENCES app.devices (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE CASCADE,
    CONSTRAINT device_commands_issued_by_fkey FOREIGN KEY (issued_by)
        REFERENCES app.user_accounts (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT device_commands_status_check CHECK (status::text = ANY (ARRAY['queued'::text, 'sent'::text, 'acked'::text, 'error'::text]))
);

ALTER TABLE IF EXISTS app.device_commands
    OWNER TO security_admin;

ALTER TABLE IF EXISTS app.device_commands
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS app.device_commands
    FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE app.device_commands FROM app_owner;
REVOKE ALL ON TABLE app.device_commands FROM app_reader;
REVOKE ALL ON TABLE app.device_commands FROM app_writer;
REVOKE ALL ON TABLE app.device_commands FROM dml_admin;

GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.device_commands TO app_owner;
GRANT SELECT ON TABLE app.device_commands TO app_reader;
GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.device_commands TO app_writer;
GRANT TRUNCATE ON TABLE app.device_commands TO dml_admin;
GRANT ALL ON TABLE app.device_commands TO security_admin;

COMMENT ON TABLE app.device_commands IS 'Команды, отправленные на устройства';
COMMENT ON COLUMN app.device_commands.device_id IS 'Целевое устройство';
COMMENT ON COLUMN app.device_commands.issued_by IS 'Кто отправил команду';
COMMENT ON COLUMN app.device_commands.cmd IS 'Текст команды';
COMMENT ON COLUMN app.device_commands.cmd_params_json IS 'Параметры команды в JSON';
COMMENT ON COLUMN app.device_commands.status IS 'Статус выполнения команды';

CREATE INDEX IF NOT EXISTS idx_device_commands_device_issued
    ON app.device_commands USING btree
    (device_id ASC NULLS LAST, issued_at ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True);

CREATE POLICY p_cmd_insert
    ON app.device_commands
    AS PERMISSIVE
    FOR INSERT
    TO public
    WITH CHECK (((EXISTS ( SELECT 1
                           FROM (app.device_user_acl a
                                    JOIN app.user_accounts u ON ((u.id = a.user_id)))
                           WHERE ((a.device_id = device_commands.device_id)
                               AND ((u.username)::text = app.current_username())
                               AND ((a.role_in_device)::text = ANY ((ARRAY['operator'::character varying, 'owner'::character varying])::text[])))))
                 OR (EXISTS ( SELECT 1
                              FROM (app.devices d
                                       JOIN app.user_accounts u ON ((u.id = d.owner_id)))
                              WHERE ((d.id = device_commands.device_id)
                                  AND ((u.username)::text = app.current_username()))))));

CREATE POLICY p_cmd_select
    ON app.device_commands
    AS PERMISSIVE
    FOR ALL
    TO public
    USING ((EXISTS ( SELECT 1
                     FROM app.devices d
                     WHERE ((d.id = device_commands.device_id)
                         AND ((EXISTS ( SELECT 1
                                        FROM app.user_accounts u
                                        WHERE (((u.username)::text = app.current_username())
                                            AND (u.id = d.owner_id))))
                              OR (EXISTS ( SELECT 1
                                           FROM (app.device_user_acl a
                                                    JOIN app.user_accounts u ON ((u.id = a.user_id)))
                                           WHERE ((a.device_id = d.id)
                                               AND ((u.username)::text = app.current_username())))))))));

-- Table: app.device_secrets

CREATE TABLE IF NOT EXISTS app.device_secrets
(
    id bigint NOT NULL DEFAULT nextval('app.device_secrets_id_seq'::regclass),
    device_id bigint NOT NULL,
    secret_ciphertext bytea NOT NULL,
    secret_type character varying(50) NOT NULL DEFAULT 'auth_token'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    is_active boolean NOT NULL DEFAULT true,
    expires_at timestamp with time zone,
    CONSTRAINT device_secrets_pkey PRIMARY KEY (id),
    CONSTRAINT device_secrets_device_id_fkey FOREIGN KEY (device_id)
        REFERENCES app.devices (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE CASCADE
);

ALTER TABLE IF EXISTS app.device_secrets
    OWNER TO security_admin;

ALTER TABLE IF EXISTS app.device_secrets
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS app.device_secrets
    FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE app.device_secrets FROM app_owner;
REVOKE ALL ON TABLE app.device_secrets FROM app_reader;
REVOKE ALL ON TABLE app.device_secrets FROM app_writer;
REVOKE ALL ON TABLE app.device_secrets FROM dml_admin;

GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.device_secrets TO app_owner;
GRANT SELECT ON TABLE app.device_secrets TO app_reader;
GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.device_secrets TO app_writer;
GRANT TRUNCATE ON TABLE app.device_secrets TO dml_admin;
GRANT ALL ON TABLE app.device_secrets TO security_admin;

COMMENT ON TABLE app.device_secrets IS 'Зашифрованные секреты устройств';
COMMENT ON COLUMN app.device_secrets.device_id IS 'Устройство';
COMMENT ON COLUMN app.device_secrets.secret_ciphertext IS 'Зашифрованный секрет';
COMMENT ON COLUMN app.device_secrets.secret_type IS 'Тип секрета';

CREATE POLICY p_devsec_owner
    ON app.device_secrets
    AS PERMISSIVE
    FOR ALL
    TO public
    USING ((EXISTS ( SELECT 1
                     FROM (app.devices d
                              JOIN app.user_accounts u ON ((u.id = d.owner_id)))
                     WHERE ((d.id = device_secrets.device_id)
                         AND ((u.username)::text = app.current_username())))));

CREATE POLICY p_devices_is_owner_or_acl
    ON app.devices
    AS PERMISSIVE
    FOR ALL
    TO public
    USING (((EXISTS ( SELECT 1
                      FROM app.user_accounts u
                      WHERE (((u.username)::text = app.current_username())
                          AND (u.id = devices.owner_id))))
            OR (EXISTS ( SELECT 1
                         FROM (app.device_user_acl a
                                  JOIN app.user_accounts u ON ((u.id = a.user_id)))
                         WHERE ((a.device_id = devices.id)
                             AND ((u.username)::text = app.current_username()))))));

-- Table: audit.login_log

CREATE TABLE IF NOT EXISTS audit.login_log
(
    id bigint NOT NULL DEFAULT nextval('audit.login_log_id_seq'::regclass),
    login_time timestamp with time zone NOT NULL DEFAULT now(),
    username character varying(50) NOT NULL,
    client_ip inet,
    user_agent character varying(255),
    success boolean NOT NULL DEFAULT true,
    failure_reason character varying(255),
    CONSTRAINT login_log_pkey PRIMARY KEY (id)
);

ALTER TABLE IF EXISTS audit.login_log
    OWNER TO postgres;

REVOKE ALL ON TABLE audit.login_log FROM auditor;
GRANT SELECT ON TABLE audit.login_log TO auditor;
GRANT ALL ON TABLE audit.login_log TO postgres;

COMMENT ON TABLE audit.login_log IS 'Лог входов пользователей в систему';
COMMENT ON COLUMN audit.login_log.username IS 'Имя пользователя';
COMMENT ON COLUMN audit.login_log.client_ip IS 'IP адрес клиента';
COMMENT ON COLUMN audit.login_log.user_agent IS 'User-Agent браузера';
COMMENT ON COLUMN audit.login_log.success IS 'Успешность входа';
COMMENT ON COLUMN audit.login_log.failure_reason IS 'Причина неудачи входа';

-- Table: stg.ingest_raw

CREATE TABLE IF NOT EXISTS stg.ingest_raw
(
    id bigint NOT NULL DEFAULT nextval('stg.ingest_raw_id_seq'::regclass),
    payload_json jsonb NOT NULL,
    received_at timestamp with time zone NOT NULL DEFAULT now(),
    source character varying(100),
    processed boolean NOT NULL DEFAULT false,
    processed_at timestamp with time zone,
    CONSTRAINT ingest_raw_pkey PRIMARY KEY (id)
);

ALTER TABLE IF EXISTS stg.ingest_raw
    OWNER TO security_admin;

REVOKE ALL ON TABLE stg.ingest_raw FROM dml_admin;
GRANT TRUNCATE ON TABLE stg.ingest_raw TO dml_admin;
GRANT ALL ON TABLE stg.ingest_raw TO security_admin;

COMMENT ON TABLE stg.ingest_raw IS 'Буфер приема сырых данных от устройств';
COMMENT ON COLUMN stg.ingest_raw.payload_json IS 'JSON с данными от устройства';
COMMENT ON COLUMN stg.ingest_raw.source IS 'Источник данных';
COMMENT ON COLUMN stg.ingest_raw.processed IS 'Флаг обработки данных';

-- Table: ref.sensor_types

CREATE TABLE IF NOT EXISTS ref.sensor_types
(
    id bigint NOT NULL DEFAULT nextval('ref.sensor_types_id_seq'::regclass),
    code character varying(32) NOT NULL,
    name character varying(100) NOT NULL,
    description character varying(255),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT sensor_types_pkey PRIMARY KEY (id),
    CONSTRAINT sensor_types_code_key UNIQUE (code)
);

ALTER TABLE IF EXISTS ref.sensor_types
    OWNER TO security_admin;

REVOKE ALL ON TABLE ref.sensor_types FROM app_owner;
REVOKE ALL ON TABLE ref.sensor_types FROM app_reader;
REVOKE ALL ON TABLE ref.sensor_types FROM app_writer;
REVOKE ALL ON TABLE ref.sensor_types FROM dml_admin;

GRANT SELECT ON TABLE ref.sensor_types TO app_owner;
GRANT SELECT ON TABLE ref.sensor_types TO app_reader;
GRANT SELECT ON TABLE ref.sensor_types TO app_writer;
GRANT TRUNCATE ON TABLE ref.sensor_types TO dml_admin;
GRANT ALL ON TABLE ref.sensor_types TO security_admin;

COMMENT ON TABLE ref.sensor_types IS 'Справочник типов датчиков';
COMMENT ON COLUMN ref.sensor_types.code IS 'Код типа датчика (уникальный)';
COMMENT ON COLUMN ref.sensor_types.name IS 'Наименование типа датчика';
COMMENT ON COLUMN ref.sensor_types.description IS 'Описание типа датчика';

-- Table: ref.units

CREATE TABLE IF NOT EXISTS ref.units
(
    id bigint NOT NULL DEFAULT nextval('ref.units_id_seq'::regclass),
    code character varying(16) NOT NULL,
    name character varying(64) NOT NULL,
    symbol character varying(16),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT units_pkey PRIMARY KEY (id),
    CONSTRAINT units_code_key UNIQUE (code)
);

ALTER TABLE IF EXISTS ref.units
    OWNER TO security_admin;

REVOKE ALL ON TABLE ref.units FROM app_owner;
REVOKE ALL ON TABLE ref.units FROM app_reader;
REVOKE ALL ON TABLE ref.units FROM app_writer;
REVOKE ALL ON TABLE ref.units FROM dml_admin;

GRANT SELECT ON TABLE ref.units TO app_owner;
GRANT SELECT ON TABLE ref.units TO app_reader;
GRANT SELECT ON TABLE ref.units TO app_writer;
GRANT TRUNCATE ON TABLE ref.units TO dml_admin;
GRANT ALL ON TABLE ref.units TO security_admin;

COMMENT ON TABLE ref.units IS 'Справочник единиц измерения';
COMMENT ON COLUMN ref.units.code IS 'Код единицы измерения (уникальный)';
COMMENT ON COLUMN ref.units.name IS 'Наименование единицы измерения';
COMMENT ON COLUMN ref.units.symbol IS 'Символ единицы измерения';

-- Table: app.sensors

CREATE TABLE IF NOT EXISTS app.sensors
(
    id bigint NOT NULL DEFAULT nextval('app.sensors_id_seq'::regclass),
    device_id bigint NOT NULL,
    sensor_type_id bigint NOT NULL,
    unit_id bigint NOT NULL,
    name character varying(100) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT sensors_pkey PRIMARY KEY (id),
    CONSTRAINT sensors_device_id_name_key UNIQUE (device_id, name),
    CONSTRAINT sensors_device_id_fkey FOREIGN KEY (device_id)
        REFERENCES app.devices (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE CASCADE,
    CONSTRAINT sensors_sensor_type_id_fkey FOREIGN KEY (sensor_type_id)
        REFERENCES ref.sensor_types (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT sensors_unit_id_fkey FOREIGN KEY (unit_id)
        REFERENCES ref.units (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
);

ALTER TABLE IF EXISTS app.sensors
    OWNER TO security_admin;

ALTER TABLE IF EXISTS app.sensors
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS app.sensors
    FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE app.sensors FROM app_owner;
REVOKE ALL ON TABLE app.sensors FROM app_reader;
REVOKE ALL ON TABLE app.sensors FROM app_writer;
REVOKE ALL ON TABLE app.sensors FROM dml_admin;

GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.sensors TO app_owner;
GRANT SELECT ON TABLE app.sensors TO app_reader;
GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.sensors TO app_writer;
GRANT TRUNCATE ON TABLE app.sensors TO dml_admin;
GRANT ALL ON TABLE app.sensors TO security_admin;

COMMENT ON TABLE app.sensors IS 'Датчики, привязанные к устройствам';
COMMENT ON COLUMN app.sensors.device_id IS 'Устройство, к которому привязан датчик';
COMMENT ON COLUMN app.sensors.sensor_type_id IS 'Тип датчика';
COMMENT ON COLUMN app.sensors.unit_id IS 'Единица измерения';
COMMENT ON COLUMN app.sensors.name IS 'Имя датчика на устройстве';

CREATE POLICY p_sensors_via_device
    ON app.sensors
    AS PERMISSIVE
    FOR ALL
    TO public
    USING ((EXISTS ( SELECT 1
                     FROM app.devices d
                     WHERE ((d.id = sensors.device_id)
                         AND ((EXISTS ( SELECT 1
                                        FROM app.user_accounts u
                                        WHERE (((u.username)::text = app.current_username())
                                            AND (u.id = d.owner_id))))
                              OR (EXISTS ( SELECT 1
                                           FROM (app.device_user_acl a
                                                    JOIN app.user_accounts u ON ((u.id = a.user_id)))
                                           WHERE ((a.device_id = d.id)
                                               AND ((u.username)::text = app.current_username())))))))));

-- Table: app.sensor_readings

CREATE TABLE IF NOT EXISTS app.sensor_readings
(
    id bigint NOT NULL DEFAULT nextval('app.sensor_readings_id_seq'::regclass),
    sensor_id bigint NOT NULL,
    ts timestamp with time zone NOT NULL,
    value numeric(18,6) NOT NULL,
    quality smallint,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT sensor_readings_pkey PRIMARY KEY (id),
    CONSTRAINT sensor_readings_sensor_id_ts_key UNIQUE (sensor_id, ts),
    CONSTRAINT sensor_readings_sensor_id_fkey FOREIGN KEY (sensor_id)
        REFERENCES app.sensors (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE CASCADE,
    CONSTRAINT sensor_readings_quality_check CHECK (quality >= 0 AND quality <= 100)
);

ALTER TABLE IF EXISTS app.sensor_readings
    OWNER TO security_admin;

ALTER TABLE IF EXISTS app.sensor_readings
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS app.sensor_readings
    FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE app.sensor_readings FROM app_owner;
REVOKE ALL ON TABLE app.sensor_readings FROM app_reader;
REVOKE ALL ON TABLE app.sensor_readings FROM app_writer;
REVOKE ALL ON TABLE app.sensor_readings FROM dml_admin;

GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.sensor_readings TO app_owner;
GRANT SELECT ON TABLE app.sensor_readings TO app_reader;
GRANT INSERT, DELETE, SELECT, UPDATE ON TABLE app.sensor_readings TO app_writer;
GRANT TRUNCATE ON TABLE app.sensor_readings TO dml_admin;
GRANT ALL ON TABLE app.sensor_readings TO security_admin;

COMMENT ON TABLE app.sensor_readings IS 'Показания датчиков';
COMMENT ON COLUMN app.sensor_readings.sensor_id IS 'Датчик';
COMMENT ON COLUMN app.sensor_readings.ts IS 'Временная метка показания';
COMMENT ON COLUMN app.sensor_readings.value IS 'Значение показания';
COMMENT ON COLUMN app.sensor_readings.quality IS 'Качество показания (0-100%)';

CREATE INDEX IF NOT EXISTS idx_sensor_readings_sensor_ts
    ON app.sensor_readings USING btree
    (sensor_id ASC NULLS LAST, ts ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True);

CREATE POLICY p_readings_via_sensor
    ON app.sensor_readings
    AS PERMISSIVE
    FOR ALL
    TO public
    USING ((EXISTS ( SELECT 1
                     FROM app.sensors s
                     WHERE ((s.id = sensor_readings.sensor_id)
                         AND (EXISTS ( SELECT 1
                                      FROM app.devices d
                                      WHERE ((d.id = s.device_id)
                                          AND ((EXISTS ( SELECT 1
                                                         FROM app.user_accounts u
                                                         WHERE (((u.username)::text = app.current_username())
                                                             AND (u.id = d.owner_id))))
                                               OR (EXISTS ( SELECT 1
                                                            FROM (app.device_user_acl a
                                                                     JOIN app.user_accounts u ON ((u.id = a.user_id)))
                                                            WHERE ((a.device_id = d.id)
                                                                AND ((u.username)::text = app.current_username()))))))))))));

CREATE INDEX IF NOT EXISTS idx_ingest_raw_processed
    ON stg.ingest_raw USING btree
    (processed ASC NULLS LAST, received_at ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True);

-- =========================================================
-- ФУНКЦИИ БЕЗОПАСНОСТИ
-- =========================================================

-- FUNCTION: app.init_session()

CREATE OR REPLACE FUNCTION app.init_session()
RETURNS void
LANGUAGE plpgsql
COST 100
VOLATILE SECURITY DEFINER PARALLEL UNSAFE
SET search_path=app, public
AS $BODY$
DECLARE
    v_user text := current_user;
    v_ip   inet := inet_client_addr();
BEGIN
    INSERT INTO audit.login_log(username, client_ip, success)
    VALUES (v_user, v_ip, true);

    PERFORM set_config('app.session_inited','1', true);

    RAISE NOTICE 'Сессия инициализирована для пользователя: %', v_user;
END;
$BODY$;

ALTER FUNCTION app.init_session()
    OWNER TO postgres;

GRANT EXECUTE ON FUNCTION app.init_session() TO PUBLIC;
GRANT EXECUTE ON FUNCTION app.init_session() TO app_owner;
GRANT EXECUTE ON FUNCTION app.init_session() TO app_reader;
GRANT EXECUTE ON FUNCTION app.init_session() TO app_writer;
GRANT EXECUTE ON FUNCTION app.init_session() TO postgres;
GRANT EXECUTE ON FUNCTION app.init_session() TO security_admin;

COMMENT ON FUNCTION app.init_session()
    IS 'Инициализация прикладной сессии: лог входа + флаг app.session_inited';

-- FUNCTION: app.sec_issue_device_command(bigint, text, jsonb)

CREATE OR REPLACE FUNCTION app.sec_issue_device_command(
	p_device_id bigint,
	p_cmd text,
	p_params jsonb DEFAULT NULL::jsonb)
RETURNS bigint
LANGUAGE plpgsql
COST 100
VOLATILE SECURITY DEFINER PARALLEL UNSAFE
SET search_path=app, public
AS $BODY$
DECLARE
    v_user text := app.current_username();
    v_user_id bigint;
    v_cmd_id bigint;
BEGIN
    IF p_device_id IS NULL OR coalesce(trim(p_cmd),'') = '' THEN
        RAISE EXCEPTION 'device_id и cmd обязательны';
    END IF;

    SELECT id INTO v_user_id
    FROM app.user_accounts
    WHERE username = v_user;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Пользователь % не найден в app.user_accounts', v_user;
    END IF;

    IF NOT (
        EXISTS (SELECT 1 FROM app.devices d WHERE d.id = p_device_id AND d.owner_id = v_user_id)
        OR EXISTS (
            SELECT 1
            FROM app.device_user_acl a
            WHERE a.device_id = p_device_id
              AND a.user_id   = v_user_id
              AND a.role_in_device IN ('operator','owner')
        )
    ) THEN
        RAISE EXCEPTION 'Недостаточно прав для отправки команды на устройство %', p_device_id;
    END IF;

    INSERT INTO app.device_commands(device_id, issued_by, cmd, cmd_params_json, status)
    VALUES (p_device_id, v_user_id, p_cmd, p_params, 'queued')
    RETURNING id INTO v_cmd_id;

    RETURN v_cmd_id;
END;
$BODY$;

ALTER FUNCTION app.sec_issue_device_command(bigint, text, jsonb)
    OWNER TO postgres;

GRANT EXECUTE ON FUNCTION app.sec_issue_device_command(bigint, text, jsonb) TO PUBLIC;
GRANT EXECUTE ON FUNCTION app.sec_issue_device_command(bigint, text, jsonb) TO app_owner;
GRANT EXECUTE ON FUNCTION app.sec_issue_device_command(bigint, text, jsonb) TO app_reader;
GRANT EXECUTE ON FUNCTION app.sec_issue_device_command(bigint, text, jsonb) TO app_writer;
GRANT EXECUTE ON FUNCTION app.sec_issue_device_command(bigint, text, jsonb) TO postgres;

-- FUNCTION: app.sec_rotate_api_key(text, text, timestamp with time zone)

CREATE OR REPLACE FUNCTION app.sec_rotate_api_key(
	p_key_name text,
	p_plain_key text,
	p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
RETURNS bigint
LANGUAGE plpgsql
COST 100
VOLATILE SECURITY DEFINER PARALLEL UNSAFE
SET search_path=app, public
AS $BODY$
DECLARE
    v_user text := app.current_username();
    v_user_id bigint;
    v_new_id bigint;
BEGIN
    IF coalesce(trim(p_key_name),'') = '' THEN
        RAISE EXCEPTION 'Имя ключа обязательно';
    END IF;
    IF p_plain_key IS NULL OR length(p_plain_key) < 16 THEN
        RAISE EXCEPTION 'Секрет ключа слишком короткий (>=16 симв.)';
    END IF;

    SELECT id INTO v_user_id
    FROM app.user_accounts
    WHERE username = v_user;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Пользователь % не найден в app.user_accounts', v_user;
    END IF;

    UPDATE app.api_keys
       SET is_revoked = true
     WHERE user_id = v_user_id AND key_name = p_key_name AND is_revoked = false;

    INSERT INTO app.api_keys(user_id, key_name, key_hash, expires_at, is_revoked)
    VALUES (v_user_id, p_key_name, digest(p_plain_key,'sha256'), p_expires_at, false)
    RETURNING id INTO v_new_id;

    RETURN v_new_id;
END;
$BODY$;

ALTER FUNCTION app.sec_rotate_api_key(text, text, timestamp with time zone)
    OWNER TO postgres;

GRANT EXECUTE ON FUNCTION app.sec_rotate_api_key(text, text, timestamp with time zone) TO PUBLIC;
GRANT EXECUTE ON FUNCTION app.sec_rotate_api_key(text, text, timestamp with time zone) TO app_owner;
GRANT EXECUTE ON FUNCTION app.sec_rotate_api_key(text, text, timestamp with time zone) TO app_reader;
GRANT EXECUTE ON FUNCTION app.sec_rotate_api_key(text, text, timestamp with time zone) TO app_writer;
GRANT EXECUTE ON FUNCTION app.sec_rotate_api_key(text, text, timestamp with time zone) TO postgres;

