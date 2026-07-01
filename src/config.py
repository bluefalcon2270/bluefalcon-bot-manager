import os

CONFIG_FILE = "/etc/bluefalcon/config.conf"
BOT_TOKEN = os.environ.get("BOT_TOKEN", "")
ADMIN_ID = os.environ.get("ADMIN_ID", "")

if os.path.exists(CONFIG_FILE):
    try:
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                line = line.strip()
                if '=' in line and not line.startswith('#'):
                    k, v = line.split('=', 1)
                    v = v.strip('"\'')
                    if k == 'BOT_TOKEN': BOT_TOKEN = v
                    elif k == 'ADMIN_ID': ADMIN_ID = v
    except Exception as e:
        print(f"Error loading config: {e}")
