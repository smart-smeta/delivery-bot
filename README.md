# delivery-bot

Automation-friendly Telegram bot service. Static and media files are served directly by Caddy; Django only handles dynamic requests.

## Environment variables
| Variable | Description |
| --- | --- |
| APP_DOMAIN | Public domain name for the app |
| ACME_EMAIL | Email used for Let's Encrypt certificates |
| POSTGRES_DB | Database name |
| POSTGRES_USER | Database user |
| POSTGRES_PASSWORD | Database user password |
| BOT_TOKEN | Telegram bot token |
| BOT_ADMIN_IDS | Comma separated admin IDs |
| WEBHOOK_SECRET | Secret token for Telegram webhook |

## Installation
Use the one-liner installer on a fresh Debian 12 server:

```bash
bash <(curl -Ls https://example.com/install_debian12.sh) \
  --domain bot.example.com \
  --app-base-url https://bot.example.com \
  --bot-token 123456:ABCDEF \
  --acme-email admin@bot.example.com
```

## Troubleshooting DNS/ACME
- The domain must resolve to the server before running the installer.
- Port 80 must be reachable for HTTP challenges.

## Useful commands
```bash
docker compose -f infra/docker-compose.prod.yml logs -f web
curl -I https://$APP_BASE_URL/healthz
ssh-keyscan -H $SERVER_HOST >> ~/.ssh/known_hosts
pg_dump -U $POSTGRES_USER $POSTGRES_DB > dump.sql
psql -U $POSTGRES_USER $POSTGRES_DB < dump.sql
```
