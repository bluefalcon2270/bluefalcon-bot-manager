#!/bin/bash
# ==============================================================================
# BlueFalcon Bot Manager
# Version: v1.1
# Description: Expert-grade Linux deployment script for Telegram Bots.
# ==============================================================================

set -eEu -o pipefail

# ==========================================
# CONSTANTS & COLORS
# ==========================================
readonly SCRIPT_VERSION="v1.1"
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
    if [ ! -d "venv" ]; then
        python3 -m venv venv
    fi
    
    if [ -f "requirements.txt" ]; then
        ./venv/bin/pip install -r requirements.txt
    fi
}

install_dependencies() {
    echo ""
    run_task "Installing system dependencies" do_install_dependencies
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
    echo -e "${BOLD_BLUE}             BlueFalcon Bot Manager ${SCRIPT_VERSION}              ${NC}"
    echo -e "${BOLD_BLUE}======================================================${NC}"
    echo -e " 1) Install Environment & Dependencies"
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
