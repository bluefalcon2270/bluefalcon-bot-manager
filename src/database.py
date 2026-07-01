import json
import os

DB_FILE = 'db.json'
db = {
    'users': {},
    'products': {},
    'faqs': {}
}

def load_db():
    global db
    if os.path.exists(DB_FILE):
        try:
            with open(DB_FILE, 'r', encoding='utf-8') as f:
                data = json.load(f)
                db['users'] = data.get('users', {})
                db['products'] = data.get('products', {})
                db['faqs'] = data.get('faqs', {})
        except Exception as e:
            print(f"Error loading DB: {e}")

def save_db():
    try:
        with open(DB_FILE, 'w', encoding='utf-8') as f:
            json.dump(db, f, indent=4, ensure_ascii=False)
    except Exception as e:
        print(f"Error saving DB: {e}")

def get_user(uid):
    uid_str = str(uid)
    if uid_str not in db['users']:
        db['users'][uid_str] = {
            'lang': 'en',
            'balance': 0.0,
            'purchases': 0,
            'invites': 0,
            'active_invites': 0,
            'invited_by': None,
            'state': 'IDLE',
            'temp_data': {}
        }
        save_db()
    return db['users'][uid_str]

def set_user_state(uid, state, temp_data=None):
    user = get_user(uid)
    user['state'] = state
    if temp_data is not None:
        user['temp_data'] = temp_data
    save_db()
