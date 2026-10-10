#!/usr/bin/env bash

# Удаление fixMistake: сочетание KDE, служба ydotoold и скрипт в ~/.local/bin.
# Пакеты (ydotool, wl-clipboard, libnotify) не удаляются: их используют и другие программы.

set -uo pipefail

BIN_PATH=$HOME/.local/bin/fixmistake
UNIT_NAME=fixmistake-ydotoold.service
UNIT_PATH=$HOME/.config/systemd/user/$UNIT_NAME
DESKTOP_ID=net.local.fixmistake.desktop
DESKTOP_PATH=$HOME/.local/share/applications/$DESKTOP_ID

if [[ -t 1 ]]; then
    REVERSE=$'\e[7m' BOLD=$'\e[1m' GREEN=$'\e[32m' DIM=$'\e[2m' CYAN=$'\e[36m' RESET=$'\e[0m'
else
    REVERSE='' BOLD='' GREEN='' DIM='' CYAN='' RESET=''
fi

step() { printf '\n%s▸ %s%s\n' "$CYAN$BOLD" "$1" "$RESET"; }
ok() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
skip() { printf '  %s○ %s%s\n' "$DIM" "$1" "$RESET"; }

printf '\n%s fixMistake %s %sудаление%s\n' "$BOLD$REVERSE" "$RESET" "$BOLD" "$RESET"

step 'Сочетание клавиш'
if command -v gdbus >/dev/null 2>&1 &&
    gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
        --method org.kde.KGlobalAccel.unregister "$DESKTOP_ID" _launch 2>/dev/null | grep -q true; then
    gdbus call --session --dest org.kde.kglobalaccel \
        --object-path /component/net_local_fixmistake_desktop \
        --method org.kde.kglobalaccel.Component.cleanUp >/dev/null 2>&1
    ok 'снято в KDE'
else
    skip 'в KDE не зарегистрировано'
fi
if [[ -f $DESKTOP_PATH ]]; then
    rm -f "$DESKTOP_PATH"
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1
    ok "удалён $DESKTOP_PATH"
fi

step 'Служба ydotoold'
if [[ -f $UNIT_PATH ]]; then
    systemctl --user disable --now "$UNIT_NAME" >/dev/null 2>&1
    rm -f "$UNIT_PATH"
    systemctl --user daemon-reload
    ok "$UNIT_NAME остановлена и удалена"
else
    skip 'не установлена'
fi

step 'Скрипт'
if [[ -f $BIN_PATH ]]; then
    rm -f "$BIN_PATH"
    ok "удалён $BIN_PATH"
else
    skip 'не установлен'
fi

printf '\n%sfixMistake удалён.%s Пакеты ydotool, wl-clipboard и libnotify оставлены.\n\n' "$GREEN$BOLD" "$RESET"
