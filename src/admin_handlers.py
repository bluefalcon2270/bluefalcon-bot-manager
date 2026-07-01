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
        mk = types.InlineKeyboardMarkup()
        mk.row(types.InlineKeyboardButton("📊 Statistics", callback_data='admin_stats'))
        mk.row(
            types.InlineKeyboardButton("👥 Manage Users", callback_data='admin_users'),
            types.InlineKeyboardButton("📢 Broadcast", callback_data='admin_broadcast')
        )
        mk.row(types.InlineKeyboardButton("⚙️ Bot Settings", callback_data='admin_settings'))
        mk.row(
            types.InlineKeyboardButton("🛍️ Products", callback_data='admin_products'),
            types.InlineKeyboardButton("❓ FAQs", callback_data='admin_faqs')
        )
        mk.row(types.InlineKeyboardButton("◀️ Back to Bot", callback_data='menu_main'))
        bot.edit_message_text("⚙️ *Ultimate Admin Panel*", chat_id, call.message.message_id, reply_markup=mk, parse_mode='Markdown')

    elif data == 'admin_stats':
        mk = types.InlineKeyboardMarkup()
        mk.add(types.InlineKeyboardButton("◀️ Back", callback_data='menu_admin'))
        users_count = len(db['users'])
        total_bal = sum(u.get('balance', 0) for u in db['users'].values())
        prods = len(db['products'])
        faqs = len(db['faqs'])
        text = f"📊 *Bot Statistics*\n\n👥 Users: {users_count}\n💰 Total Balance in System: ${total_bal:.2f}\n🛍️ Products: {prods}\n❓ FAQs: {faqs}"
        bot.edit_message_text(text, chat_id, call.message.message_id, reply_markup=mk, parse_mode='Markdown')

    elif data == 'admin_users':
        set_user_state(uid, 'WAIT_ADMIN_USER_ID')
        bot.edit_message_text("👥 Enter the User ID to manage:", chat_id, call.message.message_id)

    elif data == 'admin_broadcast':
        set_user_state(uid, 'WAIT_ADMIN_BROADCAST')
        bot.edit_message_text("📢 Enter the broadcast message to send to ALL users:", chat_id, call.message.message_id)

    elif data == 'admin_settings':
        mk = types.InlineKeyboardMarkup()
        mk.row(
            types.InlineKeyboardButton("Welcome (EN)", callback_data='admin_cfg_welcome_en'),
            types.InlineKeyboardButton("Welcome (FA)", callback_data='admin_cfg_welcome_fa')
        )
        mk.row(
            types.InlineKeyboardButton("Card Number", callback_data='admin_cfg_card_num'),
            types.InlineKeyboardButton("Card Name", callback_data='admin_cfg_card_name')
        )
        mk.row(types.InlineKeyboardButton("Support ID", callback_data='admin_cfg_support_id'))
        mk.row(types.InlineKeyboardButton("◀️ Back", callback_data='menu_admin'))
        bot.edit_message_text("⚙️ *Bot Settings*", chat_id, call.message.message_id, reply_markup=mk, parse_mode='Markdown')

    elif data.startswith('admin_cfg_'):
        key = data.replace('admin_cfg_', '')
        set_user_state(uid, f'WAIT_ADMIN_CFG_{key.upper()}')
        bot.edit_message_text(f"📝 Send the new text for `{key}`:", chat_id, call.message.message_id, parse_mode='Markdown')

    # Products Management
    elif data == 'admin_products':
        mk = types.InlineKeyboardMarkup()
        mk.add(types.InlineKeyboardButton("➕ Add Product", callback_data='admin_add_prod'))
        for pid, p in db['products'].items():
            mk.add(types.InlineKeyboardButton(f"🛍️ {p['name']} (${p['price']})", callback_data=f'admin_prod_{pid}'))
        mk.add(types.InlineKeyboardButton("◀️ Back", callback_data='menu_admin'))
        bot.edit_message_text("🛍️ *Product Management*", chat_id, call.message.message_id, reply_markup=mk, parse_mode='Markdown')

    elif data == 'admin_add_prod':
        set_user_state(uid, 'WAIT_PROD_NAME', {'msg_id': call.message.message_id})
        bot.edit_message_text("📝 Enter product name:", chat_id, call.message.message_id)

    elif data.startswith('admin_prod_'):
        pid = data.split('_')[2]
        if pid not in db['products']: return bot.answer_callback_query(call.id, "Not found!")
        p = db['products'][pid]
        mk = types.InlineKeyboardMarkup()
        mk.row(
            types.InlineKeyboardButton("📝 Edit Name", callback_data=f'editname_prod_{pid}'),
            types.InlineKeyboardButton("💵 Edit Price", callback_data=f'editprice_prod_{pid}')
        )
        mk.row(types.InlineKeyboardButton("❌ Remove Product", callback_data=f'delprod_{pid}'))
        mk.row(types.InlineKeyboardButton("◀️ Back", callback_data='admin_products'))
        bot.edit_message_text(f"🛍️ *Product:* {p['name']}\n💵 *Price:* ${p['price']}", chat_id, call.message.message_id, reply_markup=mk, parse_mode='Markdown')

    elif data.startswith('editname_prod_'):
        pid = data.split('_')[2]
        set_user_state(uid, 'WAIT_PROD_EDIT_NAME', {'pid': pid})
        bot.edit_message_text("📝 Send new product name:", chat_id, call.message.message_id)

    elif data.startswith('editprice_prod_'):
        pid = data.split('_')[2]
        set_user_state(uid, 'WAIT_PROD_EDIT_PRICE', {'pid': pid})
        bot.edit_message_text("💵 Send new product price (numbers only):", chat_id, call.message.message_id)

    elif data.startswith('delprod_'):
        pid = data.split('_')[1]
        if pid in db['products']:
            del db['products'][pid]
            save_db()
            bot.answer_callback_query(call.id, "🗑 Deleted!", show_alert=True)
            call.data = 'admin_products'
            handle_admin_callback(call)

    # FAQs Management
    elif data == 'admin_faqs':
        mk = types.InlineKeyboardMarkup()
        mk.add(types.InlineKeyboardButton("➕ Add FAQ", callback_data='admin_add_faq'))
        for fid, f in db['faqs'].items():
            mk.add(types.InlineKeyboardButton(f"❓ {f['q'][:20]}...", callback_data=f'admin_faq_{fid}'))
        mk.add(types.InlineKeyboardButton("◀️ Back", callback_data='menu_admin'))
        bot.edit_message_text("❓ *FAQ Management*", chat_id, call.message.message_id, reply_markup=mk, parse_mode='Markdown')

    elif data == 'admin_add_faq':
        set_user_state(uid, 'WAIT_FAQ_Q')
        bot.edit_message_text("📝 Enter FAQ Question:", chat_id, call.message.message_id)

    elif data.startswith('admin_faq_'):
        fid = data.split('_')[2]
        if fid not in db['faqs']: return bot.answer_callback_query(call.id, "Not found!")
        f = db['faqs'][fid]
        mk = types.InlineKeyboardMarkup()
        mk.row(
            types.InlineKeyboardButton("📝 Edit Q", callback_data=f'editq_faq_{fid}'),
            types.InlineKeyboardButton("📝 Edit A", callback_data=f'edita_faq_{fid}')
        )
        mk.row(types.InlineKeyboardButton("❌ Remove FAQ", callback_data=f'delfaq_{fid}'))
        mk.row(types.InlineKeyboardButton("◀️ Back", callback_data='admin_faqs'))
        bot.edit_message_text(f"❓ *Q:* {f['q']}\n💡 *A:* {f['a']}", chat_id, call.message.message_id, reply_markup=mk, parse_mode='Markdown')

    elif data.startswith('editq_faq_'):
        fid = data.split('_')[2]
        set_user_state(uid, 'WAIT_FAQ_EDIT_Q', {'fid': fid})
        bot.edit_message_text("📝 Send new question:", chat_id, call.message.message_id)

    elif data.startswith('edita_faq_'):
        fid = data.split('_')[2]
        set_user_state(uid, 'WAIT_FAQ_EDIT_A', {'fid': fid})
        bot.edit_message_text("📝 Send new answer:", chat_id, call.message.message_id)

    elif data.startswith('delfaq_'):
        fid = data.split('_')[1]
        if fid in db['faqs']:
            del db['faqs'][fid]
            save_db()
            bot.answer_callback_query(call.id, "🗑 Deleted!", show_alert=True)
            call.data = 'admin_faqs'
            handle_admin_callback(call)

    # User Management Balance Callbacks
    elif data.startswith('adminuser_add_'):
        target = data.split('_')[2]
        set_user_state(uid, 'WAIT_ADMIN_USER_ADD_BAL', {'target': target})
        bot.edit_message_text(f"➕ Enter amount to ADD to {target}:", chat_id, call.message.message_id)

    elif data.startswith('adminuser_sub_'):
        target = data.split('_')[2]
        set_user_state(uid, 'WAIT_ADMIN_USER_SUB_BAL', {'target': target})
        bot.edit_message_text(f"➖ Enter amount to DEDUCT from {target}:", chat_id, call.message.message_id)

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
            bot.edit_message_text(f"✅ Approved ${amount} for {user_id}", chat_id, call.message.message_id)
            bot.send_message(user_id, t(target_lang, 'receipt_approved', amount=amount))
        else:
            bot.edit_message_text(f"❌ Rejected receipt from {user_id}", chat_id, call.message.message_id)
            bot.send_message(user_id, t(target_lang, 'receipt_rejected'))
