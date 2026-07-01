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
readonly SCRIPT_VERSION="v$(cat /opt/bluefalcon-bot/VERSION 2>/dev/null || echo 'Unknown')"
readonly CONFIG_DIR="/etc/bluefalcon"
readonly CONFIG_FILE="${CONFIG_DIR}/config.conf"
readonly LOG_FILE="/var/log/bluefalcon-bot.log"
readonly SCRIPT_LOG="/var/log/bluefalcon-script.log"
readonly BOT_DIR="/opt/bluefalcon-bot"

# Colors
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'
readonly C_CYAN='\033[0;36m'
readonly C_BOLD='\033[1m'
readonly C_RESET='\033[0m'

# ==========================================
# UTILITIES
# ==========================================
log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$SCRIPT_LOG"
}

run_task() {
    local msg="$1"
    shift
    "$@" >> "$SCRIPT_LOG" 2>&1 < /dev/null &
    local pid=$!
    local delay=0.1
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    
    tput civis
    while kill -0 "$pid" 2>/dev/null; do
        for frame in "${frames[@]}"; do
            printf "\r  [ ${C_CYAN}%s${C_RESET} ] %s" "$frame" "$msg"
            sleep $delay
        done
    done
    wait "$pid"
    local exit_status=$?
    
    if [ $exit_status -eq 0 ]; then
        printf "\r  [ ${C_GREEN}✔${C_RESET} ] %s\033[K\n" "$msg"
        log_msg "SUCCESS: $msg"
    else
        printf "\r  [ ${C_RED}✖${C_RESET} ] %s\033[K\n" "$msg"
        tput cnorm
        log_msg "FAILED: $msg"
        exit 1
    fi
    tput cnorm
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
    local status_raw
    status_raw=$(get_bot_status)
    local status_line
    if [[ "$status_raw" == RUNNING* ]]; then
        local pid="${status_raw#*PID: }"
        status_line="${C_GREEN}${C_BOLD}RUNNING${C_RESET}  ${C_CYAN}(PID: $pid)${C_RESET}"
    else
        status_line="${C_RED}${C_BOLD}STOPPED${C_RESET}"
    fi

    echo -e "${C_BLUE}${C_BOLD}=====================================================${C_RESET}"
    echo -e "${C_BLUE}${C_BOLD}      🦅 BlueFalcon Telegram Bot ($SCRIPT_VERSION) 🦅        ${C_RESET}"
    echo -e "${C_BLUE}${C_BOLD}=====================================================${C_RESET}"
    echo ""
    echo -e " Status: $status_line"
    echo ""
    echo " 1. Install / Update Bot"
    echo " 2. Configure"
    echo " 3. Start / Stop"
    echo " 4. Remove Bot"
    echo " 5. View Logs"
    echo " 0. Exit"
    echo ""
}

auto_return() {
    echo ""
    echo -e " $1"
    echo ""
    read -rp " Press Enter to return to menu..."
}

# ==========================================
# BOT FILE WRITER
# ==========================================
do_update_bot_files() {
    cd "$BOT_DIR"
    if [ -d ".git" ]; then
        git fetch --all
        git reset --hard origin/main
    fi
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
    echo -e "${C_BLUE}${C_BOLD}--- Configure Bot API ---${C_RESET}"
    local bot_token=""
    while [ -z "$bot_token" ]; do
        read -rp " Bot Token: " bot_token
        [ -z "$bot_token" ] && echo -e " ${C_RED}Required.${C_RESET}"
    done
    local admin_id=""
    while [[ ! "$admin_id" =~ ^[0-9]+$ ]]; do
        read -rp " Admin ID:  " admin_id
        [[ ! "$admin_id" =~ ^[0-9]+$ ]] && echo -e " ${C_RED}Numbers only.${C_RESET}"
    done
    sed -i '/^BOT_TOKEN=/d' "$CONFIG_FILE" 2>/dev/null || true
    sed -i '/^ADMIN_ID=/d'  "$CONFIG_FILE" 2>/dev/null || true
    { echo "BOT_TOKEN=\"$bot_token\""; echo "ADMIN_ID=\"$admin_id\""; } >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    echo ""
    echo -e " [ ${C_GREEN}✔${C_RESET} ] Saved."
    sleep 1
}

install_bot() {
    echo ""
    run_task "Install dependencies" do_install_dependencies
    run_task "Update bot files" do_update_bot_files
    run_task "Setup Python venv" do_setup_venv
    auto_return "${C_GREEN}✔ Installation complete!${C_RESET}"
}

configure_bot() {
    echo ""
    collect_credentials
    auto_return "${C_GREEN}✔ Bot configured.${C_RESET}"
}

# ==========================================
# BOT CONTROL
# ==========================================
do_start_bot() {
    cd "$BOT_DIR"
    [ -f "src/main.py" ] || { echo "src/main.py not found" >&2; return 1; }
    
    # Launch bot in background
    nohup ./venv/bin/python src/main.py >> "$LOG_FILE" 2>&1 &
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
    read -rp " Are you sure you want to completely remove the bot? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        run_task "Stopping Bot" do_stop_bot || true
        rm -rf "$BOT_DIR"
        rm -f /usr/local/bin/bluefalcon
        auto_return "[ ${C_RED}🗑${C_RESET} ] Bot removed completely."
    else
        auto_return "Canceled."
    fi
}

view_logs() {
    echo ""
    echo -e "${C_BLUE}${C_BOLD}--- Bot Logs (last 40 lines) ---${C_RESET}"
    echo ""
    if [ -f "$LOG_FILE" ]; then
        tail -n 40 "$LOG_FILE"
    else
        echo " No log file found at $LOG_FILE"
    fi
    echo ""
    read -rp " Press Enter to return..."

}

# ==========================================
# MAIN
# ==========================================
pre_flight

while true; do
    show_menu
    read -rp " Select option: " choice
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
