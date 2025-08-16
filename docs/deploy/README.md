# Deployment guide

Static and media files are served directly by Caddy. Django only handles dynamic traffic.

## One-liner installation
```bash
bash <(curl -Ls https://example.com/install_debian12.sh) \
  --domain bot.example.com \
  --app-base-url https://bot.example.com \
  --bot-token 123456:ABCDEF \
  --acme-email admin@bot.example.com
```

## Troubleshooting DNS/ACME
- Ensure the domain resolves to your server: `dig +short bot.example.com`.
- Port 80 must be open: `sudo ufw allow 80/tcp`.
- Caddy cannot obtain certificates until these are satisfied.

## Cheat sheet
```bash
docker compose -f infra/docker-compose.prod.yml logs -f web
curl -I https://$APP_BASE_URL/healthz
ssh-keyscan -H $SERVER_HOST >> ~/.ssh/known_hosts
pg_dump -U $POSTGRES_USER $POSTGRES_DB > dump.sql
psql -U $POSTGRES_USER $POSTGRES_DB < dump.sql
```
