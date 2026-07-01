<div align="center">

# 🤖 BlueFalcon Telegram Bot

**The strict, secure, and automated Linux deployment toolkit for Telegram Bots.**

![Version](https://img.shields.io/badge/Version-v1.9-blue?style=for-the-badge)
![Linux](https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-FCC624?style=for-the-badge&logo=linux&logoColor=black)
[![Language](https://img.shields.io/badge/Written%20in-Shell/Python-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)
[![YouTube](https://img.shields.io/badge/YouTube-FF0000?style=for-the-badge&logo=youtube&logoColor=white)](https://www.youtube.com/@BlueFalcon2270)

<br />
</div>

An expert-grade, meticulously strict Linux deployment toolkit for Telegram Bots. Easngineered specifically for modern Debian and Ubuntu server environments, it handles completely automated dependency installations, secure configuration generation, and persistent background execution with a professional terminal UI.

<br>

## ⚡ Quick Run
Run this single command with root privileges on your fresh VPS. It acts as a secure bootstrap wrapper to bypass memory-execution limitations, pulling the core payload directly to your disk:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/bluefalcon2270/bluefalcon-bot-manager/main/install.sh)
```

**Global Shortcut:** Once installed, simply type `bluefalcon` from anywhere in your terminal to instantly launch the system manager!

<br>

## 🏗️ System Architecture
The toolkit is structured strictly to prevent data loss, ensure system idempotency, and isolate credentials:

* **The Bootstrap (`/install.sh`):** A lightweight memory-execution bypass that verifies your OS, installs `curl` silently if missing, and downloads the main payload.
* **The Core Payload (`/opt/bluefalcon-bot/bluefalcon.sh`):** The interactive UI and core execution logic.
* **Isolated Configurations (`/etc/bluefalcon/config.conf`):** All sensitive Telegram API tokens and Admin IDs are stored outside the code repository with strict `chmod 600` permissions.
* **Background Logs (`/var/log/bluefalcon-script.log`):** Centralized standard output tracking to keep your terminal clean while providing easy debugging.

<br>

## 🌟 Features

### 1️⃣ Strict Mode Operations
* **Bash Strictness:** Runs entirely under `set -eEu -o pipefail` to guarantee execution failure on unhandled errors, undefined variables, or pipeline issues.
* **Idempotency:** Re-running core functions (such as system package installations) will not corrupt or duplicate modifications on the server.
* **Pre-Flight Checks:** Validates OS versions, verifies root permissions, and checks for `apt`/`dpkg` locks before initiating the menu.

### 2️⃣ Automated Environment Setup
* **Non-Interactive APT:** Silently processes package dependencies (`DEBIAN_FRONTEND=noninteractive`) for `python3`, `pip`, and `venv` without freezing the terminal.
* **Python Virtual Environments:** Automatically builds an isolated `venv` and installs your exact bot dependencies via `requirements.txt`.

### 3️⃣ Professional Terminal UI
* **Clean Dashboards:** Implements strict ASCII box structures and clean input validation logic without messy terminal hints.
* **Visual Progress:** Features animated braille progress spinners (⠋⠙⠹⠸⠼) for background tasks, masking ugly system installation outputs.
* **Cursor Management:** Silently hides the terminal cursor during script execution to prevent visual artifacting.

### 4️⃣ Bot Execution & Lifecycle
* **Persistent Polling:** Securely launches your Python bot in the background using `nohup`, logging its PID to easily start, stop, or restart the service from the UI.
* **Integrated Log Viewer:** Includes a built-in menu option to instantly tail and view the background execution logs without leaving the tool.

<br>

## ✅ Supported Systems
| Distribution | Compatibility |
| :--- | :---: |
| **Ubuntu** (22.04, 24.04+) | ✅ |
| **Debian** (11, 12, 13+) | ✅ |

<br>

---
**Watch the Tutorial:** I use these exact deployment methodologies in my YouTube tutorials to ensure viewers have standardized, error-free environments. Subscribe at [@BlueFalcon2270](https://www.youtube.com/@BlueFalcon2270).
