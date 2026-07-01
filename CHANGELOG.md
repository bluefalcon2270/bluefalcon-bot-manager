# Changelog

All notable changes to this project will be documented in this file.

## v3.5 (Rich UI & Centralized Versioning):
- Transformed the short Telegram welcome messages into rich, multi-line marketing text. This naturally widens the message bubble to perfectly frame the inline menu grid below it.
- Implemented a centralized versioning architecture. A master `VERSION` file now dictates the version number for all Bash scripts and the Python bot simultaneously.
- Created `bump_version.sh` utility to automate version bumps and changelog entry generation.

## v3.4 (Telegram Bot UI Optimization & Language Selection):
- Restored the initial language selection prompt (English/Persian) when new users send `/start`.
- Deeply optimized the Telegram inline keyboard layouts to be perfectly symmetrical using explicit `row()` configurations.
- Re-balanced emojis and text lengths across `locales.py` to ensure unified visual weight on all platforms.
- Bumped Python bot core logger version to V3.1.

## v3.3 (Installer UI Parity & Sub-menu Refactor):
- Upgraded `install.sh` to use robust array-based braille spinner matching `bluefalcon.sh` and toolkit aesthetics.
- Fixed unicode rendering bug causing broken characters `[  ]` during installation process.
- Stripped all rounded borders (`╭─ ╰─`) from sub-menus (Configure, View Logs) to match minimalist toolkit aesthetic.
- Switched all UI prompts to `read -rp` to explicitly require Enter key confirmation, disabling auto-catch on paste.

## v3.2 (Ultimate Toolkit UI Parity):
- Redesigned Bash terminal menus to be a 1:1 replica of the `bluefalcon-ultimate-toolkit` aesthetic.
- Replaced rounded menu borders with classic `=` horizontal banners.
- Adjusted option numerical formatting and prompt styles for maximum simplicity.
- Striped terminal status indicators to purely text-based (no bullets) for cleaner look.

## v3.1 (Complete Architectural Overhaul & UI Upgrades):
- Separated Python codebase into a professional `src/` directory.
- Converted `bluefalcon.sh` into a lightweight, pure Bash Terminal Manager.
- Updated `install.sh` to use standard `git clone` for robust deployment.
- Redesigned Telegram texts for absolute minimalism, brevity, and modern aesthetic.
- Split bot logic into modular `bot_handlers.py`, `admin_handlers.py`, and `locales.py`.
- Integrated beautiful animated braille spinner `(⠋ ⠙ ⠹)` into the bash manager for loading tasks.
- Streamlined Terminal Menu UI with vertical list formatting and fixed rendering bugs.

v2.1.1 (Fix)

v2.1 (UI Overhaul & FAQ):
- Transitioned main bot navigation from Reply Keyboard to Inline Keyboard menus.
- Bottom keyboard now only contains Main Menu and Restart Bot.
- Redesigned "My Account" to show all stats in a clean inline message.
- "Invite Friend" sub-menu now explicitly shows copyable link, total invited, and invited with purchases.
- Dynamic FAQ System added: users can browse FAQs inline, admins can manage them via panel.
- Card-to-Card Receipt Validation: Users now submit a Receipt ID upon transfer, sending an approval card to the admin for 1-click automated balance crediting.
- Terminal UI styling fixed to prevent visual breakage and options streamlined.

v2.0 (Complete Professional Rewrite):
- Full ground-up rewrite of Python bot with clean FSM state machine architecture.
- Beautiful bilingual (EN/FA) welcome screen with shop logo on /start.
- Separate Start, Stop, Restart options in the terminal manager menu.
- Terminal menu shows live bot status (RUNNING/STOPPED) with PID.
- Buy flow: balance-only checkout with instant purchase confirmation.
- Add Funds menu shows only configured methods (card/link/both).
- Admin Panel: added View Users, Set Tagline, improved product management.
- Support desk: admin reply routing works from any reply-to context.
- Referral/affiliate commission system fully integrated.
- Auto-return after Start/Stop/Restart (no Enter required).
- All admin actions return to Admin Panel automatically.
- Separated bot log (/var/log/bluefalcon-bot.log) from script log.

v1.8:
- add Mass Broadcast System to send text and photo messages to all users.
- add Rich Products feature (Products now support photos and descriptions).
- add In-Bot Support Desk (users message bot, admin replies natively via Telegram forwarding).
- add Manage Products admin menu to view and delete products.
- upgrade product UI layout to display rich media and captions cleanly.

v1.7:
- add Mandatory Channel Join (Force Join) feature to enforce channel subscriptions.
- add Affiliate Marketing Engine with unique referral links.
- add automatic percentage-based commission payouts to Bot Balance on successful referrals.
- upgrade Admin Panel to configure Force Join Channel ID and Affiliate Commission %.
- expand My Account menu to securely generate and display unique invite deep-links.

v1.6:
- add Shop Name and Shop Logo management to Telegram Admin Panel.
- upgrade Admin Panel to use a conversational state machine (step-by-step inputs) instead of comma-separated strings.
- overhaul Bash terminal UI into a smart dashboard with real-time Bot Status.
- simplify Bash menu to "Install Bot", "Start/Stop Toggle", and "Logs".
- merge API token configuration securely into the "Install Bot" process.

v1.5:
- add fully-featured E-Commerce system generated directly by Bash.
- add Admin Panel for bot owners to manage products, settings, and deliver purchases.
- add User Wallets (Balance) and Phone Number collection.
- add manual and automatic payment workflows.
- add User Purchase History to track delivered items via Payment IDs.

v1.4:
- add dual-language support (English and Persian) to the generated Telegram bot.
- add Small Online Shop default template layout with bilingual reply keyboards.
- remove simple terminal menu configurator to support the more advanced JSON-based bilingual template.

v1.3:
- add CHANGELOG.md file to track all versions and script updates.
- fix script version consistency across `README.md`, `install.sh`, and `bluefalcon.sh`.

v1.2:
- add fully autonomous bot generation directly from the bash script.
- add dynamic `pyTelegramBotAPI` bot generation logic inside `/opt/bluefalcon-bot/`.
- add interactive terminal UI menu option to customize Telegram bot's keyboard buttons on the fly.
- remove the need for users to manually clone or upload bot files.
- fix project naming to "BlueFalcon Telegram Bot" across all scripts and documentation.

v1.1:
- Initial release of BlueFalcon Bot Manager.
