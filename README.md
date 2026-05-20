# IOT_BD

База данных `iot` (PostgreSQL 16) — учебный проект по безопасности БД и IoT-предметной области.

## Суперпользователь

Предустановленная роль `postgres` **переименована в `iot_dba`** (требование КР, п. 2.3).

| Параметр | Значение |
|----------|----------|
| Логин суперпользователя | `iot_dba` |
| Пароль (Docker, учебный) | `iot_dba` |
| Подключение | `psql "host=127.0.0.1 user=iot_dba password=iot_dba dbname=iot"` |

### Новый кластер

```bash
docker compose down -v   # пересоздать том с нуля
docker compose up -d db
```

В `docker-compose.yml` задано `POSTGRES_USER: iot_dba`.

### Миграция существующего кластера (если ещё есть `postgres`)

```bash
docker exec -i iot_postgres psql -U postgres -d iot < db/scripts/rename_superuser_to_iot_dba.sql
# обновить db/conf/pg_hba.conf (уже iot_dba), затем:
docker exec iot_postgres psql -U iot_dba -d iot -c "SELECT pg_reload_conf();"
```

> В контейнере по-прежнему используется **системный** пользователь ОС `postgres` (`chown postgres:postgres`) — это штатный пользователь процесса PostgreSQL, не роль БД.

## Документация

- Курсовая (черновик): `Курсовая_работа_черновик.md`
- PITR: `Lab4-README.md`, `Lab4.sql`, `./lab4-pitr-demo.sh`
