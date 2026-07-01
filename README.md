# BlueFalcon Bot Manager

An expert-grade, rigorously strict Linux deployment and management script for Telegram Bots. Engineered specifically for modern Debian and Ubuntu server environments, prioritizing security, idempotency, and professional UI/UX.

## Features

- **Strict Mode Operations:** Runs under `set -eEu -o pipefail` to guarantee failure on unhandled errors, undefined variables, or pipeline issues.
- **Idempotency:** Re-running functions (such as package installations or configurations) will not corrupt or unnecessarily modify the system.
- **Non-Interactive APT:** Silently processes dependencies (`DEBIAN_FRONTEND=noninteractive`) without freezing the terminal.
- **Pre-Flight Sanity Checks:** Validates OS versions (Debian 11+, Ubuntu 22.04+), checks for root permissions, verifies network connectivity, and checks for `apt`/`dpkg` locks before initiating the menu.
- **Secure File Handling:** Maintains separate, isolated configuration files (`/etc/bluefalcon/config.conf`) with `600` permissions. Hardcoded secrets are explicitly avoided.
- **Global Symlink Implementation:** Creates a dynamic global binary (`bluefalcon`) during first execution, allowing menu launch from anywhere in the terminal.
- **Elegant Terminal UI:** Implements strict ASCII box structures, animated braille progress spinners for background tasks, silent logging, and clean input validation without hint clutter.

## Prerequisites
- Debian 11+ or Ubuntu 22.04+
- Root access
- Active internet connection

## Installation

1. Clone or download the script to your server:
   ```bash
   wget https://raw.githubusercontent.com/your-repo/bluefalcon-bot-manager/main/bluefalcon.sh
   ```
2. Make the script executable:
   ```bash
   chmod +x bluefalcon.sh
   ```
3. Run the script as root:
   ```bash
   sudo ./bluefalcon.sh
   ```
*Note: After the first run, you can simply type `bluefalcon` from anywhere in your terminal to open the manager.*

## File Architecture

- **Bot Directory:** `/opt/bluefalcon-bot/`
- **Configuration:** `/etc/bluefalcon/config.conf`
- **Background Logs:** `/var/log/bluefalcon-script.log`
- **Virtual Environment:** `/opt/bluefalcon-bot/venv/`
