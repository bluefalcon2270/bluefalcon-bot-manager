import sys

with open('bluefalcon.sh', 'r', encoding='utf-8') as f:
    lines = f.readlines()

start = -1
end = -1
for i, line in enumerate(lines):
    if 'do_write_bot_files() {' in line:
        start = i
    elif 'PYEOF' in line and start != -1 and i > start:
        end = i
        break

if start != -1 and end != -1:
    new_content = lines[:start] + ['do_update_bot_files() {\n', '    cd "$BOT_DIR"\n', '    if [ -d ".git" ]; then\n', '        git fetch --all\n', '        git reset --hard origin/main\n', '    fi\n', '}\n'] + lines[end+1:]
    with open('bluefalcon.sh', 'w', encoding='utf-8') as f:
        f.writelines(new_content)
    print('Replaced successfully')
else:
    print('Failed to find start or end')
