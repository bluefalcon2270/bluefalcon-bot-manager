# Changelog

All notable changes to this project will be documented in this file.

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
