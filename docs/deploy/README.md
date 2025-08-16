# Руководство по деплою

Этот документ описывает эксплуатацию Delivery Bot на сервере с Debian 12.

## Требования

- Debian 12 (bookworm)
- root или sudo‑доступ
- Доменное имя с A‑записью на сервер
- Открыты порты 22/80/443
- Значения: `BOT_TOKEN`, `BOT_ADMIN_IDS`, `APP_BASE_URL`, `WAREHOUSE_COORDS`

## Установка

```bash
bash <(curl -Ls https://raw.githubusercontent.com/OWNER/REPO/main/scripts/install_debian12.sh) [флаги]
```

### Основные флаги

| Флаг | Описание |
|------|----------|
| `--repo <url>` | URL репозитория, если код не склонирован |
| `--branch <name>` | Ветка (по умолчанию `main`) |
| `--path /opt/foodbot` | Директория установки |
| `--domain bot.example.com` | Домен приложения |
| `--bot-token <token>` | Telegram‑токен |
| `--admin-ids "1,2"` | ID админов |
| `--app-base-url https://bot.example.com` | Публичный URL |
| `--db-password <pass>` | Пароль БД |
| `--non-interactive` | Без вопросов |

## Что делает install_debian12.sh

1. Проверяет ОС и права.
2. Устанавливает curl, git, jq, ufw и Docker Engine.
3. Клонирует проект в `/opt/foodbot` (или обновляет существующий).
4. Формирует `.env.prod` и генерирует секреты.
5. Настраивает UFW, Docker‑network и volumes.
6. Собирает и поднимает контейнеры, ждёт готовность `/healthz`.
7. Выполняет миграции, `collectstatic`, создаёт суперпользователя.
8. Регистрирует Telegram‑webhook.
9. Создаёт systemd‑юнит `foodbot.service` и включает его.

## Диагностика

- Статус сервиса: `systemctl status foodbot`
- Логи: `journalctl -u foodbot -f`
- Health‑check: `curl -I https://<домен>/healthz`
- Логи контейнеров: `docker compose -f infra/docker-compose.prod.yml logs -f`

## Бэкапы

Скрипт `scripts/backup_db.sh` сохраняет дампы PostgreSQL в `backups/`. Пример cron:

```
0 2 * * * /opt/foodbot/scripts/backup_db.sh >/dev/null 2>&1
```

Восстановление:

```bash
gunzip < backups/foodbot-YYYYmmdd-HHMM.sql.gz | docker compose -f infra/docker-compose.prod.yml exec -T db psql -U foodbot foodbot
```

## Ротация секретов

Повторный запуск `install_debian12.sh` с флагом `--non-interactive` пересоздаёт `.env.prod` (не перезаписывая существующие значения) и обновляет Docker‑секреты. Рекомендуется менять `DB_PASSWORD`, `DJANGO_SECRET_KEY` и `WEBHOOK_SECRET` минимум раз в полгода.

## Zero‑downtime обновления

Скрипт `scripts/update_server.sh` выполняет:

1. `git fetch && git pull --rebase`
2. `docker compose pull`
3. `docker compose up -d --build`
4. миграции и `collectstatic`
5. smoke‑тест `/healthz`

Контейнеры пересоздаются по одному, что минимизирует простой.
