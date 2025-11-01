#!/bin/bash

# Скрипт удаления fixMistake
# Удаляет настройки хоткея и опционально зависимости

set -e

echo "=== Удаление fixMistake ==="
echo ""

XBINDKEYS_CONFIG="$HOME/.xbindkeysrc"
AUTOSTART_FILE="$HOME/.config/autostart/xbindkeys.desktop"

# Удаляем конфигурацию хоткея из xbindkeys
if [ -f "$XBINDKEYS_CONFIG" ]; then
    echo "Удаление хоткея из $XBINDKEYS_CONFIG..."

    # Создаем временный файл без секции fixMistake
    grep -v "fixMistake\|fixmistake.sh\|Control+Alt + Right" "$XBINDKEYS_CONFIG" > "${XBINDKEYS_CONFIG}.tmp" || true

    # Заменяем оригинальный файл
    mv "${XBINDKEYS_CONFIG}.tmp" "$XBINDKEYS_CONFIG"

    echo "Хоткей удален из конфигурации"
else
    echo "Файл конфигурации xbindkeys не найден"
fi

# Перезапускаем xbindkeys
echo "Перезапуск xbindkeys..."
killall xbindkeys 2>/dev/null || true
sleep 0.5

# Проверяем, остались ли другие хоткеи в конфигурации
if [ -f "$XBINDKEYS_CONFIG" ] && grep -q '".*"' "$XBINDKEYS_CONFIG"; then
    # Есть другие хоткеи - перезапускаем xbindkeys
    xbindkeys &>/dev/null &
    echo "xbindkeys перезапущен (остались другие хоткеи)"
else
    # Нет других хоткеев - не запускаем
    echo "xbindkeys остановлен (больше нет хоткеев)"

    # Удаляем из автозагрузки если нет других хоткеев
    if [ -f "$AUTOSTART_FILE" ]; then
        echo "Удаление xbindkeys из автозагрузки..."
        rm -f "$AUTOSTART_FILE"
    fi
fi

echo ""
echo "Удалить зависимости (xdotool, xclip, xbindkeys)?"
echo "ВНИМАНИЕ: Эти пакеты могут использоваться другими приложениями!"
echo "ПРИМЕЧАНИЕ: libnotify не удаляется, так как используется системой (KDE Plasma)"
read -p "Удалить? [y/N]: " remove_deps

if [[ "$remove_deps" =~ ^[Yy]$ ]]; then
    # Определяем пакетный менеджер
    if command -v dnf5 &>/dev/null; then
        PKG_MANAGER="dnf5"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    else
        echo "Ошибка: dnf5/dnf не найден"
        exit 1
    fi

    echo "Удаление пакетов..."
    sudo $PKG_MANAGER remove -y xdotool xclip xbindkeys
    echo "Пакеты удалены"
else
    echo "Зависимости оставлены"
fi

echo ""
echo "=== Удаление завершено ==="
echo ""
echo "fixMistake удален из системы."
echo "Скрипты в $(dirname "$(readlink -f "$0")") можно удалить вручную."
echo ""