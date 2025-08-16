# Delivery Bot

Полуфабрикаты Delivery Bot — это комплексная система доставки готовой еды, сочетающая в себе веб-приложение на Django/DRF, Telegram‑бота на aiogram, асинхронные фоновые задачи на Celery и веб‑прокси на Caddy. Проект предназначен для быстрого развёртывания как в локальной среде разработчика, так и на production‑сервере.

## Ключевые возможности

- **Бот клиентов** — Telegram‑интерфейс для оформления заказов и получения уведомлений.
- **Модуль курьеров** — маршрутизация доставок с использованием API Яндекс.Карт.
- **Новости, розыгрыши и планировщик** — периодические рассылки и промо‑акции, управляемые через административную панель.
- **Заглушка оплаты** — имитация процессинга оплаты для тестовых стендов.

## Содержание

1. [Архитектура](#архитектура)
2. [Быстрый старт](#быстрый-старт)
3. [Конфигурация](#конфигурация)
4. [Деплой и операции](#деплой-и-операции)
5. [Мониторинг и логи](#мониторинг-и-логи)
6. [Безопасность](#безопасность)
7. [Тестирование](#тестирование)
8. [CI/CD](#cicd)
9. [Траблшутинг и FAQ](#траблшутинг-и-faq)
10. [Справочник команд](#справочник-команд)
11. [Структура каталогов](#структура-каталогов)
12. [Лицензия и вклад](#лицензия-и-вклад)

## Архитектура

Проект построен по микросервисной схеме и использует Docker Compose как на дев‑, так и на прод‑среде.

```
+---------+       +-------------+       +----------+
|  Caddy  +<----->+  Django ASGI +<----->+ Postgres |
+----+----+       +-------------+       +----------+
     ^                ^   ^                 ^
     |                |   |                 |
     |                |   |                 +--> backups
     |                |   +--> Redis <------+ 
     |                |
     |                +--> Celery/Beat
     |
     +--> Telegram Bot
```

### Таблица сервисов

| Сервис | Порт | Назначение | Важные переменные окружения |
|--------|------|------------|------------------------------|
| proxy (Caddy) | 80/443 | TLS‑прокси, статика | `APP_BASE_URL`, `WEBHOOK_SECRET` |
| web (Django) | 8000 | API и админка | `DJANGO_SECRET_KEY`, `DATABASE_URL` |
| bot | — | aiogram‑бот | `BOT_TOKEN`, `BOT_ADMIN_IDS` |
| celery | — | workers Celery | `REDIS_URL`, `DATABASE_URL` |
| beat | — | планировщик задач | `REDIS_URL`, `DATABASE_URL` |
| redis | 6379 | брокер задач | — |
| db (Postgres) | 5432 | база данных | `POSTGRES_PASSWORD` |

## Быстрый старт

### Установка на чистый Debian 12

```bash
bash <(curl -Ls https://raw.githubusercontent.com/OWNER/REPO/main/scripts/install_debian12.sh) \
  --repo https://github.com/OWNER/REPO.git \
  --branch main \
  --path /opt/foodbot \
  --domain bot.example.com \
  --app-base-url https://bot.example.com \
  --bot-token 123456:ABCDEF \
  --admin-ids "111111,222222" \
  --db-password "VeryStrongPass" \
  --non-interactive
```

Скрипт проверяет версию ОС, устанавливает Docker Engine и необходимые утилиты, разворачивает проект и регистрирует Telegram‑webhook.

### Локальная разработка

```bash
docker compose -f infra/docker-compose.prod.yml up -d --build
```

Для запуска без Docker можно использовать стандартные команды Django/uvicorn (не рекомендуется для прод).

## Конфигурация

Все переменные окружения описаны в файле `.env.prod`. Ниже приведена сводная таблица:

| Переменная | Обяз. | По умолчанию | Пример | Описание |
|------------|------|--------------|--------|----------|
| `DJANGO_SECRET_KEY` | да | — | `p9o...` | Секретный ключ Django |
| `DJANGO_DEBUG` | нет | `False` | `True` | Режим отладки |
| `ALLOWED_HOSTS` | да | — | `bot.example.com` | Разрешённые хосты |
| `DATABASE_URL` | да | — | `postgresql://foodbot:pass@db:5432/foodbot` | Подключение к БД |
| `REDIS_URL` | да | — | `redis://redis:6379/0` | Брокер задач |
| `BOT_TOKEN` | да | — | `123456:ABCDEF` | Токен Telegram‑бота |
| `BOT_ADMIN_IDS` | да | — | `123,456` | ID администраторов бота |
| `WEBHOOK_SECRET` | да | — | `tok3n` | Секрет Telegram‑webhook |
| `APP_BASE_URL` | да | — | `https://bot.example.com` | Публичный URL приложения |
| `WAREHOUSE_ADDRESS` | нет | — | `СПб, ул. Пример, 1` | Адрес склада |
| `WAREHOUSE_COORDS` | нет | — | `59.93,30.33` | Координаты склада |

Секреты можно генерировать безопасно через Python:

```bash
python - <<'PY'
import secrets; print(secrets.token_urlsafe(64))
PY
```

## Деплой и операции

Все эксплуатационные скрипты находятся в каталоге `scripts/`.

### Управление сервисом

```bash
./scripts/update_server.sh   # обновление кода и контейнеров
./scripts/rollback.sh --to <commit|tag>  # откат
./scripts/uninstall.sh       # остановка и удаление
```

Проверка и регистрация webhook:

```bash
./scripts/register_webhook.py
```

Резервное копирование БД:

```bash
./scripts/backup_db.sh
```

Пример cron‑задания для ежедневного бэкапа:

```
0 2 * * * /opt/foodbot/scripts/backup_db.sh >/dev/null 2>&1
```

### Systemd

Сервис запускается через юнит `/etc/systemd/system/foodbot.service`.

```
systemctl start foodbot
systemctl stop foodbot
systemctl restart foodbot
journalctl -u foodbot -f
```

## Мониторинг и логи

- Логи приложения: `docker compose -f infra/docker-compose.prod.yml logs -f web`
- Логи прокси: `docker compose -f infra/docker-compose.prod.yml logs -f proxy`
- Health‑check: `curl -I https://bot.example.com/healthz`

## Безопасность

- UFW блокирует всё кроме 22/80/443.
- Caddy автоматически выпускает TLS‑сертификаты и включает HSTS.
- Telegram‑webhook защищён заголовком `X-Telegram-Bot-Api-Secret-Token`.
- Секреты хранятся в `.env.prod`; регулярная ротация рекомендована через `install_debian12.sh --non-interactive`.

## Тестирование

```bash
pytest
ruff .
black --check .
```

Smoke‑тест после деплоя выполняется командой:

```bash
curl -sf https://bot.example.com/healthz
```

## CI/CD

В репозитории используется GitHub Actions workflow `.github/workflows/deploy.yml`, который по пушу в ветку `main` выполняет деплой на сервер через SSH. Необходимые secrets: `SSH_HOST`, `SSH_USER`, `SSH_KEY`, `SSH_KNOWN_HOSTS`.

## Траблшутинг и FAQ

- **DNS/SSL**: Убедитесь, что A‑запись указывает на сервер и порт 80 доступен для выдачи сертификата.
- **502/504**: проверьте логи веб‑контейнера и статус health‑check.
- **Миграции**: ошибка `relation does not exist` — выполните `docker compose exec web python manage.py migrate`.
- **Права**: убедитесь, что пользователь имеет доступ к `/opt/foodbot`.
- **Webhook**: код 401 — неверный `WEBHOOK_SECRET`; 404 — убедитесь, что URL `/api/webhook/telegram` существует.
- **SELinux/AppArmor**: на Debian по умолчанию выключены; при необходимости добавьте правила доступа к Docker.

## Справочник команд

| Команда | Описание |
|---------|----------|
| `docker compose -f infra/docker-compose.prod.yml logs -f web` | Просмотр логов веб‑сервиса |
| `docker compose -f infra/docker-compose.prod.yml restart bot` | Перезапуск бота |
| `curl -I https://bot.example.com/healthz` | Проверка health‑check |
| `docker compose -f infra/docker-compose.prod.yml ps` | Список контейнеров |
| `docker compose -f infra/docker-compose.prod.yml exec web python manage.py shell` | Django shell |
| `docker compose -f infra/docker-compose.prod.yml run --rm web python manage.py createsuperuser` | Создание суперпользователя |
| `docker compose -f infra/docker-compose.prod.yml down` | Остановка всех контейнеров |
| `journalctl -u foodbot -n 100` | Последние 100 строк systemd‑журнала |
| `ufw status` | Состояние файервола |
| `openssl s_client -connect bot.example.com:443 -servername bot.example.com` | Проверка TLS |
| `docker network ls` | Список сетей Docker |
| `docker volume ls` | Список volumes |
| `docker stats` | Мониторинг ресурсов |
| `crontab -l` | Список cron‑задач |
| `docker compose -f infra/docker-compose.prod.yml logs proxy` | Логи Caddy |
| `docker compose -f infra/docker-compose.prod.yml exec db psql -U foodbot` | Консоль БД |
| `bash scripts/backup_db.sh` | Ручной бэкап |

## Структура каталогов

```
.
├── .env.prod.example
├── docs
│   └── deploy
│       └── README.md
├── infra
│   ├── Caddyfile
│   └── docker-compose.prod.yml
├── scripts
│   ├── backup_db.sh
│   ├── install_debian12.sh
│   ├── register_webhook.py
│   ├── rollback.sh
│   ├── uninstall.sh
│   └── update_server.sh
└── .github
    └── workflows
        └── deploy.yml
```

## Лицензия и вклад

Проект распространяется под лицензией MIT. Приветствуются pull‑request'ы и баг‑репорты. Перед отправкой PR запускйте линтеры и тесты.
