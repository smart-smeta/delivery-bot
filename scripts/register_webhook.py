#!/usr/bin/env python3
import os
import requests
from urllib.parse import urljoin

from pathlib import Path

from dotenv import dotenv_values

env_path = Path(__file__).resolve().parent.parent / '.env.prod'
config = dotenv_values(env_path)

BOT_TOKEN = config.get('BOT_TOKEN')
APP_BASE_URL = config.get('APP_BASE_URL')
WEBHOOK_SECRET = config.get('WEBHOOK_SECRET')

if not BOT_TOKEN or not APP_BASE_URL:
    raise SystemExit('BOT_TOKEN and APP_BASE_URL required')

url = f"https://api.telegram.org/bot{BOT_TOKEN}/setWebhook"
data = {
    'url': urljoin(APP_BASE_URL, '/api/webhook/telegram'),
    'secret_token': WEBHOOK_SECRET,
    'drop_pending_updates': True,
}

resp = requests.post(url, data=data, timeout=30)
print(resp.json())
