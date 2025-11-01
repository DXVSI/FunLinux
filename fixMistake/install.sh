#!/bin/bash

# Скрипт установки fixMistake
# Устанавливает зависимости и настраивает горячую клавишу

set -e

echo "=== Установка fixMistake ==="
echo ""

# Проверяем, что скрипт запущен на Fedora
if ! command -v dnf5 &>/dev/null && ! command -v dnf &>/dev/null; then
    echo "Ошибка: fixMistake работает только на Fedora Linux"
    exit 1
fi

# Определяем пакетный менеджер
if command -v dnf5 &>/dev/null; then
    PKG_MANAGER="dnf5"
else
    PKG_MANAGER="dnf"
fi

# Список необходимых пакетов
PACKAGES=()

# Проверяем зависимости
echo "Проверка зависимостей..."

if ! command -v xdotool &>/dev/null; then
    PACKAGES+=("xdotool")
fi

if ! command -v xclip &>/dev/null; then
    PACKAGES+=("xclip")
fi

if ! command -v xbindkeys &>/dev/null; then
    PACKAGES+=("xbindkeys")
fi

if ! command -v notify-send &>/dev/null; then
    PACKAGES+=("libnotify")
fi

# Устанавливаем недостающие пакеты
if [ ${#PACKAGES[@]} -gt 0 ]; then
    echo "Необходимо установить: ${PACKAGES[*]}"
    echo ""
    read -p "Установить сейчас? [Y/n]: " response

    if [[ "$response" =~ ^[Nn]$ ]]; then
        echo "Установка отменена"
        exit 1
    fi

    echo "Устанавливаю пакеты..."
    sudo $PKG_MANAGER install -y "${PACKAGES[@]}"
    echo "Пакеты установлены!"
else
    echo "Все зависимости уже установлены"
fi

echo ""

# Определяем путь к скрипту
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/fixmistake.sh"

# Проверяем существование скрипта
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Ошибка: не найден файл $SCRIPT_PATH"
    exit 1
fi

# Делаем скрипт исполняемым
chmod +x "$SCRIPT_PATH"

# Настраиваем xbindkeys
echo "Настройка горячей клавиши Ctrl+Alt+→..."

XBINDKEYS_CONFIG="$HOME/.xbindkeysrc"

# Создаем конфиг если не существует
if [ ! -f "$XBINDKEYS_CONFIG" ]; then
    touch "$XBINDKEYS_CONFIG"
    echo "# xbindkeys configuration" > "$XBINDKEYS_CONFIG"
    echo "" >> "$XBINDKEYS_CONFIG"
fi

# Проверяем, не добавлен ли уже хоткей
if grep -q "fixmistake.sh" "$XBINDKEYS_CONFIG"; then
    echo "Хоткей уже настроен в $XBINDKEYS_CONFIG"
else
    # Добавляем конфигурацию хоткея
    cat >> "$XBINDKEYS_CONFIG" << EOF

# fixMistake - конвертация раскладки клавиатуры
# Ctrl+Alt+→
"$SCRIPT_PATH"
  Control+Alt + Right

EOF
    echo "Хоткей добавлен в $XBINDKEYS_CONFIG"
fi

# Перезапускаем xbindkeys
echo "Перезапуск xbindkeys..."
killall xbindkeys 2>/dev/null || true
sleep 0.5
xbindkeys &>/dev/null &

echo ""
echo "=== Установка завершена! ==="
echo ""
echo "Использование:"
echo "1. Выдели текст, набранный в неправильной раскладке"
echo "2. Нажми Ctrl+Alt+→"
echo "3. Текст автоматически конвертируется!"
echo ""
echo "Примеры:"
echo "  ghbdtn → привет"
echo "  Hello rfr ltkf → Hello как дела"
echo "  руддщ цщкдв → hello world"
echo ""

# Добавляем xbindkeys в автозагрузку если используется GNOME/KDE
if [ -n "$XDG_CURRENT_DESKTOP" ]; then
    AUTOSTART_DIR="$HOME/.config/autostart"
    AUTOSTART_FILE="$AUTOSTART_DIR/xbindkeys.desktop"

    if [ ! -f "$AUTOSTART_FILE" ]; then
        echo "Добавляю xbindkeys в автозагрузку..."
        mkdir -p "$AUTOSTART_DIR"

        cat > "$AUTOSTART_FILE" << 'EOF'
[Desktop Entry]
Type=Application
Name=xbindkeys
Exec=xbindkeys
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Comment=Keyboard shortcuts daemon
EOF
        echo "xbindkeys добавлен в автозагрузку"
    fi
fi

echo "Готово!"