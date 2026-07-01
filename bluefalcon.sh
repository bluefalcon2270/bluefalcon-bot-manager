#!/bin/bash
# ==============================================================================
# BlueFalcon Telegram Bot
# Version: v1.6
# Description: Expert-grade Linux deployment script for Telegram Bots.
# ==============================================================================

set -eEu -o pipefail

# ==========================================
# CONSTANTS & COLORS
# ==========================================
readonly SCRIPT_VERSION="v1.6"
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
        "shop_name": "Online Shop",
        "shop_logo": None,
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
                data = json.load(f)
                db.update(data)
            except:
                pass

def save_db():
    with open(DB_FILE, 'w') as f:
        json.dump(db, f)

load_db()

LANGUAGES = {
    'en': {
        'welcome': 'Welcome to {shop}!',
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
        'set_name': 'Set Shop Name',
        'set_logo': 'Set Shop Logo',
        'add_product': 'Add Product',
        'add_balance': 'Add User Balance',
        'assign_product': 'Assign Product',
        'set_card': 'Set Card Info',
        'set_link': 'Set Direct Link',
        'ask_prod_name': 'Please enter the Product Name:',
        'ask_prod_price': 'Please enter the Product Price (Number):',
        'ask_assign_uid': 'Enter User ID to assign product to:',
        'ask_assign_oid': 'Enter a unique Order ID (e.g. PayNo123):',
        'ask_assign_item': 'Enter the Product Name to deliver:',
        'ask_bal_uid': 'Enter User ID to add balance to:',
        'ask_bal_amt': 'Enter amount to add:',
        'ask_card_num': 'Enter Bank Card Number:',
        'ask_card_name': 'Enter Account Holder Name:',
        'ask_link': 'Enter Direct Payment Link:',
        'ask_shop_name': 'Enter the new Shop Name:',
        'ask_shop_logo': 'Send me the new Shop Logo (Photo):',
        'success': 'Action completed successfully!',
        'error': 'Error processing your request.'
    },
    'fa': {
        'welcome': 'به {shop} خوش آمدید!',
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
        'set_name': 'تنظیم نام فروشگاه',
        'set_logo': 'تنظیم لوگو فروشگاه',
        'add_product': 'افزودن محصول',
        'add_balance': 'افزایش موجودی کاربر',
        'assign_product': 'ثبت خرید کاربر',
        'set_card': 'تنظیمات کارت بانکی',
        'set_link': 'تنظیمات درگاه',
        'ask_prod_name': 'لطفا نام محصول را وارد کنید:',
        'ask_prod_price': 'لطفا قیمت محصول را وارد کنید:',
        'ask_assign_uid': 'آیدی کاربر را وارد کنید:',
        'ask_assign_oid': 'شماره سفارش را وارد کنید:',
        'ask_assign_item': 'نام محصول را وارد کنید:',
        'ask_bal_uid': 'آیدی کاربر را وارد کنید:',
        'ask_bal_amt': 'مبلغ شارژ را وارد کنید:',
        'ask_card_num': 'شماره کارت بانکی را وارد کنید:',
        'ask_card_name': 'نام صاحب حساب را وارد کنید:',
        'ask_link': 'لینک درگاه پرداخت را وارد کنید:',
        'ask_shop_name': 'نام جدید فروشگاه را وارد کنید:',
        'ask_shop_logo': 'لطفا عکس لوگو را ارسال کنید:',
        'success': 'عملیات با موفقیت انجام شد!',
        'error': 'خطا در پردازش اطلاعات.'
    }
}

def get_t(uid, key):
    lang = db['users'].get(str(uid), {}).get('lang', 'en')
    return LANGUAGES[lang].get(key, LANGUAGES['en'].get(key, key))

admin_states = {}

@bot.message_handler(commands=['start', 'lang'])
def send_welcome(message):
    uid = str(message.from_user.id)
    if uid not in db['users']:
        db['users'][uid] = {'lang': 'en', 'balance': 0, 'phone': 'Not Set', 'purchases': [], 'name': message.from_user.first_name}
        save_db()
        
    markup = types.InlineKeyboardMarkup()
    markup.add(types.InlineKeyboardButton("🇬🇧 English", callback_data="lang_en"),
               types.InlineKeyboardButton("🇮🇷 فارسی", callback_data="lang_fa"))
    
    shop_name = db['settings'].get('shop_name', 'Online Shop')
    text = get_t(uid, 'welcome').format(shop=shop_name) + "\n\nPlease select your language / لطفا زبان خود را انتخاب کنید:"
    
    logo = db['settings'].get('shop_logo')
    if logo:
        bot.send_photo(message.chat.id, logo, caption=text, reply_markup=markup)
    else:
        bot.reply_to(message, text, reply_markup=markup)

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
    
    shop_name = db['settings'].get('shop_name', 'Online Shop')
    bot.send_message(chat_id, get_t(uid, 'welcome').format(shop=shop_name), reply_markup=markup)

@bot.message_handler(content_types=['contact'])
def contact_handler(message):
    uid = str(message.from_user.id)
    db['users'][uid]['phone'] = message.contact.phone_number
    save_db()
    bot.reply_to(message, get_t(uid, 'phone_saved'))
    show_main_menu(message.chat.id, uid)

@bot.message_handler(content_types=['photo'])
def photo_handler(message):
    uid = str(message.from_user.id)
    if uid == str(ADMIN_ID) and admin_states.get(uid) == 'awaiting_logo':
        db['settings']['shop_logo'] = message.photo[-1].file_id
        save_db()
        admin_states[uid] = None
        bot.reply_to(message, get_t(uid, 'success'))
        show_main_menu(message.chat.id, uid)

@bot.message_handler(func=lambda message: True)
def text_handler(message):
    uid = str(message.from_user.id)
    text = message.text
    
    state = admin_states.get(uid)
    if state:
        process_admin_state(message, uid, state)
        return
        
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
        markup.add(types.InlineKeyboardButton(get_t(uid, 'set_name'), callback_data="admin_setname"))
        markup.add(types.InlineKeyboardButton(get_t(uid, 'set_logo'), callback_data="admin_setlogo"))
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
        
    elif data == "admin_setname" and uid == str(ADMIN_ID):
        admin_states[uid] = 'awaiting_name'
        bot.send_message(call.message.chat.id, get_t(uid, 'ask_shop_name'))
    elif data == "admin_setlogo" and uid == str(ADMIN_ID):
        admin_states[uid] = 'awaiting_logo'
        bot.send_message(call.message.chat.id, get_t(uid, 'ask_shop_logo'))
    elif data == "admin_addprod" and uid == str(ADMIN_ID):
        admin_states[uid] = 'awaiting_prod_name'
        bot.send_message(call.message.chat.id, get_t(uid, 'ask_prod_name'))
    elif data == "admin_assign" and uid == str(ADMIN_ID):
        admin_states[uid] = 'awaiting_assign_uid'
        bot.send_message(call.message.chat.id, get_t(uid, 'ask_assign_uid'))
    elif data == "admin_bal" and uid == str(ADMIN_ID):
        admin_states[uid] = 'awaiting_bal_uid'
        bot.send_message(call.message.chat.id, get_t(uid, 'ask_bal_uid'))
    elif data == "admin_setcard" and uid == str(ADMIN_ID):
        admin_states[uid] = 'awaiting_card_num'
        bot.send_message(call.message.chat.id, get_t(uid, 'ask_card_num'))
    elif data == "admin_setlink" and uid == str(ADMIN_ID):
        admin_states[uid] = 'awaiting_link'
        bot.send_message(call.message.chat.id, get_t(uid, 'ask_link'))

# FSM Processor
admin_temp = {}

def process_admin_state(message, uid, state):
    text = message.text
    try:
        if state == 'awaiting_name':
            db['settings']['shop_name'] = text
            save_db()
            admin_states[uid] = None
            bot.reply_to(message, get_t(uid, 'success'))
            show_main_menu(message.chat.id, uid)
            
        elif state == 'awaiting_prod_name':
            admin_temp[uid] = {'prod_name': text}
            admin_states[uid] = 'awaiting_prod_price'
            bot.reply_to(message, get_t(uid, 'ask_prod_price'))
            
        elif state == 'awaiting_prod_price':
            price = float(text)
            pid = str(uuid.uuid4())[:6]
            db['products'][pid] = {"name": admin_temp[uid]['prod_name'], "price": price}
            save_db()
            admin_states[uid] = None
            bot.reply_to(message, get_t(uid, 'success'))
            
        elif state == 'awaiting_assign_uid':
            if text in db['users']:
                admin_temp[uid] = {'assign_uid': text}
                admin_states[uid] = 'awaiting_assign_oid'
                bot.reply_to(message, get_t(uid, 'ask_assign_oid'))
            else:
                bot.reply_to(message, "User not found.")
                admin_states[uid] = None
                
        elif state == 'awaiting_assign_oid':
            admin_temp[uid]['assign_oid'] = text
            admin_states[uid] = 'awaiting_assign_item'
            bot.reply_to(message, get_t(uid, 'ask_assign_item'))
            
        elif state == 'awaiting_assign_item':
            item = text
            target_uid = admin_temp[uid]['assign_uid']
            oid = admin_temp[uid]['assign_oid']
            db['users'][target_uid]['purchases'].append({"order_id": oid, "item": item})
            save_db()
            admin_states[uid] = None
            bot.reply_to(message, get_t(uid, 'success'))
            bot.send_message(target_uid, f"Admin delivered a purchase! Order ID: {oid}")
            
        elif state == 'awaiting_bal_uid':
            if text in db['users']:
                admin_temp[uid] = {'bal_uid': text}
                admin_states[uid] = 'awaiting_bal_amt'
                bot.reply_to(message, get_t(uid, 'ask_bal_amt'))
            else:
                bot.reply_to(message, "User not found.")
                admin_states[uid] = None
                
        elif state == 'awaiting_bal_amt':
            amt = float(text)
            target_uid = admin_temp[uid]['bal_uid']
            db['users'][target_uid]['balance'] += amt
            save_db()
            admin_states[uid] = None
            bot.reply_to(message, get_t(uid, 'success'))
            bot.send_message(target_uid, f"Your balance increased by ${amt}")
            
        elif state == 'awaiting_card_num':
            admin_temp[uid] = {'card_num': text}
            admin_states[uid] = 'awaiting_card_name'
            bot.reply_to(message, get_t(uid, 'ask_card_name'))
            
        elif state == 'awaiting_card_name':
            db['settings']['admin_card'] = admin_temp[uid]['card_num']
            db['settings']['admin_name'] = text
            save_db()
            admin_states[uid] = None
            bot.reply_to(message, get_t(uid, 'success'))
            
        elif state == 'awaiting_link':
            db['settings']['direct_link'] = text
            save_db()
            admin_states[uid] = None
            bot.reply_to(message, get_t(uid, 'success'))
            
    except Exception as e:
        bot.reply_to(message, get_t(uid, 'error'))
        admin_states[uid] = None

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

install_bot() {
    echo ""
    run_task "Installing environment and generating bot" do_install_dependencies
    echo -e "${GREEN}Dependencies processed successfully.${NC}"
    
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
    
    echo -e "${GREEN}Configuration secured!${NC}"
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

toggle_bot() {
    echo ""
    if [ -f "$BOT_DIR/bot.pid" ] && kill -0 $(cat "$BOT_DIR/bot.pid" 2>/dev/null) 2>/dev/null; then
        run_task "Stopping Bot service" do_stop_bot
    else
        run_task "Starting Bot service" do_start_bot
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
    local status="${RED}Stopped${NC}"
    if [ -f "$BOT_DIR/bot.pid" ] && kill -0 $(cat "$BOT_DIR/bot.pid" 2>/dev/null) 2>/dev/null; then
        status="${GREEN}Running${NC}"
    fi

    echo -e "${BOLD_BLUE}======================================================${NC}"
    echo -e "${BOLD_BLUE}             BlueFalcon Telegram Bot ${SCRIPT_VERSION}              ${NC}"
    echo -e "${BOLD_BLUE}======================================================${NC}"
    echo -e " Bot Status: ${status}"
    echo -e "${BOLD_BLUE}------------------------------------------------------${NC}"
    echo -e " 1) Install Bot"
    echo -e " 2) Start/Stop Bot"
    echo -e " 3) Logs"
    echo -e " 0) Exit"
    echo -e "${BOLD_BLUE}------------------------------------------------------${NC}"
}

main_loop() {
    while true; do
        display_menu
        tput cnorm
        read -p "Select option: " choice
        
        # Input Validation
        if [[ ! "$choice" =~ ^[0-3]$ ]]; then
            echo -e "${RED}Invalid input. Please enter a valid number.${NC}"
            sleep 1
            continue
        fi

        case $choice in
            1) install_bot ;;
            2) toggle_bot ;;
            3) show_logs ;;
            0) cleanup ;;
        esac
    done
}

# ==========================================
# ENTRY POINT
# ==========================================
pre_flight
main_loop
