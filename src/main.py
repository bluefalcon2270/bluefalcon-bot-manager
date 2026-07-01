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
            
    elif state == 'WAIT_PROD_NAME':
        u['temp_data']['name'] = text
        set_user_state(uid, 'WAIT_PROD_PRICE', u['temp_data'])
        bot.send_message(chat_id, t(l, 'enter_product_price'))
        
    elif state == 'WAIT_PROD_PRICE':
        if not text.isdigit():
            bot.send_message(chat_id, "Please enter numbers only.")
            return
        pid = str(uuid.uuid4())[:8]
        db['products'][pid] = {
            'name': u['temp_data']['name'],
            'price': float(text)
        }
        save_db()
        set_user_state(uid, 'IDLE')
        bot.send_message(chat_id, t(l, 'product_added'))
        
    elif state == 'WAIT_FAQ_Q':
        u['temp_data']['q'] = text
        set_user_state(uid, 'WAIT_FAQ_A', u['temp_data'])
        bot.send_message(chat_id, t(l, 'enter_faq_a'))
        
    elif state == 'WAIT_FAQ_A':
        fid = str(uuid.uuid4())[:8]
        db['faqs'][fid] = {
            'q': u['temp_data']['q'],
            'a': text
        }
        save_db()
        set_user_state(uid, 'IDLE')
        bot.send_message(chat_id, t(l, 'faq_added'))

@bot.callback_query_handler(func=lambda call: True)
def on_callback(call):
    # Route admin callbacks if admin
    if str(call.from_user.id) == str(config.ADMIN_ID) and (call.data.startswith('admin_') or call.data.startswith('del') or call.data.startswith('approve_') or call.data.startswith('reject_')):
        handle_admin_callback(call)
    else:
        handle_callback_user(call)

if __name__ == '__main__':
    if not config.BOT_TOKEN:
        logger.error("BOT_TOKEN is missing!")
        sys.exit(1)
        
    load_db()
    logger.info(f"BlueFalcon Bot V3.1 Started! Admin: {config.ADMIN_ID}")
    bot.infinity_polling(timeout=30, long_polling_timeout=20, logger_level=None)
