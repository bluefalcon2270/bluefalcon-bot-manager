#!/bin/bash
# ==============================================================================
# BlueFalcon Telegram Bot
# Version: v2.1
# Description: Professional-grade Linux deployment manager for Telegram Bots.
# ==============================================================================

set -eEu -o pipefail

# ==========================================
# CONSTANTS & COLORS
# ==========================================
readonly SCRIPT_VERSION="v2.1"
readonly CONFIG_DIR="/etc/bluefalcon"
readonly CONFIG_FILE="${CONFIG_DIR}/config.conf"
readonly LOG_FILE="/var/log/bluefalcon-bot.log"
readonly SCRIPT_LOG="/var/log/bluefalcon-script.log"
readonly BOT_DIR="/opt/bluefalcon-bot"

# ==========================================
# UTILITIES
# ==========================================
log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$SCRIPT_LOG"
}

run_task() {
    local msg="$1"
    shift
    echo "  [ * ] $msg"
    "$@" >> "$SCRIPT_LOG" 2>&1 &
    local pid=$!
    wait $pid || {
        echo "  [ ✖ ] FAILED: $msg (Code: $?)"
        log_msg "FAILED: $msg"
        exit 1
    }
    echo "  [ ✔ ] SUCCESS: $msg"
    log_msg "SUCCESS: $msg"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script must be run as root (sudo)."
        exit 1
    fi
}

check_os() {
    if [ ! -f /etc/os-release ]; then
        echo "Error: Cannot detect OS."; exit 1
    fi
    . /etc/os-release
    if [[ "$ID" == "debian" ]]; then
        local major="${VERSION_ID%%.*}"
        [ "$major" -ge 11 ] || { echo "Error: Debian 11+ required."; exit 1; }
    elif [[ "$ID" == "ubuntu" ]]; then
        local major="${VERSION_ID%%.*}"
        [ "$major" -ge 22 ] || { echo "Error: Ubuntu 22.04+ required."; exit 1; }
    else
        echo "Error: Only Debian/Ubuntu supported."; exit 1
    fi
}

check_internet() {
    ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 || {
        echo "Error: No internet connection."; exit 1
    }
}

check_apt_locks() {
    if lsof /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
        echo "Error: apt/dpkg is locked."; exit 1
    fi
}

setup_environment() {
    mkdir -p "$CONFIG_DIR" "$BOT_DIR"
    [ -f "$CONFIG_FILE" ] || touch "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    [ -f "$SCRIPT_LOG" ] || touch "$SCRIPT_LOG"
    chmod 600 "$SCRIPT_LOG"
    [ -f "$LOG_FILE" ] || touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    local script_path
    script_path=$(realpath "$0")
    [ -L /usr/local/bin/bluefalcon ] || ln -sf "$script_path" /usr/local/bin/bluefalcon
    chmod +x "$script_path"
}

pre_flight() {
    check_root
    check_os
    check_internet
    check_apt_locks
    setup_environment
}

# ==========================================
# STATUS
# ==========================================
get_bot_status() {
    if [ -f "$BOT_DIR/bot.pid" ]; then
        local pid
        pid=$(cat "$BOT_DIR/bot.pid" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "RUNNING     PID: $pid"; return
        fi
    fi
    echo "STOPPED"
}

# ==========================================
# DISPLAY MENU
# ==========================================
show_menu() {
    clear
    local status_line
    status_line=$(get_bot_status)

    echo "-----------------------------------------------"
    echo "-----------------------------------------------"
    echo "              BlueFalcon Telegram Bot        $SCRIPT_VERSION"
    echo "-----------------------------------------------"
    echo "-----------------------------------------------"
    echo "Bot Status: $status_line"
    echo "-----------------------------------------------"
    echo "1- Install / Update Bot"
    echo "2- Configure Bot (Token & Admin ID)"
    echo "3- Stop / Start"
    echo "4- Remove Bot Completely"
    echo "5- View Logs"
    echo "0- Exit"
    echo ""
    printf "Select option: "
}

auto_return() {
    echo ""
    echo "$1"
    echo "Returning to menu in 3 seconds..."
    sleep 3
}

# ==========================================
# BOT FILE WRITER
# ==========================================
do_write_bot_files() {
    cd "$BOT_DIR"

    cat << 'PYEOF' > requirements.txt
pyTelegramBotAPI==4.14.0
PYEOF

    cat << 'PYEOF' > main.py
import os, json, uuid, logging, copy, time
import telebot
from telebot import types

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler('/var/log/bluefalcon-bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

CONFIG_FILE = "/etc/bluefalcon/config.conf"
DB_FILE     = "db.json"

def load_config():
    cfg = {}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            for line in f:
                line = line.strip()
                if '=' in line and not line.startswith('#'):
                    k, v = line.split('=', 1)
                    cfg[k.strip()] = v.strip().strip('"\'')
    return cfg

cfg       = load_config()
BOT_TOKEN = cfg.get('BOT_TOKEN', '')
ADMIN_ID  = str(cfg.get('ADMIN_ID', ''))
bot       = telebot.TeleBot(BOT_TOKEN, parse_mode=None)

DEFAULT_DB = {
    'users': {},
    'products': {},
    'faqs': {},
    'settings': {
        'shop_name': 'My Shop',
        'shop_tagline': 'Your trusted online store',
        'shop_logo': None,
        'shop_channel': None,
        'affiliate_percent': 10,
        'admin_card': None,
        'admin_card_name': None,
        'direct_link': None,
    }
}
db = {}

def load_db():
    global db
    db = copy.deepcopy(DEFAULT_DB)
    if os.path.exists(DB_FILE):
        with open(DB_FILE, encoding='utf-8') as f:
            try:
                saved = json.load(f)
                for k in db:
                    if k in saved:
                        db[k].update(saved[k]) if isinstance(db[k], dict) else saved[k]
            except Exception as e:
                logger.error(f'DB load error: {e}')

def save_db():
    with open(DB_FILE, 'w', encoding='utf-8') as f:
        json.dump(db, f, ensure_ascii=False, indent=2)

load_db()

states = {}
def get_state(uid): return states.get(str(uid), {})
def set_state(uid, step, data=None): states[str(uid)] = {'step': step, 'data': data or {}}
def clear_state(uid): states.pop(str(uid), None)

LANG = {
'en': {
    'btn_main':        '🏠 Main Menu',
    'btn_support':     '📞 Support',
    'btn_restart':     '🔄 Restart Bot',
    
    'inline_products': '🛍️ Products',
    'inline_account':  '👤 My Account',
    'inline_faq':      '❓ FAQ',
    'inline_admin':    '⚙️ Admin Panel',
    
    'inline_balance':  '💳 My Balance',
    'inline_purchases':'📦 My Purchases',
    'inline_invite':   '🔗 Invite Friend',
    'inline_set_info': '📝 Set Personal Info',
    'inline_back_main':'◀️ Back to Main Menu',
    'inline_back_acc': '◀️ Back to Account',
    'inline_back_faq': '◀️ Back to FAQ',
    
    'btn_topup':       '💳 Top Up Balance',
    'btn_pay_card':    '🏦 Card to Card',
    'btn_pay_link':    '🔗 Pay Online',
    'btn_submit_rec':  '🧾 Submit Receipt ID',
    'btn_join':        '📢 Join Channel',
    'btn_verify':      '✅ I Joined — Verify',
    'btn_buy':         '🛒 Buy Now — ${price}',
    'btn_delete':      '🗑️ Delete: {name}',
    
    'ask_receipt':     '📝 Please type your Receipt ID (شماره پیگیری):',
    'receipt_sent':    '✅ Receipt sent to admin for approval. You will be notified shortly.',
    'receipt_approve': '✅ Approve',
    'receipt_reject':  '❌ Reject',
    'receipt_approved':'✅ Your top-up of *${amt}* has been approved and added to your balance!',
    'receipt_rejected':'❌ Your top-up receipt was rejected by the admin.',
    
    'admin_receipt':   '💰 *Top-up Request*\nUser: {name} (`{uid}`)\nAmount: *${amt}*\nReceipt ID: `{rec}`',

    'lang_set':        '✅ Language set to English 🇬🇧',
    'force_join':      '⚠️ *Join Required*\n\nYou must join our channel to use this bot.',
    'no_products':     '🛒 No products available yet.',
    'product_card':    '🛍️ *{name}*\n💰 Price: *${price}*\n💳 Your Balance: *${bal}*\n\n{desc}',
    'buy_success':     '✅ *Purchase Successful!*\n\n📦 {name}\n🔖 Order ID: `{oid}`\n\nThank you! The admin will be in touch shortly.',
    'buy_insufficient':'❌ *Insufficient Balance*\n\nYou need *${need}* more to complete this purchase.',
    
    'balance_title':   '💳 *Your Balance*\n\nAvailable: *${bal}*',
    'topup_title':     '💳 *Top Up Balance*\n\nChoose a payment method:',
    'topup_card':      '🏦 *Card to Card Payment*\n\n💰 Amount: *${price}*\n🔢 Card: `{card}`\n👤 Name: *{name}*\n\nSubmit your receipt ID below:',
    
    'account_title':   '👤 *My Account*\n\n• Name: *{name}*\n• ID: `{uid}`\n• Phone: {phone}\n• Balance: *${bal}*\n• Purchases: *{purchases}*',
    'phone_prompt':    '📱 Click the button below to share your phone number:',
    'btn_share_phone': '📱 Share Contact',
    'phone_saved':     '✅ Phone number saved!',
    'phone_not_set':   'Not shared',
    
    'invite_msg':      '🔗 *Invite & Earn!*\n\nEarn *{pct}%* commission on every purchase made via your link!\n\nYour link:\n`{link}`\n\n• Total Invited: *{total}*\n• Invited & Purchased: *{purchased}*',
    'copy_link':       '📋 Copy Invite Link',
    
    'commission_notif':'🎉 You earned *${amt}* commission from a referral purchase!',
    'no_purchases':    '📦 You have no purchases yet.',
    'purchases_title': '📦 *My Purchases*\n\n',
    'purchase_row':    '{i}. *{name}* — `{oid}`',
    
    'support_prompt':  '📞 *Support*\n\nSend your message and our team will reply as soon as possible.',
    'support_sent':    '✅ Your message has been sent! We\'ll reply here shortly.',
    'support_header':  '💬 *Support from {name}*\nUser ID: {uid}\n\n_Reply to this message to respond to the user._',
    'support_reply':   '📩 *Support Reply:*\n\n{msg}',
    
    'faq_title':       '❓ *Frequently Asked Questions*\n\nSelect a question below:',
    'faq_answer':      '❓ *{q}*\n\n💬 {a}',
    'no_faqs':         'No FAQs available.',
    
    'admin_title':     '⚙️ *Admin Panel*\n\nManage your shop:',
    'btn_set_name':    '🏪 Shop Name',
    'btn_set_tagline': '📝 Tagline',
    'btn_set_logo':    '🖼️ Shop Logo',
    'btn_set_channel': '📢 Force Join Channel',
    'btn_affiliate':   '💹 Affiliate %',
    'btn_add_prod':    '➕ Add Product',
    'btn_manage_prod': '📋 Manage Products',
    'btn_add_faq':     '➕ Add FAQ',
    'btn_manage_faq':  '📋 Manage FAQs',
    'btn_broadcast':   '📣 Broadcast',
    'btn_assign':      '📦 Assign Order',
    'btn_add_bal':     '💰 Add Balance',
    'btn_view_users':  '👥 View Users',
    'btn_set_card':    '🏦 Card Info',
    'btn_set_link':    '🔗 Payment Link',
    
    'ask_name':        '🏪 Send the new shop name:',
    'ask_tagline':     '📝 Send the new tagline (short description):',
    'ask_logo':        '🖼️ Send the shop logo as a photo:',
    'ask_channel':     '📢 Send the channel username (e.g. @MyChannel)\nSend *off* to disable force-join.',
    'ask_affiliate':   '💹 Send the affiliate commission % (e.g. 10 for 10%):',
    'ask_prod_name':   '🛍️ Send the product name:',
    'ask_prod_price':  '💰 Send the product price (e.g. 9.99):',
    'ask_prod_desc':   '📝 Send the product description:',
    'ask_prod_photo':  '🖼️ Send the product photo.\n\nType *skip* if no photo.',
    'ask_broadcast':   '📣 Send the message to broadcast to all users (text or photo):',
    'ask_assign_uid':  '🆔 Send the User ID to assign the order to:',
    'ask_assign_prod': '📦 Send the product/item name:',
    'ask_assign_oid':  '🔖 Send an Order ID, or type *auto* to generate one:',
    'ask_bal_uid':     '🆔 Send the User ID to add balance to:',
    'ask_bal_amt':     '💰 Send the amount to add (e.g. 10.00):',
    'ask_card_num':    '🏦 Send the bank card number:',
    'ask_card_name':   '👤 Send the account holder name:',
    'ask_link':        '🔗 Send the online payment URL:',
    
    'ask_faq_q':       '❓ Send the Question text:',
    'ask_faq_a':       '💬 Send the Answer text:',
    
    'broadcast_done':  '📣 Broadcast delivered to *{count}* users.',
    'user_not_found':  '❌ User ID not found in database.',
    'order_assigned':  '✅ Order successfully assigned to user.',
    'order_notif':     '📦 *Your order has been processed!*\n\n🛍️ {item}\n🔖 Order ID: `{oid}`',
    'balance_added':   '✅ Added *${amt}* to user\'s balance.',
    'balance_notif':   '💳 Your balance has been topped up by *${amt}*!',
    'card_saved':      '✅ Card information saved.',
    'link_saved':      '✅ Payment link saved.',
    'success':         '✅ Done!',
    'error':           '❌ Something went wrong. Please try again.',
    'users_title':     '👥 *Users ({count} total)*\n\n',
    'user_row':        '• *{name}* | `{uid}` | 💳 ${bal}',
    'manage_prod_title':'📋 *Products* — Tap to delete:',
    'manage_faq_title': '📋 *FAQs* — Tap to delete:',
    'prod_added':      '✅ Product *{name}* added successfully!',
    'prod_deleted':    '✅ Product deleted.',
    'faq_added':       '✅ FAQ added successfully!',
    'faq_deleted':     '✅ FAQ deleted.',
    'no_users':        'No users registered yet.',
},
'fa': {
    'btn_main':        '🏠 منوی اصلی',
    'btn_support':     '📞 پشتیبانی',
    'btn_restart':     '🔄 شروع مجدد ربات',
    
    'inline_products': '🛍️ محصولات',
    'inline_account':  '👤 حساب کاربری',
    'inline_faq':      '❓ سوالات متداول',
    'inline_admin':    '⚙️ پنل ادمین',
    
    'inline_balance':  '💳 موجودی من',
    'inline_purchases':'📦 خریدهای من',
    'inline_invite':   '🔗 دعوت از دوستان',
    'inline_set_info': '📝 ثبت اطلاعات شخصی',
    'inline_back_main':'◀️ بازگشت به منو',
    'inline_back_acc': '◀️ بازگشت به حساب',
    'inline_back_faq': '◀️ بازگشت به سوالات',
    
    'btn_topup':       '💳 شارژ موجودی',
    'btn_pay_card':    '🏦 کارت به کارت',
    'btn_pay_link':    '🔗 پرداخت آنلاین',
    'btn_submit_rec':  '🧾 ثبت شماره پیگیری',
    'btn_join':        '📢 عضویت در کانال',
    'btn_verify':      '✅ عضو شدم — تایید',
    'btn_buy':         '🛒 خرید — ${price}',
    'btn_delete':      '🗑️ حذف: {name}',
    
    'ask_receipt':     '📝 لطفا شماره پیگیری خود را تایپ و ارسال کنید:',
    'receipt_sent':    '✅ رسید شما برای مدیریت ارسال شد. به زودی نتیجه به شما اعلام می‌شود.',
    'receipt_approve': '✅ تایید و شارژ',
    'receipt_reject':  '❌ رد رسید',
    'receipt_approved':'✅ شارژ مبلغ *${amt}* توسط مدیریت تایید و به موجودی شما اضافه شد!',
    'receipt_rejected':'❌ رسید پرداختی شما توسط مدیریت تایید نشد.',
    
    'admin_receipt':   '💰 *درخواست شارژ حساب*\nکاربر: {name} (`{uid}`)\nمبلغ: *${amt}*\nشماره پیگیری: `{rec}`',

    'lang_set':        '✅ زبان به فارسی تنظیم شد 🇮🇷',
    'force_join':      '⚠️ *عضویت الزامی*\n\nبرای استفاده از ربات باید عضو کانال ما شوید.',
    'no_products':     '🛒 هنوز محصولی موجود نیست.',
    'product_card':    '🛍️ *{name}*\n💰 قیمت: *${price}*\n💳 موجودی شما: *${bal}*\n\n{desc}',
    'buy_success':     '✅ *خرید موفق!*\n\n📦 {name}\n🔖 شماره سفارش: `{oid}`\n\nممنون از خریدتان! ادمین به زودی با شما تماس می‌گیرد.',
    'buy_insufficient':'❌ *موجودی ناکافی*\n\nبرای این خرید به *${need}* بیشتر نیاز دارید.',
    
    'balance_title':   '💳 *موجودی شما*\n\nموجودی فعلی: *${bal}*',
    'topup_title':     '💳 *شارژ موجودی*\n\nروش پرداخت را انتخاب کنید:',
    'topup_card':      '🏦 *پرداخت کارت به کارت*\n\n💰 مبلغ: *${price}*\n🔢 شماره کارت: `{card}`\n👤 نام: *{name}*\n\nپس از پرداخت شماره پیگیری را از دکمه زیر ارسال کنید:',
    
    'account_title':   '👤 *حساب کاربری*\n\n• نام: *{name}*\n• آیدی: `{uid}`\n• شماره تماس: {phone}\n• موجودی: *${bal}*\n• تعداد خریدها: *{purchases}*',
    'phone_prompt':    '📱 برای اشتراک شماره تماس روی دکمه زیر کلیک کنید:',
    'btn_share_phone': '📱 ارسال شماره تماس',
    'phone_saved':     '✅ شماره تماس ذخیره شد!',
    'phone_not_set':   'ثبت نشده',
    
    'invite_msg':      '🔗 *دعوت و کسب درآمد!*\n\nبرای هر خریدی که توسط دوستان شما انجام شود، *{pct}%* پورسانت می‌گیرید!\n\nلینک اختصاصی شما:\n`{link}`\n\n• کل دعوت شده‌ها: *{total}*\n• دعوت شده‌های دارای خرید: *{purchased}*',
    'copy_link':       '📋 کپی لینک دعوت',
    
    'commission_notif':'🎉 شما مبلغ *${amt}* پورسانت از خرید یکی از کاربرانی که دعوت کرده بودید، دریافت کردید!',
    'no_purchases':    '📦 شما هنوز خریدی انجام نداده‌اید.',
    'purchases_title': '📦 *خریدهای من*\n\n',
    'purchase_row':    '{i}. *{name}* — `{oid}`',
    
    'support_prompt':  '📞 *پشتیبانی*\n\nپیام خود را ارسال کنید. در اسرع وقت پاسخ می‌دهیم.',
    'support_sent':    '✅ پیام ارسال شد! به زودی پاسخ می‌دهیم.',
    'support_header':  '💬 *پیام پشتیبانی از {name}*\nUser ID: {uid}\n\n_برای پاسخ، روی این پیام ریپلای بزنید._',
    'support_reply':   '📩 *پاسخ پشتیبانی:*\n\n{msg}',
    
    'faq_title':       '❓ *سوالات متداول*\n\nیک سوال را انتخاب کنید:',
    'faq_answer':      '❓ *{q}*\n\n💬 {a}',
    'no_faqs':         'هنوز سوالی ثبت نشده است.',
    
    'admin_title':     '⚙️ *پنل ادمین*\n\nمدیریت فروشگاه:',
    'btn_set_name':    '🏪 نام فروشگاه',
    'btn_set_tagline': '📝 توضیحات',
    'btn_set_logo':    '🖼️ لوگو',
    'btn_set_channel': '📢 کانال اجباری',
    'btn_affiliate':   '💹 درصد پورسانت',
    'btn_add_prod':    '➕ افزودن محصول',
    'btn_manage_prod': '📋 مدیریت محصولات',
    'btn_add_faq':     '➕ افزودن سوال متداول',
    'btn_manage_faq':  '📋 مدیریت سوالات',
    'btn_broadcast':   '📣 پیام همگانی',
    'btn_assign':      '📦 ثبت سفارش',
    'btn_add_bal':     '💰 شارژ موجودی',
    'btn_view_users':  '👥 کاربران',
    'btn_set_card':    '🏦 اطلاعات کارت',
    'btn_set_link':    '🔗 لینک پرداخت',
    
    'ask_name':        '🏪 نام جدید فروشگاه را ارسال کنید:',
    'ask_tagline':     '📝 توضیح کوتاه فروشگاه را ارسال کنید:',
    'ask_logo':        '🖼️ لوگو فروشگاه را به صورت عکس ارسال کنید:',
    'ask_channel':     '📢 نام کانال را ارسال کنید (مثال: @MyChannel)\nیا *off* برای غیرفعال کردن.',
    'ask_affiliate':   '💹 درصد پورسانت را ارسال کنید (مثلا: 10):',
    'ask_prod_name':   '🛍️ نام محصول را ارسال کنید:',
    'ask_prod_price':  '💰 قیمت محصول را ارسال کنید (عدد):',
    'ask_prod_desc':   '📝 توضیحات محصول را ارسال کنید:',
    'ask_prod_photo':  '🖼️ عکس محصول را ارسال کنید.\n\nبرای رد کردن *skip* بنویسید.',
    'ask_broadcast':   '📣 پیام همگانی را ارسال کنید (متن یا عکس):',
    'ask_assign_uid':  '🆔 آیدی کاربر را ارسال کنید:',
    'ask_assign_prod': '📦 نام محصول یا آیتم را ارسال کنید:',
    'ask_assign_oid':  '🔖 شماره سفارش را ارسال کنید یا *auto* بنویسید:',
    'ask_bal_uid':     '🆔 آیدی کاربر را ارسال کنید:',
    'ask_bal_amt':     '💰 مبلغ شارژ را ارسال کنید:',
    'ask_card_num':    '🏦 شماره کارت بانکی را ارسال کنید:',
    'ask_card_name':   '👤 نام صاحب حساب را ارسال کنید:',
    'ask_link':        '🔗 لینک پرداخت آنلاین را ارسال کنید:',
    
    'ask_faq_q':       '❓ متن سوال را ارسال کنید:',
    'ask_faq_a':       '💬 متن پاسخ را ارسال کنید:',
    
    'broadcast_done':  '📣 پیام به *{count}* کاربر ارسال شد.',
    'user_not_found':  '❌ کاربر یافت نشد.',
    'order_assigned':  '✅ سفارش به کاربر اختصاص یافت.',
    'order_notif':     '📦 *سفارش شما ثبت شد!*\n\n🛍️ {item}\n🔖 شماره سفارش: `{oid}`',
    'balance_added':   '✅ مبلغ *${amt}* به موجودی کاربر اضافه شد.',
    'balance_notif':   '💳 موجودی شما به مقدار *${amt}* شارژ شد!',
    'card_saved':      '✅ اطلاعات کارت ذخیره شد.',
    'link_saved':      '✅ لینک پرداخت ذخیره شد.',
    'success':         '✅ انجام شد!',
    'error':           '❌ خطایی رخ داد. لطفا دوباره امتحان کنید.',
    'users_title':     '👥 *کاربران ({count} نفر)*\n\n',
    'user_row':        '• *{name}* | `{uid}` | 💳 ${bal}',
    'manage_prod_title':'📋 *محصولات* — روی هر محصول بزنید تا حذف شود:',
    'manage_faq_title': '📋 *سوالات* — روی هر کدام بزنید تا حذف شود:',
    'prod_added':      '✅ محصول *{name}* با موفقیت اضافه شد!',
    'prod_deleted':    '✅ محصول حذف شد.',
    'faq_added':       '✅ سوال متداول با موفقیت اضافه شد.',
    'faq_deleted':     '✅ سوال متداول حذف شد.',
    'no_users':        'هنوز کاربری ثبت نشده.',
}
}

def t(uid, key, **kw):
    lang = db['users'].get(str(uid), {}).get('lang', 'en')
    lang = lang if lang in LANG else 'en'
    text = LANG[lang].get(key, LANG['en'].get(key, f'[{key}]'))
    try: return text.format(**kw) if kw else text
    except: return text

def get_lang(uid):
    lang = db['users'].get(str(uid), {}).get('lang', 'en')
    return lang if lang in LANG else 'en'

def ensure_user(from_user, referrer=None):
    uid = str(from_user.id)
    if uid not in db['users']:
        db['users'][uid] = {
            'lang': 'en',
            'name': from_user.first_name or 'User',
            'username': from_user.username or '',
            'phone': None,
            'balance': 0.0,
            'purchases': [],
            'referred_by': referrer,
        }
        save_db()
    return uid

def check_join(uid, chat_id):
    channel = db['settings'].get('shop_channel')
    if not channel or str(uid) == str(ADMIN_ID): return True
    try:
        m = bot.get_chat_member(channel, int(uid))
        if m.status in ('member', 'administrator', 'creator'): return True
    except Exception: pass
    l = get_lang(uid)
    url = f"https://t.me/{channel.lstrip('@')}"
    mk = types.InlineKeyboardMarkup()
    mk.add(types.InlineKeyboardButton(LANG[l]['btn_join'], url=url))
    mk.add(types.InlineKeyboardButton(LANG[l]['btn_verify'], callback_data='verify_join'))
    bot.send_message(chat_id, LANG[l]['force_join'], reply_markup=mk, parse_mode='Markdown')
    return False

def award_commission(buyer_uid, amount):
    referrer = db['users'].get(str(buyer_uid), {}).get('referred_by')
    if not referrer or str(referrer) not in db['users']: return
    pct = float(db['settings'].get('affiliate_percent', 10))
    commission = round(float(amount) * pct / 100, 2)
    if commission <= 0: return
    db['users'][str(referrer)]['balance'] = round(db['users'][str(referrer)].get('balance', 0) + commission, 2)
    save_db()
    try: bot.send_message(referrer, t(referrer, 'commission_notif', amt=commission), parse_mode='Markdown')
    except Exception: pass

def handle_admin_reply(message):
    reply = message.reply_to_message
    if not reply: return False
    search = (reply.text or '') + (reply.caption or '')
    if 'User ID:' not in search: return False
    try: target_uid = search.split('User ID:')[1].strip().split()[0]
    except Exception: return False
    if target_uid not in db['users']: return False
    header = LANG[get_lang(target_uid)]['support_reply']
    try:
        if message.photo:
            cap = header.format(msg=message.caption or '')
            bot.send_photo(target_uid, message.photo[-1].file_id, caption=cap, parse_mode='Markdown')
        else:
            bot.send_message(target_uid, header.format(msg=message.text or ''), parse_mode='Markdown')
        bot.reply_to(message, '✅ Reply delivered.')
    except Exception as e:
        bot.reply_to(message, f'❌ Failed to deliver: {e}')
    return True

def send_reply_keyboard(chat_id, uid):
    l = get_lang(uid)
    mk = types.ReplyKeyboardMarkup(resize_keyboard=True, row_width=2)
    mk.add(types.KeyboardButton(LANG[l]['btn_main']))
    mk.add(types.KeyboardButton(LANG[l]['btn_restart']))
    m = bot.send_message(chat_id, ".", reply_markup=mk)
    try: bot.delete_message(chat_id, m.message_id)
    except Exception: pass

def render_inline_main(chat_id, uid, msg_id=None):
    clear_state(uid)
    l = get_lang(uid)
    mk = types.InlineKeyboardMarkup(row_width=2)
    mk.add(
        types.InlineKeyboardButton(LANG[l]['inline_products'], callback_data='menu_products'),
        types.InlineKeyboardButton(LANG[l]['inline_account'], callback_data='menu_account')
    )
    mk.add(
        types.InlineKeyboardButton(LANG[l]['inline_faq'], callback_data='menu_faq'),
        types.InlineKeyboardButton(LANG[l]['btn_support'], callback_data='menu_support')
    )
    if str(uid) == str(ADMIN_ID):
        mk.add(types.InlineKeyboardButton(LANG[l]['inline_admin'], callback_data='menu_admin'))
    
    s = db['settings']
    shop = s.get('shop_name', 'My Shop')
    tagline = s.get('shop_tagline', '')
    text = f'🏠 *{shop}*\n_{tagline}_'
    logo = s.get('shop_logo')
    
    if msg_id:
        try: bot.delete_message(chat_id, msg_id)
        except Exception: pass

    try:
        if logo:
            bot.send_photo(chat_id, logo, caption=text, reply_markup=mk, parse_mode='Markdown')
        else:
            bot.send_message(chat_id, text, reply_markup=mk, parse_mode='Markdown')
    except Exception:
        bot.send_message(chat_id, text, reply_markup=mk, parse_mode='Markdown')

def render_inline_account(chat_id, uid, msg_id):
    l = get_lang(uid)
    u = db['users'][uid]
    phone = u.get('phone') or LANG[l]['phone_not_set']
    mk = types.InlineKeyboardMarkup(row_width=2)
    mk.add(
        types.InlineKeyboardButton(LANG[l]['inline_balance'], callback_data='menu_balance'),
        types.InlineKeyboardButton(LANG[l]['inline_purchases'], callback_data='menu_purchases')
    )
    mk.add(
        types.InlineKeyboardButton(LANG[l]['inline_invite'], callback_data='menu_invite'),
        types.InlineKeyboardButton(LANG[l]['inline_set_info'], callback_data='menu_set_info')
    )
    mk.add(types.InlineKeyboardButton(LANG[l]['inline_back_main'], callback_data='menu_main'))
    
    text = LANG[l]['account_title'].format(
        name=u.get('name','?'), uid=uid, phone=phone,
        bal=u.get('balance',0), purchases=len(u.get('purchases',[]))
    )
    try: bot.edit_message_caption(caption=text, chat_id=chat_id, message_id=msg_id, reply_markup=mk, parse_mode='Markdown')
    except Exception:
        try: bot.edit_message_text(text, chat_id=chat_id, message_id=msg_id, reply_markup=mk, parse_mode='Markdown')
        except Exception: pass

def render_inline_invite(chat_id, uid, msg_id):
    l = get_lang(uid)
    info = bot.get_me()
    link = f'https://t.me/{info.username}?start={uid}'
    pct = db['settings'].get('affiliate_percent', 10)
    
    total = sum(1 for u in db['users'].values() if str(u.get('referred_by')) == str(uid))
    purchased = sum(1 for u in db['users'].values() if str(u.get('referred_by')) == str(uid) and len(u.get('purchases', [])) > 0)
    
    mk = types.InlineKeyboardMarkup(row_width=1)
    mk.add(types.InlineKeyboardButton(LANG[l]['copy_link'], url=f'https://t.me/share/url?url={link}'))
    mk.add(types.InlineKeyboardButton(LANG[l]['inline_back_acc'], callback_data='menu_account'))
    
    text = LANG[l]['invite_msg'].format(pct=pct, link=link, total=total, purchased=purchased)
    try: bot.edit_message_caption(caption=text, chat_id=chat_id, message_id=msg_id, reply_markup=mk, parse_mode='Markdown')
    except Exception:
        try: bot.edit_message_text(text, chat_id=chat_id, message_id=msg_id, reply_markup=mk, parse_mode='Markdown')
        except Exception: pass

def render_inline_faq(chat_id, uid, msg_id):
    l = get_lang(uid)
    mk = types.InlineKeyboardMarkup(row_width=1)
    faqs = db.get('faqs', {})
    
    if not faqs:
        mk.add(types.InlineKeyboardButton(LANG[l]['inline_back_main'], callback_data='menu_main'))
        text = LANG[l]['faq_title'] + '\n\n' + LANG[l]['no_faqs']
    else:
        for fid, f in faqs.items():
            mk.add(types.InlineKeyboardButton(f['q'], callback_data=f'showfaq_{fid}'))
        mk.add(types.InlineKeyboardButton(LANG[l]['inline_back_main'], callback_data='menu_main'))
        text = LANG[l]['faq_title']
        
    try: bot.edit_message_caption(caption=text, chat_id=chat_id, message_id=msg_id, reply_markup=mk, parse_mode='Markdown')
    except Exception:
        try: bot.edit_message_text(text, chat_id=chat_id, message_id=msg_id, reply_markup=mk, parse_mode='Markdown')
        except Exception: pass

def render_inline_admin(chat_id, uid, msg_id):
    if str(uid) != str(ADMIN_ID): return
    l = get_lang(uid)
    mk = types.InlineKeyboardMarkup(row_width=2)
    mk.add(
        types.InlineKeyboardButton(LANG[l]['btn_set_name'],    callback_data='a_name'),
        types.InlineKeyboardButton(LANG[l]['btn_set_tagline'], callback_data='a_tagline'))
    mk.add(
        types.InlineKeyboardButton(LANG[l]['btn_set_logo'],    callback_data='a_logo'),
        types.InlineKeyboardButton(LANG[l]['btn_set_channel'], callback_data='a_channel'))
    mk.add(
        types.InlineKeyboardButton(LANG[l]['btn_affiliate'],   callback_data='a_affiliate'),
        types.InlineKeyboardButton(LANG[l]['btn_view_users'],  callback_data='a_users'))
    mk.add(
        types.InlineKeyboardButton(LANG[l]['btn_add_prod'],    callback_data='a_addprod'),
        types.InlineKeyboardButton(LANG[l]['btn_manage_prod'], callback_data='a_manageprod'))
    mk.add(
        types.InlineKeyboardButton(LANG[l]['btn_add_faq'],     callback_data='a_addfaq'),
        types.InlineKeyboardButton(LANG[l]['btn_manage_faq'],  callback_data='a_managefaq'))
    mk.add(
        types.InlineKeyboardButton(LANG[l]['btn_broadcast'],   callback_data='a_broadcast'),
        types.InlineKeyboardButton(LANG[l]['btn_assign'],      callback_data='a_assign'))
    mk.add(
        types.InlineKeyboardButton(LANG[l]['btn_add_bal'],     callback_data='a_addbal'),
        types.InlineKeyboardButton(LANG[l]['btn_set_card'],    callback_data='a_card'))
    mk.add(
        types.InlineKeyboardButton(LANG[l]['btn_set_link'],    callback_data='a_link'),
        types.InlineKeyboardButton(LANG[l]['inline_back_main'], callback_data='menu_main'))
        
    text = t(uid, 'admin_title')
    try: bot.edit_message_caption(caption=text, chat_id=chat_id, message_id=msg_id, reply_markup=mk, parse_mode='Markdown')
    except Exception:
        try: bot.edit_message_text(text, chat_id=chat_id, message_id=msg_id, reply_markup=mk, parse_mode='Markdown')
        except Exception: pass

@bot.message_handler(commands=['start'])
def cmd_start(message):
    args = message.text.split()
    referrer = args[1] if len(args) > 1 and args[1] != str(message.from_user.id) else None
    uid = ensure_user(message.from_user, referrer)
    send_reply_keyboard(message.chat.id, uid)
    
    # Send Language selector if first time, else jump to menu
    if 'lang' not in db['users'][uid] or message.text == '/start':
        s = db['settings']
        shop = s.get('shop_name', 'My Shop')
        tagline = s.get('shop_tagline', 'Your trusted online store')
        text = f'👋 *Welcome to {shop}!*\n\n_{tagline}_\n\nSelect your language / لطفا زبان خود را انتخاب کنید:'
        mk = types.InlineKeyboardMarkup()
        mk.add(
            types.InlineKeyboardButton('🇬🇧 English', callback_data='lang_en'),
            types.InlineKeyboardButton('🇮🇷 فارسی',   callback_data='lang_fa'))
        logo = s.get('shop_logo')
        try:
            if logo: bot.send_photo(message.chat.id, logo, caption=text, reply_markup=mk, parse_mode='Markdown')
            else: bot.send_message(message.chat.id, text, reply_markup=mk, parse_mode='Markdown')
        except:
            bot.send_message(message.chat.id, text, reply_markup=mk, parse_mode='Markdown')
    else:
        render_inline_main(message.chat.id, uid)

@bot.callback_query_handler(func=lambda c: c.data.startswith('lang_'))
def cb_lang(call):
    uid = ensure_user(call.from_user)
    db['users'][uid]['lang'] = call.data.split('_')[1]
    save_db()
    bot.answer_callback_query(call.id, LANG[db['users'][uid]['lang']]['lang_set'])
    send_reply_keyboard(call.message.chat.id, uid)
    if not check_join(uid, call.message.chat.id): return
    render_inline_main(call.message.chat.id, uid, call.message.message_id)

@bot.callback_query_handler(func=lambda c: c.data == 'verify_join')
def cb_verify(call):
    uid = ensure_user(call.from_user)
    channel = db['settings'].get('shop_channel')
    if not channel:
        bot.answer_callback_query(call.id)
        render_inline_main(call.message.chat.id, uid, call.message.message_id)
        return
    try:
        m = bot.get_chat_member(channel, int(uid))
        if m.status in ('member', 'administrator', 'creator'):
            bot.answer_callback_query(call.id, '✅')
            render_inline_main(call.message.chat.id, uid, call.message.message_id)
        else:
            bot.answer_callback_query(call.id, '⚠️ Please join the channel first.', show_alert=True)
    except Exception:
        bot.answer_callback_query(call.id, '⚠️ Could not verify. Try again.', show_alert=True)

@bot.message_handler(content_types=['contact'])
def handle_contact(message):
    uid = ensure_user(message.from_user)
    if not check_join(uid, message.chat.id): return
    db['users'][uid]['phone'] = message.contact.phone_number
    save_db()
    bot.send_message(message.chat.id, t(uid, 'phone_saved'), reply_markup=types.ReplyKeyboardRemove())
    send_reply_keyboard(message.chat.id, uid)
    render_inline_main(message.chat.id, uid)

@bot.message_handler(content_types=['photo'])
def handle_photo(message):
    uid = ensure_user(message.from_user)
    if not check_join(uid, message.chat.id): return
    if str(uid) == str(ADMIN_ID) and message.reply_to_message:
        if handle_admin_reply(message): return
    state = get_state(uid)
    step = state.get('step', '')
    data = state.get('data', {})
    
    if step == 'admin_logo' and str(uid) == str(ADMIN_ID):
        db['settings']['shop_logo'] = message.photo[-1].file_id
        save_db(); clear_state(uid)
        bot.send_message(message.chat.id, t(uid, 'success'))
        render_inline_admin(message.chat.id, uid, None)
    elif step == 'admin_prod_photo' and str(uid) == str(ADMIN_ID):
        pid = str(uuid.uuid4())[:8]
        db['products'][pid] = {
            'name': data.get('name', 'Product'),
            'price': data.get('price', 0),
            'desc': data.get('desc', ''),
            'photo': message.photo[-1].file_id
        }
        save_db(); clear_state(uid)
        bot.send_message(message.chat.id, t(uid, 'prod_added', name=data.get('name','')), parse_mode='Markdown')
        render_inline_admin(message.chat.id, uid, None)
    elif step == 'admin_broadcast' and str(uid) == str(ADMIN_ID):
        count = 0
        cap = message.caption or ''
        for u_id in list(db['users'].keys()):
            try: bot.send_photo(u_id, message.photo[-1].file_id, caption=cap); count += 1
            except Exception: pass
        clear_state(uid)
        bot.send_message(message.chat.id, t(uid, 'broadcast_done', count=count), parse_mode='Markdown')
        render_inline_admin(message.chat.id, uid, None)
    elif step == 'support':
        u = db['users'][uid]
        try:
            fwd = bot.forward_message(ADMIN_ID, message.chat.id, message.message_id)
            bot.send_message(ADMIN_ID, LANG['en']['support_header'].format(name=u.get('name','?'), uid=uid),
                reply_to_message_id=fwd.message_id, parse_mode='Markdown')
        except Exception: pass
        clear_state(uid)
        bot.send_message(message.chat.id, t(uid, 'support_sent'))
        render_inline_main(message.chat.id, uid)

@bot.message_handler(func=lambda m: True)
def handle_text(message):
    uid = ensure_user(message.from_user)
    text = message.text or ''
    l = get_lang(uid)
    
    if not check_join(uid, message.chat.id): return
    if str(uid) == str(ADMIN_ID) and message.reply_to_message:
        if handle_admin_reply(message): return
        
    state = get_state(uid)
    step = state.get('step', '')
    if step:
        _handle_state(message, uid, step, state.get('data', {}), text, l)
        return

    if text in (LANG['en']['btn_main'], LANG['fa']['btn_main']):
        render_inline_main(message.chat.id, uid); return
    if text in (LANG['en']['btn_restart'], LANG['fa']['btn_restart']):
        cmd_start(message); return
        
    render_inline_main(message.chat.id, uid)

def _handle_state(message, uid, step, data, text, l):
    if step == 'support':
        u = db['users'][uid]
        try:
            fwd = bot.forward_message(ADMIN_ID, message.chat.id, message.message_id)
            bot.send_message(ADMIN_ID, LANG['en']['support_header'].format(name=u.get('name','?'), uid=uid),
                reply_to_message_id=fwd.message_id, parse_mode='Markdown')
        except Exception: pass
        clear_state(uid)
        bot.send_message(message.chat.id, t(uid, 'support_sent'))
        render_inline_main(message.chat.id, uid)
        return
        
    if step == 'ask_receipt':
        amt = data.get('amt')
        try: bot.delete_message(message.chat.id, data.get('msg_id'))
        except Exception: pass
        
        clear_state(uid)
        bot.send_message(message.chat.id, t(uid, 'receipt_sent'))
        
        # Send to admin
        u = db['users'][uid]
        mk = types.InlineKeyboardMarkup()
        mk.add(
            types.InlineKeyboardButton("✅ Approve", callback_data=f"rec_ok_{uid}_{amt}"),
            types.InlineKeyboardButton("❌ Reject", callback_data=f"rec_no_{uid}_{amt}")
        )
        msg = LANG['en']['admin_receipt'].format(name=u.get('name','?'), uid=uid, amt=amt, rec=text)
        bot.send_message(ADMIN_ID, msg, reply_markup=mk, parse_mode='Markdown')
        return

    if str(uid) != str(ADMIN_ID): clear_state(uid); return

    try:
        if step == 'admin_name':
            db['settings']['shop_name'] = text; save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'success')); render_inline_admin(message.chat.id, uid, None)
        elif step == 'admin_tagline':
            db['settings']['shop_tagline'] = text; save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'success')); render_inline_admin(message.chat.id, uid, None)
        elif step == 'admin_channel':
            db['settings']['shop_channel'] = None if text.lower() == 'off' else (text if text.startswith('@') else '@'+text)
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'success')); render_inline_admin(message.chat.id, uid, None)
        elif step == 'admin_affiliate':
            db['settings']['affiliate_percent'] = float(text); save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'success')); render_inline_admin(message.chat.id, uid, None)
        elif step == 'admin_prod_name':
            set_state(uid, 'admin_prod_price', {'name': text})
            bot.send_message(message.chat.id, t(uid, 'ask_prod_price'), parse_mode='Markdown')
        elif step == 'admin_prod_price':
            set_state(uid, 'admin_prod_desc', {**data, 'price': float(text)})
            bot.send_message(message.chat.id, t(uid, 'ask_prod_desc'))
        elif step == 'admin_prod_desc':
            set_state(uid, 'admin_prod_photo', {**data, 'desc': text})
            bot.send_message(message.chat.id, t(uid, 'ask_prod_photo'), parse_mode='Markdown')
        elif step == 'admin_prod_photo':
            pid = str(uuid.uuid4())[:8]
            db['products'][pid] = {'name': data.get('name'), 'price': data.get('price'), 'desc': data.get('desc', ''), 'photo': None}
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'prod_added', name=data.get('name','')), parse_mode='Markdown')
            render_inline_admin(message.chat.id, uid, None)
        elif step == 'admin_faq_q':
            set_state(uid, 'admin_faq_a', {'q': text})
            bot.send_message(message.chat.id, t(uid, 'ask_faq_a'))
        elif step == 'admin_faq_a':
            fid = str(uuid.uuid4())[:8]
            db.setdefault('faqs', {})[fid] = {'q': data['q'], 'a': text}
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'faq_added')); render_inline_admin(message.chat.id, uid, None)
        elif step == 'admin_broadcast':
            count = 0
            for u_id in list(db['users'].keys()):
                try: bot.send_message(u_id, text); count += 1
                except Exception: pass
            clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'broadcast_done', count=count), parse_mode='Markdown')
            render_inline_admin(message.chat.id, uid, None)
        elif step == 'admin_assign_uid':
            if text not in db['users']:
                bot.send_message(message.chat.id, t(uid, 'user_not_found')); clear_state(uid); return
            set_state(uid, 'admin_assign_prod', {'target': text})
            bot.send_message(message.chat.id, t(uid, 'ask_assign_prod'))
        elif step == 'admin_assign_prod':
            set_state(uid, 'admin_assign_oid', {**data, 'item': text})
            bot.send_message(message.chat.id, t(uid, 'ask_assign_oid'), parse_mode='Markdown')
        elif step == 'admin_assign_oid':
            oid = ('BF-' + str(uuid.uuid4())[:6].upper()) if text.lower() == 'auto' else text
            db['users'][data['target']]['purchases'].append({'order_id': oid, 'item': data['item']})
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'order_assigned'))
            try: bot.send_message(data['target'], t(data['target'], 'order_notif', item=data['item'], oid=oid), parse_mode='Markdown')
            except Exception: pass
            render_inline_admin(message.chat.id, uid, None)
        elif step == 'admin_addbal_uid':
            if text not in db['users']:
                bot.send_message(message.chat.id, t(uid, 'user_not_found')); clear_state(uid); return
            set_state(uid, 'admin_addbal_amt', {'target': text})
            bot.send_message(message.chat.id, t(uid, 'ask_bal_amt'))
        elif step == 'admin_addbal_amt':
            amt = float(text)
            db['users'][data['target']]['balance'] = round(db['users'][data['target']].get('balance', 0) + amt, 2)
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'balance_added', amt=amt), parse_mode='Markdown')
            try: bot.send_message(data['target'], t(data['target'], 'balance_notif', amt=amt), parse_mode='Markdown')
            except Exception: pass
            render_inline_admin(message.chat.id, uid, None)
        elif step == 'admin_card_num':
            set_state(uid, 'admin_card_name', {'card': text})
            bot.send_message(message.chat.id, t(uid, 'ask_card_name'))
        elif step == 'admin_card_name':
            db['settings']['admin_card'] = data['card']
            db['settings']['admin_card_name'] = text
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'card_saved'))
            render_inline_admin(message.chat.id, uid, None)
        elif step == 'admin_link':
            db['settings']['direct_link'] = text
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'link_saved'))
            render_inline_admin(message.chat.id, uid, None)
        else:
            clear_state(uid)
    except Exception as e:
        logger.error(f'State error: {e}')
        bot.send_message(message.chat.id, t(uid, 'error'))
        clear_state(uid)

@bot.callback_query_handler(func=lambda c: True)
def handle_callback(call):
    uid = ensure_user(call.from_user)
    data = call.data
    l = get_lang(uid)

    if data != 'verify_join' and not check_join(uid, call.message.chat.id):
        bot.answer_callback_query(call.id); return

    # Admin Receipt Validation
    if data.startswith('rec_ok_') or data.startswith('rec_no_'):
        if str(uid) != str(ADMIN_ID): bot.answer_callback_query(call.id); return
        parts = data.split('_')
        action, target, amt = parts[1], parts[2], float(parts[3])
        if action == 'ok':
            db['users'][target]['balance'] = round(db['users'][target].get('balance', 0) + amt, 2)
            save_db()
            bot.edit_message_text(f"✅ Approved. Added ${amt} to {target}.", chat_id=call.message.chat.id, message_id=call.message.message_id)
            try: bot.send_message(target, t(target, 'receipt_approved', amt=amt), parse_mode='Markdown')
            except Exception: pass
        else:
            bot.edit_message_text(f"❌ Rejected request for {target}.", chat_id=call.message.chat.id, message_id=call.message.message_id)
            try: bot.send_message(target, t(target, 'receipt_rejected'), parse_mode='Markdown')
            except Exception: pass
        return

    # Menus
    if data == 'menu_main': bot.answer_callback_query(call.id); render_inline_main(call.message.chat.id, uid, call.message.message_id); return
    if data == 'menu_account': bot.answer_callback_query(call.id); render_inline_account(call.message.chat.id, uid, call.message.message_id); return
    if data == 'menu_invite': bot.answer_callback_query(call.id); render_inline_invite(call.message.chat.id, uid, call.message.message_id); return
    if data == 'menu_faq': bot.answer_callback_query(call.id); render_inline_faq(call.message.chat.id, uid, call.message.message_id); return
    if data == 'menu_admin': bot.answer_callback_query(call.id); render_inline_admin(call.message.chat.id, uid, call.message.message_id); return
    if data == 'menu_support':
        bot.answer_callback_query(call.id)
        set_state(uid, 'support')
        bot.send_message(call.message.chat.id, t(uid, 'support_prompt'), parse_mode='Markdown')
        return

    if data.startswith('showfaq_'):
        fid = data.split('_')[1]
        faq = db.get('faqs', {}).get(fid)
        if faq:
            mk = types.InlineKeyboardMarkup()
            mk.add(types.InlineKeyboardButton(LANG[l]['inline_back_faq'], callback_data='menu_faq'))
            mk.add(types.InlineKeyboardButton(LANG[l]['inline_back_main'], callback_data='menu_main'))
            text = LANG[l]['faq_answer'].format(q=faq['q'], a=faq['a'])
            try: bot.edit_message_caption(caption=text, chat_id=call.message.chat.id, message_id=call.message.message_id, reply_markup=mk, parse_mode='Markdown')
            except Exception:
                try: bot.edit_message_text(text, chat_id=call.message.chat.id, message_id=call.message.message_id, reply_markup=mk, parse_mode='Markdown')
                except Exception: pass
        bot.answer_callback_query(call.id)
        return

    if data == 'menu_balance':
        bot.answer_callback_query(call.id)
        bal = db['users'][uid].get('balance', 0)
        mk = types.InlineKeyboardMarkup()
        mk.add(types.InlineKeyboardButton(LANG[l]['btn_topup'], callback_data='topup'))
        bot.send_message(call.message.chat.id, t(uid, 'balance_title', bal=bal), reply_markup=mk, parse_mode='Markdown')
        return

    if data == 'menu_purchases':
        bot.answer_callback_query(call.id)
        purchases = db['users'][uid].get('purchases', [])
        if not purchases:
            bot.send_message(call.message.chat.id, t(uid, 'no_purchases'))
        else:
            rows = [LANG[l]['purchases_title']]
            for i, p in enumerate(purchases, 1): rows.append(LANG[l]['purchase_row'].format(i=i, name=p.get('item','?'), oid=p.get('order_id','?')))
            bot.send_message(call.message.chat.id, '\n'.join(rows), parse_mode='Markdown')
        return

    if data == 'menu_set_info':
        bot.answer_callback_query(call.id)
        mk = types.ReplyKeyboardMarkup(resize_keyboard=True, one_time_keyboard=True)
        mk.add(types.KeyboardButton(LANG[l]['btn_share_phone'], request_contact=True))
        mk.add(types.KeyboardButton(LANG[l]['btn_main']))
        bot.send_message(call.message.chat.id, t(uid, 'phone_prompt'), reply_markup=mk)
        return

    if data == 'menu_products':
        bot.answer_callback_query(call.id)
        if not db['products']:
            bot.send_message(call.message.chat.id, t(uid, 'no_products')); return
        bal = db['users'][uid].get('balance', 0)
        for pid, p in db['products'].items():
            mk = types.InlineKeyboardMarkup()
            mk.add(types.InlineKeyboardButton(LANG[l]['btn_buy'].format(price=p['price']), callback_data=f'buy_{pid}'))
            card = LANG[l]['product_card'].format(name=p['name'], price=p['price'], bal=bal, desc=p.get('desc',''))
            try:
                if p.get('photo'): bot.send_photo(call.message.chat.id, p['photo'], caption=card, reply_markup=mk, parse_mode='Markdown')
                else: bot.send_message(call.message.chat.id, card, reply_markup=mk, parse_mode='Markdown')
            except Exception:
                bot.send_message(call.message.chat.id, card, reply_markup=mk, parse_mode='Markdown')
        return

    if data.startswith('buy_'):
        pid = data[4:]
        if pid not in db['products']: bot.answer_callback_query(call.id, '❌ Not found.', show_alert=True); return
        p = db['products'][pid]
        price = float(p['price'])
        bal = float(db['users'][uid].get('balance', 0))
        if bal >= price:
            db['users'][uid]['balance'] = round(bal - price, 2)
            oid = 'BF-' + str(uuid.uuid4())[:6].upper()
            db['users'][uid]['purchases'].append({'order_id': oid, 'item': p['name']})
            save_db(); award_commission(uid, price)
            bot.answer_callback_query(call.id, '✅ Purchase successful!', show_alert=True)
            bot.send_message(call.message.chat.id, LANG[l]['buy_success'].format(name=p['name'], oid=oid), parse_mode='Markdown')
        else:
            need = round(price - bal, 2)
            mk = types.InlineKeyboardMarkup()
            mk.add(types.InlineKeyboardButton(LANG[l]['btn_topup'], callback_data=f'tc_{price}'))
            bot.answer_callback_query(call.id, '❌ Insufficient balance', show_alert=True)
            bot.send_message(call.message.chat.id, LANG[l]['buy_insufficient'].format(need=need), reply_markup=mk, parse_mode='Markdown')
        return

    if data == 'topup':
        bot.answer_callback_query(call.id)
        s = db['settings']
        has_c = s.get('admin_card') and s.get('admin_card_name')
        has_l = bool(s.get('direct_link'))
        if not has_c and not has_l:
            bot.send_message(call.message.chat.id, 'ℹ️ No payment methods configured.'); return
        mk = types.InlineKeyboardMarkup()
        if has_c: mk.add(types.InlineKeyboardButton(LANG[l]['btn_pay_card'], callback_data=f'tc_0'))
        if has_l: mk.add(types.InlineKeyboardButton(LANG[l]['btn_pay_link'], url=s['direct_link']))
        bot.send_message(call.message.chat.id, t(uid, 'topup_title'), reply_markup=mk, parse_mode='Markdown')
        return

    if data.startswith('tc_'):
        bot.answer_callback_query(call.id)
        amt = data.split('_')[1]
        s = db['settings']
        mk = types.InlineKeyboardMarkup()
        mk.add(types.InlineKeyboardButton(LANG[l]['btn_submit_rec'], callback_data=f'submitrec_{amt}'))
        bot.send_message(call.message.chat.id, LANG[l]['topup_card'].format(
            price=amt if amt!='0' else 'Any Amount', card=s.get('admin_card',''), name=s.get('admin_card_name','')
        ), reply_markup=mk, parse_mode='Markdown')
        return
        
    if data.startswith('submitrec_'):
        bot.answer_callback_query(call.id)
        amt = data.split('_')[1]
        msg = bot.send_message(call.message.chat.id, t(uid, 'ask_receipt'), parse_mode='Markdown')
        set_state(uid, 'ask_receipt', {'amt': amt, 'msg_id': msg.message_id})
        return

    if str(uid) != str(ADMIN_ID): bot.answer_callback_query(call.id); return

    AA = {
        'a_name': ('admin_name', 'ask_name'), 'a_tagline': ('admin_tagline', 'ask_tagline'),
        'a_logo': ('admin_logo', 'ask_logo'), 'a_channel': ('admin_channel', 'ask_channel'),
        'a_affiliate': ('admin_affiliate', 'ask_affiliate'), 'a_addprod': ('admin_prod_name', 'ask_prod_name'),
        'a_broadcast': ('admin_broadcast', 'ask_broadcast'), 'a_assign': ('admin_assign_uid', 'ask_assign_uid'),
        'a_addbal': ('admin_addbal_uid', 'ask_bal_uid'), 'a_card': ('admin_card_num', 'ask_card_num'),
        'a_link': ('admin_link', 'ask_link'), 'a_addfaq': ('admin_faq_q', 'ask_faq_q')
    }

    if data in AA:
        step, prompt = AA[data]
        set_state(uid, step)
        bot.answer_callback_query(call.id)
        bot.send_message(call.message.chat.id, t(uid, prompt), parse_mode='Markdown')
        return

    if data == 'a_users':
        count = len(db['users'])
        rows = []
        for u_id, u in list(db['users'].items())[:30]:
            rows.append(LANG[l]['user_row'].format(name=u.get('name','?'), uid=u_id, bal=u.get('balance',0)))
        bot.answer_callback_query(call.id)
        bot.send_message(call.message.chat.id, t(uid, 'users_title', count=count) + ('\n'.join(rows) if rows else t(uid, 'no_users')), parse_mode='Markdown')
        return

    if data == 'a_manageprod':
        bot.answer_callback_query(call.id)
        if not db['products']: bot.send_message(call.message.chat.id, '📋 No products.'); return
        mk = types.InlineKeyboardMarkup()
        for pid, p in db['products'].items():
            mk.add(types.InlineKeyboardButton(LANG[l]['btn_delete'].format(name=p['name']), callback_data=f'dp_{pid}'))
        bot.send_message(call.message.chat.id, t(uid, 'manage_prod_title'), reply_markup=mk, parse_mode='Markdown')
        return
        
    if data == 'a_managefaq':
        bot.answer_callback_query(call.id)
        if not db.get('faqs'): bot.send_message(call.message.chat.id, '📋 No FAQs.'); return
        mk = types.InlineKeyboardMarkup()
        for fid, f in db['faqs'].items():
            mk.add(types.InlineKeyboardButton(LANG[l]['btn_delete'].format(name=f['q'][:20]+'...'), callback_data=f'dfaq_{fid}'))
        bot.send_message(call.message.chat.id, t(uid, 'manage_faq_title'), reply_markup=mk, parse_mode='Markdown')
        return

    if data.startswith('dp_'):
        pid = data[3:]
        if pid in db['products']:
            del db['products'][pid]; save_db()
            bot.answer_callback_query(call.id, t(uid, 'prod_deleted'), show_alert=True)
            try: bot.delete_message(call.message.chat.id, call.message.message_id)
            except: pass
            render_inline_admin(call.message.chat.id, uid, None)
        else: bot.answer_callback_query(call.id, 'Not found.', show_alert=True)
        return
        
    if data.startswith('dfaq_'):
        fid = data.split('_')[1]
        if fid in db.get('faqs', {}):
            del db['faqs'][fid]; save_db()
            bot.answer_callback_query(call.id, t(uid, 'faq_deleted'), show_alert=True)
            try: bot.delete_message(call.message.chat.id, call.message.message_id)
            except: pass
            render_inline_admin(call.message.chat.id, uid, None)
        else: bot.answer_callback_query(call.id, 'Not found.', show_alert=True)
        return

    bot.answer_callback_query(call.id)

if __name__ == '__main__':
    if not BOT_TOKEN:
        logger.error('BOT_TOKEN not configured.')
        exit(1)
    logger.info(f'BlueFalcon v2.1 starting — Admin: {ADMIN_ID}')
    bot.infinity_polling(timeout=30, long_polling_timeout=20, logger_level=None)
PYEOF
}

do_install_dependencies() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -yq
    for pkg in python3 python3-pip python3-venv; do
        dpkg -l | grep -qw "$pkg" || apt-get install -yq "$pkg"
    done
}

do_setup_venv() {
    cd "$BOT_DIR"
    [ -d "venv" ] || python3 -m venv venv
    ./venv/bin/pip install --quiet --upgrade pip
    ./venv/bin/pip install --quiet -r requirements.txt
}

collect_credentials() {
    echo ""
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Bot Configuration"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    local bot_token=""
    while [ -z "$bot_token" ]; do
        printf "  Bot Token: "
        read -r bot_token
        [ -z "$bot_token" ] && echo "  Token cannot be empty."
    done
    local admin_id=""
    while [[ ! "$admin_id" =~ ^[0-9]+$ ]]; do
        printf "  Admin Telegram ID (numbers only): "
        read -r admin_id
        [[ ! "$admin_id" =~ ^[0-9]+$ ]] && echo "  Must be a numeric ID."
    done
    sed -i '/^BOT_TOKEN=/d' "$CONFIG_FILE" 2>/dev/null || true
    sed -i '/^ADMIN_ID=/d'  "$CONFIG_FILE" 2>/dev/null || true
    { echo "BOT_TOKEN=\"$bot_token\""; echo "ADMIN_ID=\"$admin_id\""; } >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    echo ""
    echo "  ✔ Credentials saved."
    sleep 1
}

install_bot() {
    echo ""
    run_task "Updating dependencies" do_install_dependencies
    collect_credentials
    run_task "Writing bot files to $BOT_DIR" do_write_bot_files
    run_task "Setting up Python virtual environment" do_setup_venv
    auto_return "✅ Installation complete!"
}

configure_bot() {
    echo ""
    collect_credentials
    auto_return "✅ Bot configured."
}

# ==========================================
# BOT CONTROL
# ==========================================
do_start_bot() {
    cd "$BOT_DIR"
    [ -f "main.py" ] || { echo "main.py not found" >&2; return 1; }
    set +u; . "$CONFIG_FILE"; set -u
    [ -n "${BOT_TOKEN:-}" ] || { echo "BOT_TOKEN missing" >&2; return 1; }
    nohup ./venv/bin/python main.py >> "$LOG_FILE" 2>&1 &
    echo $! > bot.pid
    sleep 1
}

do_stop_bot() {
    cd "$BOT_DIR"
    if [ -f "bot.pid" ]; then
        local pid
        pid=$(cat bot.pid 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid"; sleep 1
        fi
        rm -f bot.pid
    fi
}

toggle_bot() {
    local s; s=$(get_bot_status)
    if [[ "$s" == RUNNING* ]]; then
        echo ""
        run_task "Stopping Bot" do_stop_bot
        auto_return "⏹ Bot stopped."
    else
        echo ""
        run_task "Starting Bot" do_start_bot
        auto_return "✅ Bot started successfully."
    fi
}

remove_bot() {
    echo ""
    printf "  Are you sure you want to completely remove the bot? [y/N]: "
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        run_task "Stopping Bot" do_stop_bot || true
        rm -rf "$BOT_DIR"
        rm -f /usr/local/bin/bluefalcon
        auto_return "🗑 Bot removed completely."
    else
        auto_return "Canceled."
    fi
}

view_logs() {
    echo ""
    echo "  ━━━━━━━━━━━━ Bot Logs (last 40 lines) ━━━━━━━━━━━━"
    echo ""
    if [ -f "$LOG_FILE" ]; then
        tail -n 40 "$LOG_FILE"
    else
        echo "  No log file found at $LOG_FILE"
    fi
    echo ""
    printf "  Press Enter to return..."
    read -r
}

# ==========================================
# MAIN
# ==========================================
pre_flight

while true; do
    show_menu
    read -r choice
    case "$choice" in
        1) install_bot    ;;
        2) configure_bot  ;;
        3) toggle_bot     ;;
        4) remove_bot     ;;
        5) view_logs      ;;
        0) echo -e "\n  Goodbye.\n"; exit 0 ;;
        *) sleep 1        ;;
    esac
done
