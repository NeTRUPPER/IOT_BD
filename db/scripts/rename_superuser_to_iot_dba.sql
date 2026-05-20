-- Миграция для уже развёрнутого кластера с ролью postgres.
-- Запуск (пока ещё есть postgres):
--   docker exec -it iot_postgres psql -U postgres -d iot -f /path/rename_superuser_to_iot_dba.sql
-- После переименования обновите pg_hba.conf (iot_dba) и перезагрузите конфиг:
--   SELECT pg_reload_conf();

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres')
       AND NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iot_dba')
    THEN
        ALTER ROLE postgres RENAME TO iot_dba;
        RAISE NOTICE 'Роль postgres переименована в iot_dba';
    ELSIF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iot_dba') THEN
        RAISE NOTICE 'Роль iot_dba уже существует, переименование не требуется';
    ELSE
        RAISE EXCEPTION 'Не найдена роль postgres для переименования';
    END IF;
END
$$;

SELECT rolname, rolsuper, rolcanlogin
FROM pg_roles
WHERE rolname IN ('iot_dba', 'postgres')
ORDER BY rolname;
