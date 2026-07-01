#!/bin/bash
# ==============================================================================
# BlueFalcon Telegram Bot
# Version: v2.0
# Description: Professional-grade Linux deployment manager for Telegram Bots.
# ==============================================================================

set -eEu -o pipefail

# ==========================================
# CONSTANTS & COLORS
# ==========================================
readonly SCRIPT_VERSION="v2.0"
readonly CONFIG_DIR="/etc/bluefalcon"
readonly CONFIG_FILE="${CONFIG_DIR}/config.conf"
readonly LOG_FILE="/var/log/bluefalcon-bot.log"
readonly SCRIPT_LOG="/var/log/bluefalcon-script.log"
readonly BOT_DIR="/opt/bluefalcon-bot"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# ==========================================
# TRAPS & GRACEFUL EXIT
# ==========================================
cleanup() {
    tput cnorm 2>/dev/null || true
    rm -f /tmp/bluefalcon_task.pid
}
trap cleanup EXIT SIGINT SIGTERM

# ==========================================
# UTILITIES
# ==========================================
log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$SCRIPT_LOG"
}

run_task() {
    local msg="$1"
    shift
    tput civis 2>/dev/null || true
    printf "\r  [ ${YELLOW}⠋${NC} ] %s" "$msg"

    "$@" >> "$SCRIPT_LOG" 2>&1 &
    local pid=$!
    echo $pid > /tmp/bluefalcon_task.pid

    local spinstr="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local status=0

    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\r  [ ${YELLOW}%c${NC} ] %s" "$spinstr" "$msg"
        spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
    done
    wait $pid || status=$?
    rm -f /tmp/bluefalcon_task.pid

    if [ $status -eq 0 ]; then
        printf "\r  [ ${GREEN}✔${NC} ] %s\n" "$msg"
        log_msg "SUCCESS: $msg"
    else
        printf "\r  [ ${RED}✖${NC} ] %s\n" "$msg"
        log_msg "FAILED: $msg (Exit Code: $status)"
        tput cnorm 2>/dev/null || true
        exit $status
    fi
    tput cnorm 2>/dev/null || true
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root (sudo).${NC}"
        exit 1
    fi
}

check_os() {
    if [ ! -f /etc/os-release ]; then
        echo -e "${RED}Error: Cannot detect OS.${NC}"; exit 1
    fi
    . /etc/os-release
    if [[ "$ID" == "debian" ]]; then
        local major="${VERSION_ID%%.*}"
        [ "$major" -ge 11 ] || { echo -e "${RED}Error: Debian 11+ required.${NC}"; exit 1; }
    elif [[ "$ID" == "ubuntu" ]]; then
        local major="${VERSION_ID%%.*}"
        [ "$major" -ge 22 ] || { echo -e "${RED}Error: Ubuntu 22.04+ required.${NC}"; exit 1; }
    else
        echo -e "${RED}Error: Only Debian/Ubuntu supported.${NC}"; exit 1
    fi
}

check_internet() {
    ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 || {
        echo -e "${RED}Error: No internet connection.${NC}"; exit 1
    }
}

check_apt_locks() {
    if lsof /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
        echo -e "${RED}Error: apt/dpkg is locked.${NC}"; exit 1
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
            echo "RUNNING:$pid"; return
        fi
    fi
    echo "STOPPED"
}

# ==========================================
# DISPLAY MENU
# ==========================================
show_menu() {
    clear
    local status_info
    status_info=$(get_bot_status)
    local status_line

    if [[ "$status_info" == RUNNING:* ]]; then
        local pid="${status_info#RUNNING:}"
        status_line="${GREEN}${BOLD}● RUNNING${NC}  ${DIM}PID: $pid${NC}"
    else
        status_line="${RED}${BOLD}○ STOPPED${NC}"
    fi

    echo -e "${BOLD}${CYAN}"
    echo    "  ╔══════════════════════════════════════════════╗"
    echo    "  ║       🦅  BlueFalcon Bot Manager             ║"
    printf  "  ║       Version: %-30s ║\n" "$SCRIPT_VERSION"
    echo    "  ╠══════════════════════════════════════════════╣"
    printf  "  ║  Status: %-36b ║\n" "$status_line"
    echo    "  ╠══════════════════════════════════════════════╣${NC}"
    echo -e "  ${CYAN}║${NC}  ${BOLD}1)${NC}  Install / Reinstall Bot               ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}  ${BOLD}2)${NC}  Start Bot                             ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}  ${BOLD}3)${NC}  Stop Bot                              ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}  ${BOLD}4)${NC}  Restart Bot                           ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}  ${BOLD}5)${NC}  View Logs                             ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}  ${BOLD}0)${NC}  Exit                                  ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    printf "  ${BOLD}Select option:${NC} "
}

auto_return() {
    echo -e "\n  ${GREEN}${1:-Done.}${NC}"
    echo -e "  ${DIM}Returning to menu in 3 seconds...${NC}"
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
import os, json, uuid, logging, copy
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

# ─── Config ───────────────────────────────────────────────────────────────────
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

# ─── Database ─────────────────────────────────────────────────────────────────
DEFAULT_DB = {
    'users': {},
    'products': {},
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

# ─── State Machine ────────────────────────────────────────────────────────────
states = {}

def get_state(uid): return states.get(str(uid), {})
def set_state(uid, step, data=None): states[str(uid)] = {'step': step, 'data': data or {}}
def clear_state(uid): states.pop(str(uid), None)

# ─── Strings ──────────────────────────────────────────────────────────────────
LANG = {
'en': {
    'btn_products':    '🛍️ Products',
    'btn_balance':     '💳 My Balance',
    'btn_purchases':   '📦 My Purchases',
    'btn_account':     '👤 My Account',
    'btn_support':     '📞 Support',
    'btn_restart':     '🔄 Restart',
    'btn_admin':       '⚙️ Admin Panel',
    'btn_back':        '◀️ Back',
    'btn_share_phone': '📱 Share Phone Number',
    'btn_invite':      '🔗 Invite Friends',
    'btn_topup':       '💳 Top Up Balance',
    'btn_pay_card':    '🏦 Card to Card',
    'btn_pay_link':    '🔗 Pay Online',
    'btn_join':        '📢 Join Channel',
    'btn_verify':      '✅ I Joined — Verify',
    'btn_buy':         '🛒 Buy Now — ${price}',
    'btn_delete':      '🗑️ Delete: {name}',
    'lang_set':        '✅ Language set to English 🇬🇧',
    'force_join':      '⚠️ *Join Required*\n\nYou must join our channel to use this bot.',
    'no_products':     '🛒 No products available yet. Check back later!',
    'product_card':    '🛍️ *{name}*\n💰 Price: *${price}*\n💳 Your Balance: *${bal}*\n\n{desc}',
    'buy_success':     '✅ *Purchase Successful!*\n\n📦 {name}\n🔖 Order ID: `{oid}`\n\nThank you! The admin will be in touch shortly.',
    'buy_insufficient':'❌ *Insufficient Balance*\n\nYou need *${need}* more to complete this purchase.',
    'balance_title':   '💳 *Your Balance*\n\nAvailable: *${bal}*',
    'topup_title':     '💳 *Top Up Balance*\n\nChoose a payment method:',
    'topup_card':      '🏦 *Card to Card Payment*\n\n💰 Amount: *${price}*\n🔢 Card: `{card}`\n👤 Name: *{name}*\n\nAfter payment, send your receipt to *Support*.',
    'account_title':   '👤 *My Account*\n\n• Name: *{name}*\n• ID: `{uid}`\n• Phone: {phone}\n• Balance: *${bal}*\n• Purchases: *{purchases}*',
    'phone_saved':     '✅ Phone number saved!',
    'phone_not_set':   'Not shared',
    'invite_msg':      '🔗 *Invite & Earn!*\n\nEarn *{pct}%* commission on every purchase made via your link!\n\nYour link:\n`{link}`',
    'commission_notif':'🎉 You earned *${amt}* commission from a referral purchase!',
    'no_purchases':    '📦 You have no purchases yet.',
    'purchases_title': '📦 *My Purchases*\n\n',
    'purchase_row':    '{i}. *{name}* — `{oid}`',
    'support_prompt':  '📞 *Support*\n\nSend your message and our team will reply as soon as possible.',
    'support_sent':    '✅ Your message has been sent! We\'ll reply here shortly.',
    'support_header':  '💬 *Support from {name}*\nUser ID: {uid}\n\n_Reply to this message to respond to the user._',
    'support_reply':   '📩 *Support Reply:*\n\n{msg}',
    'admin_title':     '⚙️ *Admin Panel*\n\nManage your shop:',
    'btn_set_name':    '🏪 Shop Name',
    'btn_set_tagline': '📝 Tagline',
    'btn_set_logo':    '🖼️ Shop Logo',
    'btn_set_channel': '📢 Force Join Channel',
    'btn_affiliate':   '💹 Affiliate %',
    'btn_add_prod':    '➕ Add Product',
    'btn_manage_prod': '📋 Manage Products',
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
    'manage_prod_title':'📋 *Products* — Tap a product to delete it:',
    'prod_added':      '✅ Product *{name}* added successfully!',
    'prod_deleted':    '✅ Product deleted.',
    'no_users':        'No users registered yet.',
},
'fa': {
    'btn_products':    '🛍️ محصولات',
    'btn_balance':     '💳 موجودی من',
    'btn_purchases':   '📦 خریدهای من',
    'btn_account':     '👤 حساب کاربری',
    'btn_support':     '📞 پشتیبانی',
    'btn_restart':     '🔄 شروع مجدد',
    'btn_admin':       '⚙️ پنل ادمین',
    'btn_back':        '◀️ بازگشت',
    'btn_share_phone': '📱 اشتراک شماره تماس',
    'btn_invite':      '🔗 دعوت از دوستان',
    'btn_topup':       '💳 شارژ موجودی',
    'btn_pay_card':    '🏦 کارت به کارت',
    'btn_pay_link':    '🔗 پرداخت آنلاین',
    'btn_join':        '📢 عضویت در کانال',
    'btn_verify':      '✅ عضو شدم — تایید',
    'btn_buy':         '🛒 خرید — ${price}',
    'btn_delete':      '🗑️ حذف: {name}',
    'lang_set':        '✅ زبان به فارسی تنظیم شد 🇮🇷',
    'force_join':      '⚠️ *عضویت الزامی*\n\nبرای استفاده از ربات باید عضو کانال ما شوید.',
    'no_products':     '🛒 هنوز محصولی موجود نیست.',
    'product_card':    '🛍️ *{name}*\n💰 قیمت: *${price}*\n💳 موجودی شما: *${bal}*\n\n{desc}',
    'buy_success':     '✅ *خرید موفق!*\n\n📦 {name}\n🔖 شماره سفارش: `{oid}`\n\nممنون از خریدتان! ادمین به زودی با شما تماس می‌گیرد.',
    'buy_insufficient':'❌ *موجودی ناکافی*\n\nبرای این خرید به *${need}* بیشتر نیاز دارید.',
    'balance_title':   '💳 *موجودی شما*\n\nموجودی فعلی: *${bal}*',
    'topup_title':     '💳 *شارژ موجودی*\n\nروش پرداخت را انتخاب کنید:',
    'topup_card':      '🏦 *پرداخت کارت به کارت*\n\n💰 مبلغ: *${price}*\n🔢 شماره کارت: `{card}`\n👤 نام: *{name}*\n\nپس از پرداخت رسید را به *پشتیبانی* ارسال کنید.',
    'account_title':   '👤 *حساب کاربری*\n\n• نام: *{name}*\n• آیدی: `{uid}`\n• شماره: {phone}\n• موجودی: *${bal}*\n• خریدها: *{purchases}*',
    'phone_saved':     '✅ شماره تماس ذخیره شد!',
    'phone_not_set':   'ثبت نشده',
    'invite_msg':      '🔗 *دعوت و کسب درآمد!*\n\nبرای هر خریدی از طریق لینک شما، *{pct}%* پورسانت می‌گیرید!\n\nلینک شما:\n`{link}`',
    'commission_notif':'🎉 شما *${amt}* پورسانت از یک خرید معرفی دریافت کردید!',
    'no_purchases':    '📦 شما هنوز خریدی ندارید.',
    'purchases_title': '📦 *خریدهای من*\n\n',
    'purchase_row':    '{i}. *{name}* — `{oid}`',
    'support_prompt':  '📞 *پشتیبانی*\n\nپیام خود را ارسال کنید. در اسرع وقت پاسخ می‌دهیم.',
    'support_sent':    '✅ پیام ارسال شد! به زودی پاسخ می‌دهیم.',
    'support_header':  '💬 *پیام پشتیبانی از {name}*\nUser ID: {uid}\n\n_برای پاسخ، روی این پیام ریپلای بزنید._',
    'support_reply':   '📩 *پاسخ پشتیبانی:*\n\n{msg}',
    'admin_title':     '⚙️ *پنل ادمین*\n\nمدیریت فروشگاه:',
    'btn_set_name':    '🏪 نام فروشگاه',
    'btn_set_tagline': '📝 توضیحات',
    'btn_set_logo':    '🖼️ لوگو',
    'btn_set_channel': '📢 کانال اجباری',
    'btn_affiliate':   '💹 درصد پورسانت',
    'btn_add_prod':    '➕ افزودن محصول',
    'btn_manage_prod': '📋 مدیریت محصولات',
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
    'prod_added':      '✅ محصول *{name}* با موفقیت اضافه شد!',
    'prod_deleted':    '✅ محصول حذف شد.',
    'no_users':        'هنوز کاربری ثبت نشده.',
}
}

def t(uid, key, **kw):
    lang = db['users'].get(str(uid), {}).get('lang', 'en')
    lang = lang if lang in LANG else 'en'
    text = LANG[lang].get(key, LANG['en'].get(key, f'[{key}]'))
    try: return text.format(**kw) if kw else text
    except: return text

# ─── Helpers ──────────────────────────────────────────────────────────────────
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
    if not channel or str(uid) == str(ADMIN_ID):
        return True
    try:
        m = bot.get_chat_member(channel, int(uid))
        if m.status in ('member', 'administrator', 'creator'):
            return True
    except Exception:
        pass
    lang = db['users'].get(str(uid), {}).get('lang', 'en')
    url  = f"https://t.me/{channel.lstrip('@')}"
    mk   = types.InlineKeyboardMarkup()
    mk.add(types.InlineKeyboardButton(LANG[lang]['btn_join'], url=url))
    mk.add(types.InlineKeyboardButton(LANG[lang]['btn_verify'], callback_data='verify_join'))
    bot.send_message(chat_id, LANG[lang]['force_join'], reply_markup=mk, parse_mode='Markdown')
    return False

def award_commission(buyer_uid, amount):
    referrer = db['users'].get(str(buyer_uid), {}).get('referred_by')
    if not referrer or str(referrer) not in db['users']:
        return
    pct = float(db['settings'].get('affiliate_percent', 10))
    commission = round(float(amount) * pct / 100, 2)
    if commission <= 0:
        return
    db['users'][str(referrer)]['balance'] = round(
        db['users'][str(referrer)].get('balance', 0) + commission, 2)
    save_db()
    try:
        bot.send_message(referrer, t(referrer, 'commission_notif', amt=commission), parse_mode='Markdown')
    except Exception:
        pass

def handle_admin_reply(message):
    """Route admin reply back to the correct user. Returns True if handled."""
    reply = message.reply_to_message
    if not reply:
        return False
    search = (reply.text or '') + (reply.caption or '')
    if 'User ID:' not in search:
        return False
    try:
        target_uid = search.split('User ID:')[1].strip().split()[0]
    except Exception:
        return False
    if target_uid not in db['users']:
        return False
    lang   = db['users'][target_uid].get('lang', 'en')
    header = LANG[lang]['support_reply']
    try:
        if message.photo:
            cap = header.format(msg=message.caption or '')
            bot.send_photo(target_uid, message.photo[-1].file_id, caption=cap, parse_mode='Markdown')
        else:
            bot.send_message(target_uid, header.format(msg=message.text or ''), parse_mode='Markdown')
        bot.reply_to(message, '✅ Reply delivered to user.')
    except Exception as e:
        bot.reply_to(message, f'❌ Failed to deliver: {e}')
    return True

# ─── Menu builders ────────────────────────────────────────────────────────────
def send_main_menu(chat_id, uid, text=None):
    clear_state(uid)
    lang = db['users'].get(str(uid), {}).get('lang', 'en')
    L = LANG[lang]
    mk = types.ReplyKeyboardMarkup(resize_keyboard=True, row_width=2)
    mk.add(types.KeyboardButton(L['btn_products']), types.KeyboardButton(L['btn_balance']))
    mk.add(types.KeyboardButton(L['btn_purchases']), types.KeyboardButton(L['btn_account']))
    mk.add(types.KeyboardButton(L['btn_support']), types.KeyboardButton(L['btn_restart']))
    if str(uid) == str(ADMIN_ID):
        mk.add(types.KeyboardButton(L['btn_admin']))
    shop = db['settings'].get('shop_name', 'My Shop')
    bot.send_message(chat_id, text or f'🏠 *{shop}*', reply_markup=mk, parse_mode='Markdown')

def send_admin_menu(chat_id, uid):
    if str(uid) != str(ADMIN_ID):
        return
    lang = db['users'].get(str(uid), {}).get('lang', 'en')
    L = LANG[lang]
    mk = types.InlineKeyboardMarkup(row_width=2)
    mk.add(
        types.InlineKeyboardButton(L['btn_set_name'],    callback_data='a_name'),
        types.InlineKeyboardButton(L['btn_set_tagline'], callback_data='a_tagline'))
    mk.add(
        types.InlineKeyboardButton(L['btn_set_logo'],    callback_data='a_logo'),
        types.InlineKeyboardButton(L['btn_set_channel'], callback_data='a_channel'))
    mk.add(
        types.InlineKeyboardButton(L['btn_affiliate'],   callback_data='a_affiliate'),
        types.InlineKeyboardButton(L['btn_view_users'],  callback_data='a_users'))
    mk.add(
        types.InlineKeyboardButton(L['btn_add_prod'],    callback_data='a_addprod'),
        types.InlineKeyboardButton(L['btn_manage_prod'], callback_data='a_manageprod'))
    mk.add(
        types.InlineKeyboardButton(L['btn_broadcast'],   callback_data='a_broadcast'))
    mk.add(
        types.InlineKeyboardButton(L['btn_assign'],      callback_data='a_assign'),
        types.InlineKeyboardButton(L['btn_add_bal'],     callback_data='a_addbal'))
    mk.add(
        types.InlineKeyboardButton(L['btn_set_card'],    callback_data='a_card'),
        types.InlineKeyboardButton(L['btn_set_link'],    callback_data='a_link'))
    bot.send_message(chat_id, t(uid, 'admin_title'), reply_markup=mk, parse_mode='Markdown')

def send_topup_menu(chat_id, uid, price='?'):
    lang    = db['users'].get(str(uid), {}).get('lang', 'en')
    s       = db['settings']
    has_card = s.get('admin_card') and s.get('admin_card_name')
    has_link = bool(s.get('direct_link'))
    if not has_card and not has_link:
        bot.send_message(chat_id, 'ℹ️ No payment methods configured. Contact admin.')
        return
    mk = types.InlineKeyboardMarkup()
    if has_card:
        mk.add(types.InlineKeyboardButton(LANG[lang]['btn_pay_card'], callback_data=f'tc_{price}'))
    if has_link:
        mk.add(types.InlineKeyboardButton(LANG[lang]['btn_pay_link'], url=s['direct_link']))
    bot.send_message(chat_id, t(uid, 'topup_title'), reply_markup=mk, parse_mode='Markdown')

# ─── Handlers ─────────────────────────────────────────────────────────────────
@bot.message_handler(commands=['start'])
def cmd_start(message):
    args     = message.text.split()
    referrer = args[1] if len(args) > 1 and args[1] != str(message.from_user.id) else None
    uid      = ensure_user(message.from_user, referrer)
    clear_state(uid)
    s      = db['settings']
    shop   = s.get('shop_name', 'My Shop')
    tagline= s.get('shop_tagline', 'Your trusted online store')
    logo   = s.get('shop_logo')
    text   = (f'👋 *Welcome to {shop}!*\n\n'
              f'_{tagline}_\n\n'
              f'Select your language / لطفا زبان خود را انتخاب کنید:')
    mk = types.InlineKeyboardMarkup()
    mk.add(
        types.InlineKeyboardButton('🇬🇧 English', callback_data='lang_en'),
        types.InlineKeyboardButton('🇮🇷 فارسی',   callback_data='lang_fa'))
    try:
        if logo:
            bot.send_photo(message.chat.id, logo, caption=text, reply_markup=mk, parse_mode='Markdown')
        else:
            bot.send_message(message.chat.id, text, reply_markup=mk, parse_mode='Markdown')
    except Exception:
        bot.send_message(message.chat.id, text, reply_markup=mk, parse_mode='Markdown')

@bot.callback_query_handler(func=lambda c: c.data.startswith('lang_'))
def cb_lang(call):
    uid  = ensure_user(call.from_user)
    lang = call.data.split('_')[1]
    db['users'][uid]['lang'] = lang
    save_db()
    try:
        bot.delete_message(call.message.chat.id, call.message.message_id)
    except Exception:
        pass
    bot.answer_callback_query(call.id, LANG[lang]['lang_set'])
    if not check_join(uid, call.message.chat.id):
        return
    send_main_menu(call.message.chat.id, uid)

@bot.callback_query_handler(func=lambda c: c.data == 'verify_join')
def cb_verify(call):
    uid     = ensure_user(call.from_user)
    channel = db['settings'].get('shop_channel')
    if not channel:
        bot.answer_callback_query(call.id)
        send_main_menu(call.message.chat.id, uid)
        return
    try:
        m = bot.get_chat_member(channel, int(uid))
        if m.status in ('member', 'administrator', 'creator'):
            try:
                bot.delete_message(call.message.chat.id, call.message.message_id)
            except Exception:
                pass
            bot.answer_callback_query(call.id, '✅')
            send_main_menu(call.message.chat.id, uid)
        else:
            bot.answer_callback_query(call.id, '⚠️ Please join the channel first.', show_alert=True)
    except Exception:
        bot.answer_callback_query(call.id, '⚠️ Could not verify. Try again.', show_alert=True)

@bot.message_handler(content_types=['contact'])
def handle_contact(message):
    uid = ensure_user(message.from_user)
    if not check_join(uid, message.chat.id):
        return
    db['users'][uid]['phone'] = message.contact.phone_number
    save_db()
    bot.send_message(message.chat.id, t(uid, 'phone_saved'))
    send_main_menu(message.chat.id, uid)

@bot.message_handler(content_types=['photo'])
def handle_photo(message):
    uid = ensure_user(message.from_user)
    if not check_join(uid, message.chat.id):
        return
    if str(uid) == str(ADMIN_ID) and message.reply_to_message:
        if handle_admin_reply(message):
            return
    state = get_state(uid)
    step  = state.get('step', '')
    data  = state.get('data', {})
    if step == 'admin_logo' and str(uid) == str(ADMIN_ID):
        db['settings']['shop_logo'] = message.photo[-1].file_id
        save_db(); clear_state(uid)
        bot.send_message(message.chat.id, t(uid, 'success'))
        send_admin_menu(message.chat.id, uid)
    elif step == 'admin_prod_photo' and str(uid) == str(ADMIN_ID):
        pid = data.get('pid')
        if pid and pid in db['products']:
            db['products'][pid]['photo'] = message.photo[-1].file_id
            save_db()
            name = db['products'][pid]['name']
        else:
            name = data.get('name', '?')
        clear_state(uid)
        bot.send_message(message.chat.id, t(uid, 'prod_added', name=name),
                         reply_markup=types.ReplyKeyboardRemove(), parse_mode='Markdown')
        send_admin_menu(message.chat.id, uid)
    elif step == 'admin_broadcast' and str(uid) == str(ADMIN_ID):
        count   = 0
        caption = message.caption or ''
        for u_id in list(db['users'].keys()):
            try:
                bot.send_photo(u_id, message.photo[-1].file_id, caption=caption)
                count += 1
            except Exception:
                pass
        clear_state(uid)
        bot.send_message(message.chat.id, t(uid, 'broadcast_done', count=count), parse_mode='Markdown')
        send_admin_menu(message.chat.id, uid)
    elif step == 'support':
        u = db['users'][uid]
        try:
            fwd = bot.forward_message(ADMIN_ID, message.chat.id, message.message_id)
            bot.send_message(ADMIN_ID,
                LANG['en']['support_header'].format(name=u.get('name','?'), uid=uid),
                reply_to_message_id=fwd.message_id, parse_mode='Markdown')
        except Exception as e:
            logger.error(f'Support photo forward error: {e}')
        clear_state(uid)
        bot.send_message(message.chat.id, t(uid, 'support_sent'))
        send_main_menu(message.chat.id, uid)

@bot.message_handler(func=lambda m: True)
def handle_text(message):
    uid  = ensure_user(message.from_user)
    text = message.text or ''
    lang = db['users'].get(uid, {}).get('lang', 'en')
    L    = LANG[lang]

    if not check_join(uid, message.chat.id):
        return
    if str(uid) == str(ADMIN_ID) and message.reply_to_message:
        if handle_admin_reply(message):
            return

    state = get_state(uid)
    step  = state.get('step', '')
    if step:
        _handle_state(message, uid, step, state.get('data', {}), text, lang)
        return

    # Restart
    if text in (LANG['en']['btn_restart'], LANG['fa']['btn_restart']):
        cmd_start(message); return

    # Products
    if text in (LANG['en']['btn_products'], LANG['fa']['btn_products']):
        if not db['products']:
            bot.send_message(message.chat.id, t(uid, 'no_products')); return
        bal = db['users'][uid].get('balance', 0)
        for pid, p in db['products'].items():
            mk   = types.InlineKeyboardMarkup()
            mk.add(types.InlineKeyboardButton(L['btn_buy'].format(price=p['price']), callback_data=f'buy_{pid}'))
            card = L['product_card'].format(name=p['name'], price=p['price'], bal=bal, desc=p.get('desc',''))
            try:
                if p.get('photo'):
                    bot.send_photo(message.chat.id, p['photo'], caption=card, reply_markup=mk, parse_mode='Markdown')
                else:
                    bot.send_message(message.chat.id, card, reply_markup=mk, parse_mode='Markdown')
            except Exception:
                bot.send_message(message.chat.id, card, reply_markup=mk, parse_mode='Markdown')
        return

    # Balance
    if text in (LANG['en']['btn_balance'], LANG['fa']['btn_balance']):
        bal = db['users'][uid].get('balance', 0)
        mk  = types.InlineKeyboardMarkup()
        mk.add(types.InlineKeyboardButton(L['btn_topup'], callback_data='topup'))
        bot.send_message(message.chat.id, t(uid, 'balance_title', bal=bal), reply_markup=mk, parse_mode='Markdown')
        return

    # Purchases
    if text in (LANG['en']['btn_purchases'], LANG['fa']['btn_purchases']):
        purchases = db['users'][uid].get('purchases', [])
        if not purchases:
            bot.send_message(message.chat.id, t(uid, 'no_purchases')); return
        rows = [L['purchases_title']]
        for i, p in enumerate(purchases, 1):
            rows.append(L['purchase_row'].format(i=i, name=p.get('item','?'), oid=p.get('order_id','?')))
        bot.send_message(message.chat.id, '\n'.join(rows), parse_mode='Markdown')
        return

    # Account
    if text in (LANG['en']['btn_account'], LANG['fa']['btn_account']):
        u     = db['users'][uid]
        phone = u.get('phone') or L['phone_not_set']
        mk = types.ReplyKeyboardMarkup(resize_keyboard=True, row_width=2)
        mk.add(types.KeyboardButton(L['btn_share_phone'], request_contact=True),
               types.KeyboardButton(L['btn_invite']))
        mk.add(types.KeyboardButton(L['btn_back']))
        bot.send_message(message.chat.id,
            L['account_title'].format(name=u.get('name','?'), uid=uid, phone=phone,
                                      bal=u.get('balance',0), purchases=len(u.get('purchases',[]))),
            reply_markup=mk, parse_mode='Markdown')
        return

    # Invite
    if text in (LANG['en']['btn_invite'], LANG['fa']['btn_invite']):
        info = bot.get_me()
        link = f'https://t.me/{info.username}?start={uid}'
        pct  = db['settings'].get('affiliate_percent', 10)
        bot.send_message(message.chat.id, t(uid, 'invite_msg', pct=pct, link=link), parse_mode='Markdown')
        return

    # Back
    if text in (LANG['en']['btn_back'], LANG['fa']['btn_back']):
        send_main_menu(message.chat.id, uid); return

    # Support
    if text in (LANG['en']['btn_support'], LANG['fa']['btn_support']):
        mk = types.ReplyKeyboardMarkup(resize_keyboard=True)
        mk.add(types.KeyboardButton(L['btn_back']))
        set_state(uid, 'support')
        bot.send_message(message.chat.id, t(uid, 'support_prompt'), reply_markup=mk, parse_mode='Markdown')
        return

    # Admin panel
    if text in (LANG['en']['btn_admin'], LANG['fa']['btn_admin']) and str(uid) == str(ADMIN_ID):
        send_admin_menu(message.chat.id, uid); return

    send_main_menu(message.chat.id, uid)


def _handle_state(message, uid, step, data, text, lang):
    # Support
    if step == 'support':
        if text in (LANG['en']['btn_back'], LANG['fa']['btn_back']):
            clear_state(uid); send_main_menu(message.chat.id, uid); return
        u = db['users'][uid]
        try:
            fwd = bot.forward_message(ADMIN_ID, message.chat.id, message.message_id)
            bot.send_message(ADMIN_ID,
                LANG['en']['support_header'].format(name=u.get('name','?'), uid=uid),
                reply_to_message_id=fwd.message_id, parse_mode='Markdown')
        except Exception as e:
            logger.error(f'Support forward error: {e}')
        clear_state(uid)
        bot.send_message(message.chat.id, t(uid, 'support_sent'))
        send_main_menu(message.chat.id, uid)
        return

    if str(uid) != str(ADMIN_ID):
        clear_state(uid); return

    try:
        if step == 'admin_name':
            db['settings']['shop_name'] = text
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'success'))
            send_admin_menu(message.chat.id, uid)

        elif step == 'admin_tagline':
            db['settings']['shop_tagline'] = text
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'success'))
            send_admin_menu(message.chat.id, uid)

        elif step == 'admin_channel':
            val = None if text.lower() == 'off' else (text if text.startswith('@') else '@' + text)
            db['settings']['shop_channel'] = val
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'success'))
            send_admin_menu(message.chat.id, uid)

        elif step == 'admin_affiliate':
            db['settings']['affiliate_percent'] = float(text)
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'success'))
            send_admin_menu(message.chat.id, uid)

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
            # text "skip" or anything else -> save without photo
            pid = str(uuid.uuid4())[:8]
            db['products'][pid] = {
                'name': data.get('name', 'Product'),
                'price': data.get('price', 0),
                'desc': data.get('desc', ''),
                'photo': None
            }
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'prod_added', name=data.get('name','')),
                             reply_markup=types.ReplyKeyboardRemove(), parse_mode='Markdown')
            send_admin_menu(message.chat.id, uid)

        elif step == 'admin_broadcast':
            count = 0
            for u_id in list(db['users'].keys()):
                try: bot.send_message(u_id, text); count += 1
                except Exception: pass
            clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'broadcast_done', count=count), parse_mode='Markdown')
            send_admin_menu(message.chat.id, uid)

        elif step == 'admin_assign_uid':
            if text not in db['users']:
                bot.send_message(message.chat.id, t(uid, 'user_not_found'))
                clear_state(uid); send_admin_menu(message.chat.id, uid); return
            set_state(uid, 'admin_assign_prod', {'target': text})
            bot.send_message(message.chat.id, t(uid, 'ask_assign_prod'))

        elif step == 'admin_assign_prod':
            set_state(uid, 'admin_assign_oid', {**data, 'item': text})
            bot.send_message(message.chat.id, t(uid, 'ask_assign_oid'), parse_mode='Markdown')

        elif step == 'admin_assign_oid':
            oid    = ('BF-' + str(uuid.uuid4())[:6].upper()) if text.lower() == 'auto' else text
            target = data['target']
            item   = data['item']
            db['users'][target]['purchases'].append({'order_id': oid, 'item': item})
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'order_assigned'))
            try: bot.send_message(target, t(target, 'order_notif', item=item, oid=oid), parse_mode='Markdown')
            except Exception: pass
            send_admin_menu(message.chat.id, uid)

        elif step == 'admin_addbal_uid':
            if text not in db['users']:
                bot.send_message(message.chat.id, t(uid, 'user_not_found'))
                clear_state(uid); send_admin_menu(message.chat.id, uid); return
            set_state(uid, 'admin_addbal_amt', {'target': text})
            bot.send_message(message.chat.id, t(uid, 'ask_bal_amt'))

        elif step == 'admin_addbal_amt':
            amt    = float(text)
            target = data['target']
            db['users'][target]['balance'] = round(db['users'][target].get('balance', 0) + amt, 2)
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'balance_added', amt=amt), parse_mode='Markdown')
            try: bot.send_message(target, t(target, 'balance_notif', amt=amt), parse_mode='Markdown')
            except Exception: pass
            send_admin_menu(message.chat.id, uid)

        elif step == 'admin_card_num':
            set_state(uid, 'admin_card_name', {'card': text})
            bot.send_message(message.chat.id, t(uid, 'ask_card_name'))

        elif step == 'admin_card_name':
            db['settings']['admin_card']      = data['card']
            db['settings']['admin_card_name'] = text
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'card_saved'))
            send_admin_menu(message.chat.id, uid)

        elif step == 'admin_link':
            db['settings']['direct_link'] = text
            save_db(); clear_state(uid)
            bot.send_message(message.chat.id, t(uid, 'link_saved'))
            send_admin_menu(message.chat.id, uid)

        else:
            clear_state(uid)

    except Exception as e:
        logger.error(f'State error ({step}): {e}')
        bot.send_message(message.chat.id, t(uid, 'error'))
        clear_state(uid)
        send_admin_menu(message.chat.id, uid)


@bot.callback_query_handler(func=lambda c: True)
def handle_callback(call):
    uid  = ensure_user(call.from_user)
    data = call.data

    if data != 'verify_join' and not check_join(uid, call.message.chat.id):
        bot.answer_callback_query(call.id); return

    # ── Buy ──
    if data.startswith('buy_'):
        pid = data[4:]
        if pid not in db['products']:
            bot.answer_callback_query(call.id, '❌ Product not found.', show_alert=True); return
        product = db['products'][pid]
        price   = float(product['price'])
        bal     = float(db['users'][uid].get('balance', 0))
        lang    = db['users'][uid].get('lang', 'en')
        if bal >= price:
            db['users'][uid]['balance'] = round(bal - price, 2)
            oid = 'BF-' + str(uuid.uuid4())[:6].upper()
            db['users'][uid]['purchases'].append({'order_id': oid, 'item': product['name']})
            save_db()
            award_commission(uid, price)
            bot.answer_callback_query(call.id, '✅ Purchase successful!', show_alert=True)
            bot.send_message(call.message.chat.id,
                LANG[lang]['buy_success'].format(name=product['name'], oid=oid),
                parse_mode='Markdown')
            send_main_menu(call.message.chat.id, uid)
        else:
            need = round(price - bal, 2)
            mk   = types.InlineKeyboardMarkup()
            mk.add(types.InlineKeyboardButton(LANG[lang]['btn_topup'], callback_data=f'tc_{price}'))
            bot.answer_callback_query(call.id, '❌ Insufficient balance', show_alert=True)
            bot.send_message(call.message.chat.id,
                LANG[lang]['buy_insufficient'].format(need=need),
                reply_markup=mk, parse_mode='Markdown')
        return

    # ── Top-up ──
    if data == 'topup':
        bot.answer_callback_query(call.id)
        send_topup_menu(call.message.chat.id, uid); return

    if data.startswith('tc_'):
        price = data[3:]
        s     = db['settings']
        lang  = db['users'][uid].get('lang', 'en')
        bot.answer_callback_query(call.id)
        bot.send_message(call.message.chat.id,
            LANG[lang]['topup_card'].format(
                price=price,
                card=s.get('admin_card','N/A'),
                name=s.get('admin_card_name','N/A')),
            parse_mode='Markdown')
        return

    # ── Admin actions ──
    if str(uid) != str(ADMIN_ID):
        bot.answer_callback_query(call.id); return

    ADMIN_ACTIONS = {
        'a_name':      ('admin_name',        'ask_name'),
        'a_tagline':   ('admin_tagline',     'ask_tagline'),
        'a_logo':      ('admin_logo',        'ask_logo'),
        'a_channel':   ('admin_channel',     'ask_channel'),
        'a_affiliate': ('admin_affiliate',   'ask_affiliate'),
        'a_addprod':   ('admin_prod_name',   'ask_prod_name'),
        'a_broadcast': ('admin_broadcast',   'ask_broadcast'),
        'a_assign':    ('admin_assign_uid',  'ask_assign_uid'),
        'a_addbal':    ('admin_addbal_uid',  'ask_bal_uid'),
        'a_card':      ('admin_card_num',    'ask_card_num'),
        'a_link':      ('admin_link',        'ask_link'),
    }

    if data in ADMIN_ACTIONS:
        step, prompt = ADMIN_ACTIONS[data]
        set_state(uid, step)
        bot.answer_callback_query(call.id)
        bot.send_message(call.message.chat.id, t(uid, prompt), parse_mode='Markdown')
        return

    if data == 'a_users':
        lang   = db['users'][uid].get('lang', 'en')
        count  = len(db['users'])
        rows   = []
        for u_id, u in list(db['users'].items())[:30]:
            rows.append(LANG[lang]['user_row'].format(
                name=u.get('name','?'), uid=u_id, bal=u.get('balance',0)))
        listing = '\n'.join(rows) if rows else t(uid, 'no_users')
        bot.answer_callback_query(call.id)
        bot.send_message(call.message.chat.id,
            t(uid, 'users_title', count=count) + listing, parse_mode='Markdown')
        return

    if data == 'a_manageprod':
        bot.answer_callback_query(call.id)
        if not db['products']:
            bot.send_message(call.message.chat.id, '📋 No products to manage.'); return
        lang = db['users'][uid].get('lang', 'en')
        mk   = types.InlineKeyboardMarkup()
        for pid, p in db['products'].items():
            mk.add(types.InlineKeyboardButton(
                LANG[lang]['btn_delete'].format(name=p['name']),
                callback_data=f'dp_{pid}'))
        bot.send_message(call.message.chat.id, t(uid, 'manage_prod_title'), reply_markup=mk, parse_mode='Markdown')
        return

    if data.startswith('dp_'):
        pid = data[3:]
        if pid in db['products']:
            del db['products'][pid]; save_db()
            bot.answer_callback_query(call.id, t(uid, 'prod_deleted'), show_alert=True)
            try: bot.delete_message(call.message.chat.id, call.message.message_id)
            except Exception: pass
            send_admin_menu(call.message.chat.id, uid)
        else:
            bot.answer_callback_query(call.id, 'Not found.', show_alert=True)
        return

    bot.answer_callback_query(call.id)


if __name__ == '__main__':
    if not BOT_TOKEN:
        logger.error('BOT_TOKEN not configured. Exiting.')
        exit(1)
    logger.info(f'BlueFalcon Bot v2.0 starting — Admin ID: {ADMIN_ID}')
    bot.infinity_polling(timeout=30, long_polling_timeout=20, logger_level=None)
PYEOF
}

# ==========================================
# INSTALL
# ==========================================
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
    echo -e "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BOLD}Bot Configuration${NC}"
    echo -e "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    local bot_token=""
    while [ -z "$bot_token" ]; do
        printf "  Bot Token: "
        read -r bot_token
        [ -z "$bot_token" ] && echo -e "  ${RED}Token cannot be empty.${NC}"
    done
    local admin_id=""
    while [[ ! "$admin_id" =~ ^[0-9]+$ ]]; do
        printf "  Admin Telegram ID (numbers only): "
        read -r admin_id
        [[ ! "$admin_id" =~ ^[0-9]+$ ]] && echo -e "  ${RED}Must be a numeric ID.${NC}"
    done
    sed -i '/^BOT_TOKEN=/d' "$CONFIG_FILE" 2>/dev/null || true
    sed -i '/^ADMIN_ID=/d'  "$CONFIG_FILE" 2>/dev/null || true
    { echo "BOT_TOKEN=\"$bot_token\""; echo "ADMIN_ID=\"$admin_id\""; } >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    echo -e "\n  ${GREEN}✔ Credentials saved.${NC}"
    sleep 1
}

install_bot() {
    echo ""
    run_task "Updating package lists & installing dependencies" do_install_dependencies
    collect_credentials
    run_task "Writing bot files to $BOT_DIR" do_write_bot_files
    run_task "Setting up Python virtual environment" do_setup_venv
    auto_return "✅ Installation complete! Select option 2 to start your bot."
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

start_bot() {
    local s; s=$(get_bot_status)
    if [[ "$s" == RUNNING:* ]]; then
        echo -e "\n  ${YELLOW}Bot is already running.${NC}"; sleep 2; return
    fi
    echo ""
    run_task "Starting Bot" do_start_bot
    auto_return "✅ Bot started successfully."
}

stop_bot() {
    local s; s=$(get_bot_status)
    if [[ "$s" == "STOPPED" ]]; then
        echo -e "\n  ${YELLOW}Bot is not running.${NC}"; sleep 2; return
    fi
    echo ""
    run_task "Stopping Bot" do_stop_bot
    auto_return "⏹ Bot stopped."
}

restart_bot() {
    echo ""
    local s; s=$(get_bot_status)
    [[ "$s" == RUNNING:* ]] && run_task "Stopping Bot" do_stop_bot && sleep 1
    run_task "Starting Bot" do_start_bot
    auto_return "🔄 Bot restarted successfully."
}

view_logs() {
    echo ""
    echo -e "  ${BOLD}${CYAN}━━━━━━━━━━━━ Bot Logs (last 40 lines) ━━━━━━━━━━━━${NC}"
    echo ""
    if [ -f "$LOG_FILE" ]; then
        tail -n 40 "$LOG_FILE"
    else
        echo -e "  ${DIM}No log file found at $LOG_FILE${NC}"
    fi
    echo ""
    printf "  Press ${BOLD}Enter${NC} to return..."
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
        1) install_bot  ;;
        2) start_bot    ;;
        3) stop_bot     ;;
        4) restart_bot  ;;
        5) view_logs    ;;
        0) echo -e "\n  ${DIM}Goodbye.${NC}\n"; exit 0 ;;
        *) sleep 1      ;;
    esac
done
