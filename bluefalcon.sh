#!/bin/bash
# ==============================================================================
# BlueFalcon Telegram Bot
# Version: v1.5
# Description: Expert-grade Linux deployment script for Telegram Bots.
# ==============================================================================

set -eEu -o pipefail

# ==========================================
# CONSTANTS & COLORS
# ==========================================
readonly SCRIPT_VERSION="v1.5"
readonly CONFIG_DIR="/etc/bluefalcon"
readonly CONFIG_FILE="${CONFIG_DIR}/config.conf"
readonly LOG_FILE="/var/log/bluefalcon-script.log"
readonly BOT_DIR="/opt/bluefalcon-bot"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BOLD_BLUE='\033[1;34m'
readonly NC='\033[0m' # No Color

# ==========================================
# TRAPS & GRACEFUL EXIT
# ==========================================
cleanup() {
    tput cnorm # Restore cursor
    # Release any apt locks if we created them, clean up temp files
    rm -f /tmp/bluefalcon_task.pid
    exit 0
}
trap cleanup EXIT SIGINT SIGTERM

# ==========================================
# CORE LOGIC & PRE-FLIGHT
# ==========================================
log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

run_task() {
    local msg="$1"
    shift
    tput civis
    printf "\r[ ⠋ ] %s" "$msg"
    
    # Run the command in background, capture output to log
    "$@" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    echo $pid > /tmp/bluefalcon_task.pid
    
    local delay=0.1
    local spinstr="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local status=0

    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\r[ ${YELLOW}%c${NC} ] %s" "$spinstr" "$msg"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    wait $pid || status=$?
    rm -f /tmp/bluefalcon_task.pid
    
    if [ $status -eq 0 ]; then
        printf "\r[ ${GREEN}✔${NC} ] %s\n" "$msg"
        log_msg "SUCCESS: $msg"
    else
        printf "\r[ ${RED}✖${NC} ] %s\n" "$msg"
        log_msg "FAILED: $msg (Exit Code: $status)"
        tput cnorm
        exit $status
    fi
    tput cnorm
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root.${NC}"
        exit 1
    fi
}

check_os() {
    if [ ! -f /etc/os-release ]; then
        echo -e "${RED}Error: Cannot detect OS. /etc/os-release missing.${NC}"
        exit 1
    fi
    . /etc/os-release
    if [[ "$ID" == "debian" ]]; then
        local major="${VERSION_ID%%.*}"
        if [ "$major" -lt 11 ]; then
            echo -e "${RED}Error: Debian 11+ required. Detected: $VERSION_ID${NC}"
            exit 1
        fi
    elif [[ "$ID" == "ubuntu" ]]; then
        local major="${VERSION_ID%%.*}"
        if [ "$major" -lt 22 ]; then
            echo -e "${RED}Error: Ubuntu 22.04+ required. Detected: $VERSION_ID${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Error: Unsupported OS. Only Debian and Ubuntu are supported.${NC}"
        exit 1
    fi
}

check_internet() {
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${RED}Error: No active internet connection detected.${NC}"
        exit 1
    fi
}

check_apt_locks() {
    if lsof /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || lsof /var/lib/apt/lists/lock >/dev/null 2>&1; then
        echo -e "${RED}Error: dpkg/apt is currently locked by another process.${NC}"
        exit 1
    fi
}

setup_environment() {
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$BOT_DIR"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        touch "$CONFIG_FILE"
    fi
    chmod 600 "$CONFIG_FILE"
    
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
    fi
    chmod 600 "$LOG_FILE"

    # Global Symlink
    local script_path
    script_path=$(realpath "$0")
    if [ ! -L /usr/local/bin/bluefalcon ]; then
        ln -s "$script_path" /usr/local/bin/bluefalcon
    fi
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
# MODULE FUNCTIONS
# ==========================================

install_pkg() {
    local pkg=$1
    if ! dpkg -l | grep -qw "$pkg"; then
        DEBIAN_FRONTEND=noninteractive apt-get install -yq "$pkg"
    fi
}

do_install_dependencies() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -yq
    install_pkg python3
    install_pkg python3-pip
    install_pkg python3-venv
    
    cd "$BOT_DIR"
    
    cat << 'EOF' > requirements.txt
pyTelegramBotAPI==4.14.0
EOF

    cat << 'EOF' > main.py
import os
import json
import uuid
import telebot
from telebot import types

CONFIG_FILE = "/etc/bluefalcon/config.conf"
DB_FILE = "db.json"

def load_config():
    config = {}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    key, val = line.strip().split('=', 1)
                    config[key] = val.strip('"\'')
    return config

config = load_config()
BOT_TOKEN = config.get("BOT_TOKEN", "")
ADMIN_ID = config.get("ADMIN_ID", "")

bot = telebot.TeleBot(BOT_TOKEN)

db = {
    "users": {},
    "products": {},
    "settings": {
        "admin_card": "1234-5678-9012-3456",
        "admin_name": "Admin Name",
        "direct_link": "https://gateway.com/pay",
        "support_info": "Admin Telegram: @admin"
    }
}

def load_db():
    global db
    if os.path.exists(DB_FILE):
        with open(DB_FILE, 'r') as f:
            try:
                db = json.load(f)
            except:
                pass

def save_db():
    with open(DB_FILE, 'w') as f:
        json.dump(db, f)

load_db()

LANGUAGES = {
    'en': {
        'welcome': 'Welcome to our Online Shop!',
        'products': '🛍 Products',
        'balance': '💳 Balance',
        'purchases': '📦 My Purchases',
        'account': '👤 My Account',
        'support': '📞 Support',
        'admin_panel': '⚙️ Admin Panel',
        'lang_changed': 'Language changed to English 🇬🇧',
        'no_products': 'No products available yet.',
        'acc_details': 'Name: {name}\nID: {id}\nPhone: {phone}\nBalance: ${bal}',
        'share_phone': '📱 Share Phone Number',
        'phone_saved': 'Phone number saved!',
        'cart_empty': 'Your cart is empty.',
        'payment_methods': 'Select Payment Method:',
        'pay_bot': 'Bot Balance',
        'pay_direct': 'Direct / Card',
        'card_info': 'Please transfer ${price} to:\nCard: {card}\nName: {name}\n\nOr pay via link: {link}\n\nAfter payment, send receipt to Admin.',
        'insufficient_bal': 'Insufficient balance!',
        'purchased_success': 'Successfully purchased from balance! Order ID: {oid}',
        'no_purchases': 'No purchases yet.',
        'admin_menu': 'Admin Panel:',
        'add_product': 'Add Product',
        'add_balance': 'Add User Balance',
        'assign_product': 'Assign Product',
        'set_card': 'Set Card Info',
        'set_link': 'Set Direct Link'
    },
    'fa': {
        'welcome': 'به فروشگاه ما خوش آمدید!',
        'products': '🛍 محصولات',
        'balance': '💳 موجودی',
        'purchases': '📦 خریدهای من',
        'account': '👤 حساب کاربری',
        'support': '📞 پشتیبانی',
        'admin_panel': '⚙️ پنل ادمین',
        'lang_changed': 'زبان به فارسی تغییر یافت 🇮🇷',
        'no_products': 'محصولی موجود نیست.',
        'acc_details': 'نام: {name}\nآیدی: {id}\nشماره: {phone}\nموجودی: ${bal}',
        'share_phone': '📱 ارسال شماره تماس',
        'phone_saved': 'شماره شما ثبت شد!',
        'cart_empty': 'سبد خرید خالی است.',
        'payment_methods': 'روش پرداخت را انتخاب کنید:',
        'pay_bot': 'موجودی ربات',
        'pay_direct': 'کارت به کارت / درگاه',
        'card_info': 'لطفا مبلغ ${price} را به کارت زیر واریز کنید:\nشماره: {card}\nنام: {name}\n\nیا از طریق لینک: {link}\n\nسپس رسید را برای پشتیبانی ارسال کنید.',
        'insufficient_bal': 'موجودی ناکافی!',
        'purchased_success': 'خرید با موفقیت انجام شد! شماره سفارش: {oid}',
        'no_purchases': 'خریدی ثبت نشده.',
        'admin_menu': 'پنل مدیریت:',
        'add_product': 'افزودن محصول',
        'add_balance': 'افزایش موجودی کاربر',
        'assign_product': 'ثبت خرید کاربر',
        'set_card': 'تنظیمات کارت بانکی',
        'set_link': 'تنظیمات درگاه'
    }
}

def get_t(uid, key):
    lang = db['users'].get(str(uid), {}).get('lang', 'en')
    return LANGUAGES[lang].get(key, LANGUAGES['en'].get(key, key))

@bot.message_handler(commands=['start', 'lang'])
def send_welcome(message):
    uid = str(message.from_user.id)
    if uid not in db['users']:
        db['users'][uid] = {'lang': 'en', 'balance': 0, 'phone': 'Not Set', 'purchases': [], 'name': message.from_user.first_name}
        save_db()
        
    markup = types.InlineKeyboardMarkup()
    markup.add(types.InlineKeyboardButton("🇬🇧 English", callback_data="lang_en"),
               types.InlineKeyboardButton("🇮🇷 فارسی", callback_data="lang_fa"))
    bot.reply_to(message, "Please select your language / لطفا زبان خود را انتخاب کنید:", reply_markup=markup)

@bot.callback_query_handler(func=lambda call: call.data.startswith('lang_'))
def callback_query(call):
    uid = str(call.from_user.id)
    lang = call.data.split('_')[1]
    db['users'][uid]['lang'] = lang
    save_db()
    
    bot.answer_callback_query(call.id, get_t(uid, 'lang_changed'))
    bot.delete_message(call.message.chat.id, call.message.message_id)
    show_main_menu(call.message.chat.id, uid)

def show_main_menu(chat_id, uid):
    markup = types.ReplyKeyboardMarkup(resize_keyboard=True, row_width=2)
    markup.add(types.KeyboardButton(get_t(uid, 'products')), types.KeyboardButton(get_t(uid, 'balance')))
    markup.add(types.KeyboardButton(get_t(uid, 'purchases')), types.KeyboardButton(get_t(uid, 'account')))
    markup.add(types.KeyboardButton(get_t(uid, 'support')))
    if str(uid) == str(ADMIN_ID):
        markup.add(types.KeyboardButton(get_t(uid, 'admin_panel')))
    
    bot.send_message(chat_id, get_t(uid, 'welcome'), reply_markup=markup)

@bot.message_handler(content_types=['contact'])
def contact_handler(message):
    uid = str(message.from_user.id)
    db['users'][uid]['phone'] = message.contact.phone_number
    save_db()
    bot.reply_to(message, get_t(uid, 'phone_saved'))
    show_main_menu(message.chat.id, uid)

@bot.message_handler(func=lambda message: True)
def text_handler(message):
    uid = str(message.from_user.id)
    text = message.text
    
    if text in [LANGUAGES['en']['products'], LANGUAGES['fa']['products']]:
        if not db['products']:
            bot.reply_to(message, get_t(uid, 'no_products'))
        else:
            markup = types.InlineKeyboardMarkup()
            for pid, p in db['products'].items():
                markup.add(types.InlineKeyboardButton(f"{p['name']} - ${p['price']}", callback_data=f"buy_{pid}"))
            bot.reply_to(message, get_t(uid, 'products'), reply_markup=markup)
            
    elif text in [LANGUAGES['en']['balance'], LANGUAGES['fa']['balance']]:
        bal = db['users'][uid]['balance']
        markup = types.InlineKeyboardMarkup()
        markup.add(types.InlineKeyboardButton("Add Funds", callback_data="addfunds"))
        bot.reply_to(message, f"{get_t(uid, 'balance')}: ${bal}", reply_markup=markup)
        
    elif text in [LANGUAGES['en']['account'], LANGUAGES['fa']['account']]:
        u = db['users'][uid]
        msg = get_t(uid, 'acc_details').format(name=u.get('name',''), id=uid, phone=u.get('phone','N/A'), bal=u.get('balance',0))
        markup = types.ReplyKeyboardMarkup(resize_keyboard=True)
        markup.add(types.KeyboardButton(get_t(uid, 'share_phone'), request_contact=True))
        markup.add(types.KeyboardButton("Back"))
        bot.reply_to(message, msg, reply_markup=markup)
        
    elif text == "Back":
        show_main_menu(message.chat.id, uid)
        
    elif text in [LANGUAGES['en']['purchases'], LANGUAGES['fa']['purchases']]:
        purchases = db['users'][uid].get('purchases', [])
        if not purchases:
            bot.reply_to(message, get_t(uid, 'no_purchases'))
        else:
            msg = "\n".join([f"📦 {p['item']} (ID: {p['order_id']})" for p in purchases])
            bot.reply_to(message, msg)
            
    elif text in [LANGUAGES['en']['support'], LANGUAGES['fa']['support']]:
        bot.reply_to(message, db['settings']['support_info'])
        
    elif text in [LANGUAGES['en']['admin_panel'], LANGUAGES['fa']['admin_panel']] and uid == str(ADMIN_ID):
        markup = types.InlineKeyboardMarkup()
        markup.add(types.InlineKeyboardButton(get_t(uid, 'add_product'), callback_data="admin_addprod"))
        markup.add(types.InlineKeyboardButton(get_t(uid, 'assign_product'), callback_data="admin_assign"))
        markup.add(types.InlineKeyboardButton(get_t(uid, 'add_balance'), callback_data="admin_bal"))
        markup.add(types.InlineKeyboardButton(get_t(uid, 'set_card'), callback_data="admin_setcard"))
        markup.add(types.InlineKeyboardButton(get_t(uid, 'set_link'), callback_data="admin_setlink"))
        bot.reply_to(message, get_t(uid, 'admin_menu'), reply_markup=markup)

@bot.callback_query_handler(func=lambda call: True)
def inline_handler(call):
    uid = str(call.from_user.id)
    data = call.data
    
    if data.startswith("buy_"):
        pid = data.split('_')[1]
        markup = types.InlineKeyboardMarkup()
        markup.add(types.InlineKeyboardButton(get_t(uid, 'pay_bot'), callback_data=f"paybot_{pid}"))
        markup.add(types.InlineKeyboardButton(get_t(uid, 'pay_direct'), callback_data=f"paydir_{pid}"))
        bot.edit_message_text(get_t(uid, 'payment_methods'), call.message.chat.id, call.message.message_id, reply_markup=markup)
        
    elif data.startswith("paybot_"):
        pid = data.split('_')[1]
        price = db['products'][pid]['price']
        if db['users'][uid]['balance'] >= price:
            db['users'][uid]['balance'] -= price
            oid = "PayNo" + str(uuid.uuid4())[:4].upper()
            db['users'][uid]['purchases'].append({"order_id": oid, "item": db['products'][pid]['name']})
            save_db()
            bot.answer_callback_query(call.id, get_t(uid, 'purchased_success').format(oid=oid), show_alert=True)
        else:
            bot.answer_callback_query(call.id, get_t(uid, 'insufficient_bal'), show_alert=True)
            
    elif data.startswith("paydir_") or data == "addfunds":
        pid = data.split('_')[1] if "paydir_" in data else "Funds"
        price = db['products'][pid]['price'] if "paydir_" in data else "Any Amount"
        s = db['settings']
        msg = get_t(uid, 'card_info').format(price=price, card=s['admin_card'], name=s['admin_name'], link=s['direct_link'])
        bot.send_message(call.message.chat.id, msg)
        bot.answer_callback_query(call.id)
        
    elif data == "admin_addprod" and uid == str(ADMIN_ID):
        msg = bot.send_message(call.message.chat.id, "Enter Product Name and Price separated by comma (e.g. VIP Pass, 10):")
        bot.register_next_step_handler(msg, process_add_prod)
        
    elif data == "admin_assign" and uid == str(ADMIN_ID):
        msg = bot.send_message(call.message.chat.id, "Enter UserID, OrderID, ItemName separated by comma:")
        bot.register_next_step_handler(msg, process_assign)
        
    elif data == "admin_bal" and uid == str(ADMIN_ID):
        msg = bot.send_message(call.message.chat.id, "Enter UserID, Amount separated by comma:")
        bot.register_next_step_handler(msg, process_add_bal)
        
    elif data == "admin_setcard" and uid == str(ADMIN_ID):
        msg = bot.send_message(call.message.chat.id, "Enter Card Number and Name separated by comma:")
        bot.register_next_step_handler(msg, process_set_card)
        
    elif data == "admin_setlink" and uid == str(ADMIN_ID):
        msg = bot.send_message(call.message.chat.id, "Enter Direct Gateway Link:")
        bot.register_next_step_handler(msg, process_set_link)

def process_add_prod(message):
    try:
        name, price = message.text.split(',')
        pid = str(uuid.uuid4())[:6]
        db['products'][pid] = {"name": name.strip(), "price": float(price.strip())}
        save_db()
        bot.reply_to(message, "Product added.")
    except:
        bot.reply_to(message, "Format error.")

def process_assign(message):
    try:
        userid, oid, item = [x.strip() for x in message.text.split(',')]
        if userid in db['users']:
            db['users'][userid]['purchases'].append({"order_id": oid, "item": item})
            save_db()
            bot.reply_to(message, "Purchase assigned.")
            bot.send_message(userid, f"Admin delivered a purchase! Order ID: {oid}")
        else:
            bot.reply_to(message, "User not found.")
    except:
        bot.reply_to(message, "Format error.")

def process_add_bal(message):
    try:
        userid, amt = [x.strip() for x in message.text.split(',')]
        if userid in db['users']:
            db['users'][userid]['balance'] += float(amt)
            save_db()
            bot.reply_to(message, "Balance added.")
            bot.send_message(userid, f"Your balance increased by ${amt}")
        else:
            bot.reply_to(message, "User not found.")
    except:
        bot.reply_to(message, "Format error.")

def process_set_card(message):
    try:
        card, name = [x.strip() for x in message.text.split(',')]
        db['settings']['admin_card'] = card
        db['settings']['admin_name'] = name
        save_db()
        bot.reply_to(message, "Card info saved.")
    except:
        bot.reply_to(message, "Format error.")

def process_set_link(message):
    try:
        db['settings']['direct_link'] = message.text.strip()
        save_db()
        bot.reply_to(message, "Link saved.")
    except:
        bot.reply_to(message, "Format error.")

if __name__ == "__main__":
    if BOT_TOKEN:
        bot.infinity_polling()
    else:
        print("Error: BOT_TOKEN is missing")
EOF

    if [ ! -d "venv" ]; then
        python3 -m venv venv
    fi
    
    if [ -f "requirements.txt" ]; then
        ./venv/bin/pip install -r requirements.txt
    fi
}

install_dependencies() {
    echo ""
    run_task "Installing environment and generating bot" do_install_dependencies
    echo -e "${GREEN}Dependencies processed successfully.${NC}"
    read -p "Press Enter to return..."
}

configure_api() {
    echo ""
    tput cnorm
    read -p "Enter Telegram Bot Token: " bot_token
    if [[ -z "$bot_token" ]]; then
        echo -e "${RED}Error: Token cannot be empty.${NC}"
        sleep 2
        return
    fi
    
    read -p "Enter Admin Chat ID: " admin_id
    if [[ ! "$admin_id" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Chat ID must be an integer.${NC}"
        sleep 2
        return
    fi

    # Idempotent write to config
    sed -i '/^BOT_TOKEN=/d' "$CONFIG_FILE"
    sed -i '/^ADMIN_ID=/d' "$CONFIG_FILE"
    echo "BOT_TOKEN=\"$bot_token\"" >> "$CONFIG_FILE"
    echo "ADMIN_ID=\"$admin_id\"" >> "$CONFIG_FILE"
    
    echo -e "${GREEN}Configuration secured in ${CONFIG_FILE}.${NC}"
    read -p "Press Enter to return..."
}




do_start_bot() {
    cd "$BOT_DIR"
    if [ ! -f "main.py" ]; then
        echo "Error: main.py not found in $BOT_DIR" >&2
        return 1
    fi
    
    # Source config for variables
    set +u
    . "$CONFIG_FILE"
    set -u

    if [ -z "${BOT_TOKEN:-}" ]; then
        echo "Error: BOT_TOKEN is missing from config" >&2
        return 1
    fi

    nohup ./venv/bin/python main.py >> "$LOG_FILE" 2>&1 &
    echo $! > bot.pid
}

start_bot() {
    echo ""
    if [ ! -f "$BOT_DIR/bot.pid" ] || ! kill -0 $(cat "$BOT_DIR/bot.pid" 2>/dev/null) 2>/dev/null; then
        run_task "Starting Bot service" do_start_bot
    else
        echo -e "${YELLOW}Bot is already running (PID: $(cat "$BOT_DIR/bot.pid")).${NC}"
    fi
    read -p "Press Enter to return..."
}

do_stop_bot() {
    cd "$BOT_DIR"
    if [ -f "bot.pid" ]; then
        local pid=$(cat bot.pid)
        if kill -0 $pid 2>/dev/null; then
            kill $pid
        fi
        rm -f bot.pid
    fi
}

stop_bot() {
    echo ""
    run_task "Stopping Bot service" do_stop_bot
    read -p "Press Enter to return..."
}

show_logs() {
    clear
    tput cnorm
    if [ -f "$LOG_FILE" ]; then
        less "$LOG_FILE"
    else
        echo -e "${YELLOW}Log file is currently empty.${NC}"
        sleep 2
    fi
}

# ==========================================
# USER INTERFACE (UI/UX)
# ==========================================
display_menu() {
    clear
    echo -e "${BOLD_BLUE}======================================================${NC}"
    echo -e "${BOLD_BLUE}             BlueFalcon Telegram Bot ${SCRIPT_VERSION}              ${NC}"
    echo -e "${BOLD_BLUE}======================================================${NC}"
    echo -e " 1) Install Environment & Generate Bot"
    echo -e " 2) Configure Telegram API Token"
    echo -e " 3) Start Bot"
    echo -e " 4) Stop Bot"
    echo -e " 5) Show Logs"
    echo -e " 0) Exit"
    echo -e "${BOLD_BLUE}------------------------------------------------------${NC}"
}

main_loop() {
    while true; do
        display_menu
        tput cnorm
        read -p "Select option: " choice
        
        # Input Validation
        if [[ ! "$choice" =~ ^[0-5]$ ]]; then
            echo -e "${RED}Invalid input. Please enter a valid number.${NC}"
            sleep 1
            continue
        fi

        case $choice in
            1) install_dependencies ;;
            2) configure_api ;;
            3) start_bot ;;
            4) stop_bot ;;
            5) show_logs ;;
            0) cleanup ;;
        esac
    done
}

# ==========================================
# ENTRY POINT
# ==========================================
pre_flight
main_loop
