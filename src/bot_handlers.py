import telebot
from telebot import types
import config
from database import db, get_user, set_user_state, save_db
from locales import t

bot = telebot.TeleBot(config.BOT_TOKEN, parse_mode='Markdown')

def get_lang(uid):
    return get_user(uid)['lang']

def send_language_selection(chat_id):
    mk = types.InlineKeyboardMarkup()
    mk.row(
        types.InlineKeyboardButton("🇬🇧 English", callback_data='setlang_en'),
        types.InlineKeyboardButton("🇮🇷 فارسی", callback_data='setlang_fa')
    )
    bot.send_message(chat_id, "🌍 Please select your language / لطفا زبان خود را انتخاب کنید:", reply_markup=mk)

def send_welcome(chat_id, uid):
    u = get_user(uid)
    markup = types.ReplyKeyboardMarkup(resize_keyboard=True, row_width=2)
    markup.add(
        types.KeyboardButton(t(u['lang'], 'btn_main_menu')),
        types.KeyboardButton(t(u['lang'], 'btn_restart'))
    )
    bot.send_message(chat_id, t(u['lang'], 'system_ready'), reply_markup=markup)
    send_inline_main_menu(chat_id, uid)

def send_inline_main_menu(chat_id, uid):
    l = get_lang(uid)
    mk = types.InlineKeyboardMarkup()
    mk.row(
        types.InlineKeyboardButton(t(l, 'btn_products'), callback_data='menu_products'),
        types.InlineKeyboardButton(t(l, 'btn_account'), callback_data='menu_account')
    )

    mk.row(
        types.InlineKeyboardButton(t(l, 'btn_faq'), callback_data='menu_faq'),
        types.InlineKeyboardButton(t(l, 'btn_support'), callback_data='menu_support')
    )
    if str(uid) == str(config.ADMIN_ID):
        mk.add(types.InlineKeyboardButton(t(l, 'btn_admin'), callback_data='menu_admin'))
        
    bot.send_message(chat_id, t(l, 'welcome'), reply_markup=mk)

def handle_callback_user(call):
    uid = call.from_user.id
    chat_id = call.message.chat.id
    l = get_lang(uid)
    data = call.data
    
    if data.startswith('setlang_'):
        u = get_user(uid)
        u['lang'] = data.split('_')[1]
        save_db()
        bot.delete_message(chat_id, call.message.message_id)
        bot.answer_callback_query(call.id, t(u['lang'], 'lang_selected'))
        send_welcome(chat_id, uid)
        
    elif data == 'menu_main':
        bot.delete_message(chat_id, call.message.message_id)
        send_inline_main_menu(chat_id, uid)
        
    elif data == 'menu_products':
        mk = types.InlineKeyboardMarkup(row_width=1)
        for pid, p in db['products'].items():
            mk.add(types.InlineKeyboardButton(f"{p['name']} - {p['price']}", callback_data=f'viewprod_{pid}'))
        mk.add(types.InlineKeyboardButton(t(l, 'btn_back'), callback_data='menu_main'))
        bot.edit_message_text(t(l, 'products'), chat_id, call.message.message_id, reply_markup=mk)
        
    elif data.startswith('viewprod_'):
        pid = data.split('_')[1]
        p = db['products'].get(pid)
        if not p: return
        mk = types.InlineKeyboardMarkup()
        mk.add(types.InlineKeyboardButton(t(l, 'btn_buy'), callback_data=f'buyprod_{pid}'))
        mk.add(types.InlineKeyboardButton(t(l, 'btn_back'), callback_data='menu_products'))
        bot.edit_message_text(t(l, 'buy_product', name=p['name'], price=p['price']), chat_id, call.message.message_id, reply_markup=mk)
        
    elif data.startswith('buyprod_'):
        pid = data.split('_')[1]
        p = db['products'].get(pid)
        u = get_user(uid)
        if u['balance'] >= p['price']:
            u['balance'] -= p['price']
            u['purchases'] += 1
            if u['invited_by']:
                inviter = get_user(u['invited_by'])
                inviter['active_invites'] += 1
                # Optional: add bonus to inviter here
            save_db()
            bot.answer_callback_query(call.id, t(l, 'purchase_success'), show_alert=True)
            bot.delete_message(chat_id, call.message.message_id)
            send_inline_main_menu(chat_id, uid)
        else:
            bot.answer_callback_query(call.id, t(l, 'insufficient_funds'), show_alert=True)
            
    elif data == 'menu_account':
        u = get_user(uid)
        mk = types.InlineKeyboardMarkup()
        mk.row(
            types.InlineKeyboardButton(t(l, 'btn_add_funds'), callback_data='menu_add_funds'),
            types.InlineKeyboardButton(t(l, 'btn_invite'), callback_data='menu_invite')
        )
        mk.add(types.InlineKeyboardButton(t(l, 'btn_change_lang'), callback_data='menu_change_lang'))
        mk.add(types.InlineKeyboardButton(t(l, 'btn_back'), callback_data='menu_main'))
        text = t(l, 'my_account', balance=u['balance'], purchases=u['purchases'], invites=u['invites'], active_invites=u['active_invites'])
        bot.edit_message_text(text, chat_id, call.message.message_id, reply_markup=mk)
        
    elif data == 'menu_change_lang':
        bot.delete_message(chat_id, call.message.message_id)
        send_language_selection(chat_id)
        
    elif data == 'menu_add_funds':
        mk = types.InlineKeyboardMarkup()
        mk.add(types.InlineKeyboardButton(t(l, 'btn_card'), callback_data='fund_card'))
        mk.add(types.InlineKeyboardButton(t(l, 'btn_back'), callback_data='menu_account'))
        bot.edit_message_text(t(l, 'add_funds'), chat_id, call.message.message_id, reply_markup=mk)
        
    elif data == 'fund_card':
        mk = types.InlineKeyboardMarkup()
        mk.add(types.InlineKeyboardButton(t(l, 'btn_submit_receipt'), callback_data='submit_receipt'))
        mk.add(types.InlineKeyboardButton(t(l, 'btn_back'), callback_data='menu_add_funds'))
        # Using a dummy card for now
        bot.edit_message_text(t(l, 'card_transfer', card_num="1234-5678-9012-3456"), chat_id, call.message.message_id, reply_markup=mk)
        
    elif data == 'submit_receipt':
        set_user_state(uid, 'WAIT_RECEIPT', {'msg_id': call.message.message_id})
        bot.edit_message_text(t(l, 'enter_receipt'), chat_id, call.message.message_id)
        
    elif data == 'menu_invite':
        u = get_user(uid)
        bot_info = bot.get_me()
        link = f"https://t.me/{bot_info.username}?start={uid}"
        mk = types.InlineKeyboardMarkup()
        mk.add(types.InlineKeyboardButton(t(l, 'btn_back'), callback_data='menu_account'))
        text = t(l, 'invite_friend', link=link, total=u['invites'], active=u['active_invites'])
        bot.edit_message_text(text, chat_id, call.message.message_id, reply_markup=mk)
        
    elif data == 'menu_faq':
        mk = types.InlineKeyboardMarkup(row_width=1)
        for fid, f in db['faqs'].items():
            mk.add(types.InlineKeyboardButton(f['q'], callback_data=f'viewfaq_{fid}'))
        mk.add(types.InlineKeyboardButton(t(l, 'btn_back'), callback_data='menu_main'))
        bot.edit_message_text(t(l, 'faq_list'), chat_id, call.message.message_id, reply_markup=mk)
        
    elif data.startswith('viewfaq_'):
        fid = data.split('_')[1]
        f = db['faqs'].get(fid)
        if not f: return
        mk = types.InlineKeyboardMarkup()
        mk.add(types.InlineKeyboardButton(t(l, 'btn_back'), callback_data='menu_faq'))
        bot.edit_message_text(f"❓ *{f['q']}*\n\n💡 {f['a']}", chat_id, call.message.message_id, reply_markup=mk)
        
    elif data == 'menu_support':
        mk = types.InlineKeyboardMarkup()
        mk.add(types.InlineKeyboardButton(t(l, 'btn_back'), callback_data='menu_main'))
        bot.edit_message_text(t(l, 'contact_support'), chat_id, call.message.message_id, reply_markup=mk)
