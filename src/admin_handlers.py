import uuid
from telebot import types
import config
from database import db, get_user, set_user_state, save_db
from locales import t
from bot_handlers import bot, send_inline_main_menu, get_lang

def handle_admin_callback(call):
    uid = call.from_user.id
    chat_id = call.message.chat.id
    l = get_lang(uid)
    data = call.data
    
    if data == 'menu_admin':
        mk = types.InlineKeyboardMarkup(row_width=2)
        mk.add(
            types.InlineKeyboardButton(t(l, 'btn_add_product'), callback_data='admin_add_prod'),
            types.InlineKeyboardButton(t(l, 'btn_manage_products'), callback_data='admin_manage_prod')
        )
        mk.add(
            types.InlineKeyboardButton(t(l, 'btn_add_faq'), callback_data='admin_add_faq'),
            types.InlineKeyboardButton(t(l, 'btn_manage_faqs'), callback_data='admin_manage_faq')
        )
        mk.add(types.InlineKeyboardButton(t(l, 'btn_back'), callback_data='menu_main'))
        bot.edit_message_text(t(l, 'admin_panel'), chat_id, call.message.message_id, reply_markup=mk)
        
    elif data == 'admin_add_prod':
        set_user_state(uid, 'WAIT_PROD_NAME', {'msg_id': call.message.message_id})
        bot.edit_message_text(t(l, 'enter_product_name'), chat_id, call.message.message_id)
        
    elif data == 'admin_manage_prod':
        mk = types.InlineKeyboardMarkup(row_width=1)
        for pid, p in db['products'].items():
            mk.add(types.InlineKeyboardButton(f"❌ {p['name']}", callback_data=f'delprod_{pid}'))
        mk.add(types.InlineKeyboardButton(t(l, 'btn_back'), callback_data='menu_admin'))
        bot.edit_message_text(t(l, 'admin_panel'), chat_id, call.message.message_id, reply_markup=mk)
        
    elif data.startswith('delprod_'):
        pid = data.split('_')[1]
        if pid in db['products']:
            del db['products'][pid]
            save_db()
            bot.answer_callback_query(call.id, t(l, 'deleted'), show_alert=True)
            # Re-render list
            call.data = 'admin_manage_prod'
            handle_admin_callback(call)
            
    elif data == 'admin_add_faq':
        set_user_state(uid, 'WAIT_FAQ_Q', {'msg_id': call.message.message_id})
        bot.edit_message_text(t(l, 'enter_faq_q'), chat_id, call.message.message_id)
        
    elif data == 'admin_manage_faq':
        mk = types.InlineKeyboardMarkup(row_width=1)
        for fid, f in db['faqs'].items():
            mk.add(types.InlineKeyboardButton(f"❌ {f['q'][:20]}...", callback_data=f'delfaq_{fid}'))
        mk.add(types.InlineKeyboardButton(t(l, 'btn_back'), callback_data='menu_admin'))
        bot.edit_message_text(t(l, 'admin_panel'), chat_id, call.message.message_id, reply_markup=mk)
        
    elif data.startswith('delfaq_'):
        fid = data.split('_')[1]
        if fid in db['faqs']:
            del db['faqs'][fid]
            save_db()
            bot.answer_callback_query(call.id, t(l, 'deleted'), show_alert=True)
            # Re-render list
            call.data = 'admin_manage_faq'
            handle_admin_callback(call)

    # Approving/Rejecting receipts
    elif data.startswith('approve_') or data.startswith('reject_'):
        parts = data.split('_')
        action = parts[0]
        user_id = parts[1]
        amount = parts[2] if len(parts) > 2 else 0
        
        target_lang = get_lang(user_id)
        
        if action == 'approve':
            u = get_user(user_id)
            u['balance'] += float(amount)
            save_db()
            bot.edit_message_text(f"✅ Approved {amount} for {user_id}", chat_id, call.message.message_id)
            bot.send_message(user_id, t(target_lang, 'receipt_approved', amount=amount))
        else:
            bot.edit_message_text(f"❌ Rejected receipt from {user_id}", chat_id, call.message.message_id)
            bot.send_message(user_id, t(target_lang, 'receipt_rejected'))
