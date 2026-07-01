import os
import sys
import uuid
import logging
from telebot import types
import config
from database import db, load_db, save_db, get_user, set_user_state
from locales import t
from bot_handlers import bot, send_welcome, send_inline_main_menu, handle_callback_user, get_lang, send_language_selection
from admin_handlers import handle_admin_callback

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

@bot.message_handler(commands=['start'])
def on_start(message):
    uid = message.from_user.id
    u = get_user(uid)
    
    # Handle referral
    if ' ' in message.text:
        inviter_id = message.text.split(' ')[1]
        if inviter_id.isdigit() and int(inviter_id) != uid and not u['invited_by']:
            u['invited_by'] = int(inviter_id)
            inviter = get_user(inviter_id)
            inviter['invites'] += 1
            save_db()
            
    # Simple language selection if new
    if u['lang'] not in ['en', 'fa']:
        set_user_state(uid, 'IDLE')
        send_language_selection(message.chat.id)
        return
        
    set_user_state(uid, 'IDLE')
    send_welcome(message.chat.id, uid)

@bot.message_handler(func=lambda m: True)
def on_message(message):
    uid = message.from_user.id
    chat_id = message.chat.id
    u = get_user(uid)
    state = u.get('state', 'IDLE')
    l = u['lang']
    text = message.text

    # Global keyboard catches
    if text in [t('en', 'btn_main_menu'), t('fa', 'btn_main_menu')]:
        set_user_state(uid, 'IDLE')
        send_inline_main_menu(chat_id, uid)
        return
        
    if text in [t('en', 'btn_restart'), t('fa', 'btn_restart')]:
        set_user_state(uid, 'IDLE')
        send_welcome(chat_id, uid)
        return

    # FSM Processing
    if state == 'WAIT_RECEIPT':
        set_user_state(uid, 'IDLE')
        bot.send_message(chat_id, t(l, 'receipt_submitted'))
        if config.ADMIN_ID:
            mk = types.InlineKeyboardMarkup()
            # Send a prompt to admin to approve/reject
            # Default amount to add is hardcoded here to 10.0 for simplicity, in a real app would ask for amount
            # Actually, let's just make the approve button callback contain the ID and wait for admin
            mk.add(
                types.InlineKeyboardButton("✅ Approve $10", callback_data=f"approve_{uid}_10"),
                types.InlineKeyboardButton("✅ Approve $50", callback_data=f"approve_{uid}_50"),
                types.InlineKeyboardButton("❌ Reject", callback_data=f"reject_{uid}")
            )
            bot.send_message(config.ADMIN_ID, f"🧾 *New Receipt* from {uid}:\n`{text}`", reply_markup=mk, parse_mode='Markdown')
            
    # Admin Product FSM
    elif state == 'WAIT_PROD_NAME':
        u['temp_data']['name'] = text
        set_user_state(uid, 'WAIT_PROD_PRICE', u['temp_data'])
        bot.send_message(chat_id, "💵 Enter price (numbers only):")
        
    elif state == 'WAIT_PROD_PRICE':
        if not text.isdigit(): return bot.send_message(chat_id, "Numbers only.")
        pid = str(uuid.uuid4())[:8]
        db['products'][pid] = {'name': u['temp_data']['name'], 'price': float(text)}
        save_db()
        set_user_state(uid, 'IDLE')
        bot.send_message(chat_id, "✅ Product saved!")

    elif state == 'WAIT_PROD_EDIT_NAME':
        pid = u['temp_data']['pid']
        if pid in db['products']:
            db['products'][pid]['name'] = text
            save_db()
        set_user_state(uid, 'IDLE')
        bot.send_message(chat_id, "✅ Name updated!")

    elif state == 'WAIT_PROD_EDIT_PRICE':
        if not text.isdigit(): return bot.send_message(chat_id, "Numbers only.")
        pid = u['temp_data']['pid']
        if pid in db['products']:
            db['products'][pid]['price'] = float(text)
            save_db()
        set_user_state(uid, 'IDLE')
        bot.send_message(chat_id, "✅ Price updated!")

    # Admin FAQ FSM
    elif state == 'WAIT_FAQ_Q':
        u['temp_data']['q'] = text
        set_user_state(uid, 'WAIT_FAQ_A', u['temp_data'])
        bot.send_message(chat_id, "📝 Enter answer:")
        
    elif state == 'WAIT_FAQ_A':
        fid = str(uuid.uuid4())[:8]
        db['faqs'][fid] = {'q': u['temp_data']['q'], 'a': text}
        save_db()
        set_user_state(uid, 'IDLE')
        bot.send_message(chat_id, "✅ FAQ saved!")
        
    elif state == 'WAIT_FAQ_EDIT_Q':
        fid = u['temp_data']['fid']
        if fid in db['faqs']:
            db['faqs'][fid]['q'] = text
            save_db()
        set_user_state(uid, 'IDLE')
        bot.send_message(chat_id, "✅ Question updated!")

    elif state == 'WAIT_FAQ_EDIT_A':
        fid = u['temp_data']['fid']
        if fid in db['faqs']:
            db['faqs'][fid]['a'] = text
            save_db()
        set_user_state(uid, 'IDLE')
        bot.send_message(chat_id, "✅ Answer updated!")

    # Admin Config FSM
    elif state.startswith('WAIT_ADMIN_CFG_'):
        key = state.replace('WAIT_ADMIN_CFG_', '').lower()
        if 'config' not in db: db['config'] = {}
        db['config'][key] = text
        save_db()
        set_user_state(uid, 'IDLE')
        bot.send_message(chat_id, "✅ Setting updated successfully!")

    # Admin Broadcast FSM
    elif state == 'WAIT_ADMIN_BROADCAST':
        set_user_state(uid, 'IDLE')
        bot.send_message(chat_id, "⏳ Sending broadcast...")
        sent = 0
        for user_id in db['users']:
            try:
                bot.send_message(user_id, text)
                sent += 1
            except:
                pass
        bot.send_message(chat_id, f"✅ Broadcast sent to {sent} users!")

    # Admin Manage User FSM
    elif state == 'WAIT_ADMIN_USER_ID':
        if text not in db['users']:
            set_user_state(uid, 'IDLE')
            return bot.send_message(chat_id, "❌ User not found in DB.")
        
        target = db['users'][text]
        set_user_state(uid, 'IDLE')
        mk = types.InlineKeyboardMarkup()
        mk.row(
            types.InlineKeyboardButton("➕ Add $", callback_data=f"adminuser_add_{text}"),
            types.InlineKeyboardButton("➖ Deduct $", callback_data=f"adminuser_sub_{text}")
        )
        mk.add(types.InlineKeyboardButton("◀️ Back", callback_data="menu_admin"))
        
        info = f"👤 *User:* `{text}`\n💰 *Balance:* {target.get('balance', 0)}\n🛍 *Purchases:* {target.get('purchases', 0)}\n🗣 *Language:* {target.get('lang', 'en')}"
        bot.send_message(chat_id, info, reply_markup=mk, parse_mode='Markdown')

    elif state == 'WAIT_ADMIN_USER_ADD_BAL':
        if not text.replace('.','',1).isdigit(): return bot.send_message(chat_id, "Numbers only.")
        target_uid = u['temp_data']['target']
        if target_uid in db['users']:
            db['users'][target_uid]['balance'] += float(text)
            save_db()
            bot.send_message(chat_id, f"✅ Added {text} to user {target_uid}.")
        set_user_state(uid, 'IDLE')

    elif state == 'WAIT_ADMIN_USER_SUB_BAL':
        if not text.replace('.','',1).isdigit(): return bot.send_message(chat_id, "Numbers only.")
        target_uid = u['temp_data']['target']
        if target_uid in db['users']:
            db['users'][target_uid]['balance'] -= float(text)
            save_db()
            bot.send_message(chat_id, f"✅ Deducted {text} from user {target_uid}.")
        set_user_state(uid, 'IDLE')

@bot.callback_query_handler(func=lambda call: True)
def on_callback(call):
    # Route admin callbacks if admin
    admin_prefixes = ['admin', 'del', 'approve_', 'reject_', 'edit', 'menu_admin']
    is_admin_call = any(call.data.startswith(p) for p in admin_prefixes)
    
    if str(call.from_user.id) == str(config.ADMIN_ID) and is_admin_call:
        handle_admin_callback(call)
    else:
        handle_callback_user(call)

if __name__ == '__main__':
    if not config.BOT_TOKEN:
        logger.error("BOT_TOKEN is missing!")
        sys.exit(1)
        
    load_db()
    
    version = "Unknown"
    try:
        with open(os.path.join(os.path.dirname(os.path.dirname(__file__)), 'VERSION'), 'r') as f:
            version = f.read().strip()
    except Exception:
        pass
        
    logger.info(f"BlueFalcon Bot V{version} Started! Admin: {config.ADMIN_ID}")
    bot.infinity_polling(timeout=30, long_polling_timeout=20, logger_level=None)
