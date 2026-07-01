#!/bin/bash
# ==============================================================================
# BlueFalcon Telegram Bot - Bootstrap Installer
# Version: v1.4
# Description: Secure one-liner installation wrapper to prevent memory-execution 
#              symlink failures.
# ==============================================================================

set -eEu -o pipefail

# ==========================================
# CONSTANTS & COLORS
# ==========================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BOLD_BLUE='\033[1;34m'
readonly NC='\033[0m'

readonly BOT_DIR="/opt/bluefalcon-bot"
readonly MAIN_SCRIPT_DEST="${BOT_DIR}/bluefalcon.sh"
readonly SYMLINK_PATH="/usr/local/bin/bluefalcon"
readonly REMOTE_URL="https://raw.githubusercontent.com/bluefalcon2270/bluefalcon-bot-manager/main/bluefalcon.sh"
readonly LOG_FILE="/var/log/bluefalcon-bootstrap.log"

# ==========================================
# TRAPS & GRACEFUL EXIT
# ==========================================
cleanup() {
    tput cnorm
    rm -f /tmp/bluefalcon_bootstrap.pid
}
trap cleanup EXIT SIGINT SIGTERM

# ==========================================
# CORE LOGIC
# ==========================================
run_task() {
    local msg="$1"
    shift
    tput civis
    printf "\r[ ⠋ ] %s" "$msg"
    
    "$@" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    echo $pid > /tmp/bluefalcon_bootstrap.pid
    
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
    rm -f /tmp/bluefalcon_bootstrap.pid
    
    if [ $status -eq 0 ]; then
        printf "\r[ ${GREEN}✔${NC} ] %s\n" "$msg"
    else
        printf "\r[ ${RED}✖${NC} ] %s\n" "$msg"
        echo -e "${RED}Bootstrap failed. Check ${LOG_FILE} for details.${NC}"
        tput cnorm
        exit $status
    fi
    tput cnorm
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: The installer must be run as root.${NC}"
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
            echo -e "${RED}Error: Debian 11+ required.${NC}"
            exit 1
        fi
    elif [[ "$ID" == "ubuntu" ]]; then
        local major="${VERSION_ID%%.*}"
        if [ "$major" -lt 22 ]; then
            echo -e "${RED}Error: Ubuntu 22.04+ required.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Error: Unsupported OS. Only Debian and Ubuntu supported.${NC}"
        exit 1
    fi
}

ensure_curl() {
    if ! command -v curl >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -yq
        apt-get install -yq curl
    fi
}

download_payload() {
    mkdir -p "$BOT_DIR"
    curl -sSLo "$MAIN_SCRIPT_DEST" "$REMOTE_URL"
    chmod +x "$MAIN_SCRIPT_DEST"
}

create_symlink() {
    ln -sf "$MAIN_SCRIPT_DEST" "$SYMLINK_PATH"
}

# ==========================================
# EXECUTION
# ==========================================
clear
echo -e "${BOLD_BLUE}======================================================${NC}"
echo -e "${BOLD_BLUE}          BlueFalcon Telegram Bot Bootstrap            ${NC}"
echo -e "${BOLD_BLUE}======================================================${NC}"

touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

check_root
check_os
run_task "Verifying secure transfer protocols (curl)" ensure_curl
run_task "Downloading BlueFalcon core payload" download_payload
run_task "Establishing global CLI command" create_symlink

echo ""
echo -e "${GREEN}Installation complete! Launching BlueFalcon System...${NC}"
sleep 1.5

# Hand over execution to the main script
exec "$SYMLINK_PATH"
