# BlueFalcon Ultimate Toolkit

An expert-grade, meticulously strict Linux deployment toolkit for Telegram Bots. Engineered specifically for modern Debian 11+ and Ubuntu 22.04+ server environments.

## Features

- **Strict Mode Operations:** Runs entirely under `set -eEu -o pipefail` to guarantee execution failure on unhandled errors, undefined variables, or pipeline issues.
- **Memory-Execution Bypass:** Utilizes a secure, two-stage bootstrap system (`install.sh`) to download the primary payload directly to disk, ensuring robust global symlinks that survive execution.
- **Idempotency:** Re-running core functions (such as system package installations or token configurations) will not corrupt or unnecessarily duplicate modifications on the system.
- **Non-Interactive APT:** Silently processes package dependencies (`DEBIAN_FRONTEND=noninteractive`) without freezing the terminal on system prompts.
- **Pre-Flight Sanity Checks:** Validates OS versions (Debian 11+, Ubuntu 22.04+), verifies root permissions, confirms active network connectivity, and checks for `apt`/`dpkg` locks before initiating the graphical menu.
- **Secure File Handling:** Maintains separate, isolated configuration files (`/etc/bluefalcon/config.conf`) with forced `600` permissions. Hardcoded secrets are explicitly avoided in the script source.
- **Elegant Terminal UI:** Implements strict ASCII box structures, animated braille progress spinners for background tasks, silent background logging, and clean input validation logic.

## One-Line Installation

To automatically bootstrap the environment, establish the global executable symlinks, and launch the configuration menu, run the following command as `root`:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/bluefalcon2270/bluefalcon-ultimate-toolkit/main/install.sh)
```

## Global Execution

Once the initial bootstrap completes, you can launch the BlueFalcon System Manager from anywhere in your server terminal simply by typing:

```bash
bluefalcon
```

## System Architecture

- **Main Bot Directory:** `/opt/bluefalcon-bot/`
- **Environment Configuration:** `/etc/bluefalcon/config.conf`
- **Background Execution Logs:** `/var/log/bluefalcon-script.log`
- **Bootstrap Transfer Logs:** `/var/log/bluefalcon-bootstrap.log`
- **Global Executable Binary:** `/usr/local/bin/bluefalcon`
