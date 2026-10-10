#!/usr/bin/env bash

# Установка fixMistake для Fedora с KDE Plasma (Wayland):
# зависимости, копия скрипта в ~/.local/bin, пользовательский ydotoold
# и глобальное сочетание Ctrl+Alt+→ в KDE.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN_PATH=$HOME/.local/bin/fixmistake
UNIT_NAME=fixmistake-ydotoold.service
UNIT_PATH=$HOME/.config/systemd/user/$UNIT_NAME
DESKTOP_ID=net.local.fixmistake.desktop
DESKTOP_PATH=$HOME/.local/share/applications/$DESKTOP_ID
# Qt-код сочетания: Ctrl (0x04000000) | Alt (0x08000000) | Key_Right (0x01000014)
SHORTCUT_CODE=218103828
SHORTCUT_NAME='Ctrl+Alt+→'

if [[ -t 1 ]]; then
    REVERSE=$'\e[7m' BOLD=$'\e[1m' DIM=$'\e[2m' GREEN=$'\e[32m' YELLOW=$'\e[33m' RED=$'\e[31m' CYAN=$'\e[36m' RESET=$'\e[0m'
else
    REVERSE='' BOLD='' DIM='' GREEN='' YELLOW='' RED='' CYAN='' RESET=''
fi

step() { printf '\n%s▸ %s%s\n' "$CYAN$BOLD" "$1" "$RESET"; }
ok() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }
die() {
    printf '  %s✗%s %s\n' "$RED" "$RESET" "$1" >&2
    exit 1
}

kglobalaccel() {
    gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
        --method "org.kde.KGlobalAccel.$1" "${@:2}"
}

printf '\n%s fixMistake %s %sустановка%s\n' "$BOLD$REVERSE" "$RESET" "$BOLD" "$RESET"

step 'Проверка системы'
command -v dnf5 >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1 || die 'Нужна Fedora с dnf'
PKG_MANAGER=$(command -v dnf5 || command -v dnf)
if [[ ${XDG_SESSION_TYPE:-} == wayland || -n ${WAYLAND_DISPLAY:-} ]]; then
    ok 'сессия Wayland'
else
    die 'fixMistake работает только в сессии Wayland'
fi
IS_KDE=0
[[ ${XDG_CURRENT_DESKTOP:-} == *KDE* ]] && IS_KDE=1

step 'Зависимости'
declare -A PACKAGE_FOR=([ydotool]=ydotool [wl-copy]=wl-clipboard [notify-send]=libnotify [python3]=python3 [gdbus]=glib2)
MISSING=()
for tool in ydotool wl-copy notify-send python3 gdbus; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "$tool"
    else
        MISSING+=("${PACKAGE_FOR[$tool]}")
    fi
done
if ((${#MISSING[@]} > 0)); then
    warn "Нужно установить: ${MISSING[*]}"
    read -r -p "  Установить сейчас? [Y/n] " answer
    [[ $answer =~ ^[Nn]$ ]] && die 'Установка отменена'
    sudo "$PKG_MANAGER" install -y "${MISSING[@]}"
    ok 'пакеты установлены'
fi

step 'Доступ к виртуальной клавиатуре'
NEED_RELOGIN=0
if [[ -w /dev/uinput ]]; then
    ok 'есть доступ к /dev/uinput'
else
    warn 'Нет доступа к /dev/uinput: ydotool нужна группа input'
    read -r -p "  Добавить $USER в группу input? [Y/n] " answer
    [[ $answer =~ ^[Nn]$ ]] && die 'Без доступа к /dev/uinput fixMistake не сможет вставлять текст'
    sudo usermod -aG input "$USER"
    NEED_RELOGIN=1
    warn 'Группа добавлена, она начнёт действовать после повторного входа в систему'
fi

step 'Скрипт'
install -Dm755 "$SCRIPT_DIR/fixmistake.sh" "$BIN_PATH"
ok "$BIN_PATH"

step 'Служба ydotoold'
mkdir -p "$(dirname "$UNIT_PATH")"
cat >"$UNIT_PATH" <<'EOF'
[Unit]
Description=ydotoold для fixMistake (виртуальная клавиатура)

[Service]
ExecStart=/usr/bin/ydotoold --socket-path=%t/fixmistake-ydotool.socket --socket-perm=0600 --mouse-off
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
if ((NEED_RELOGIN)); then
    systemctl --user enable "$UNIT_NAME" >/dev/null 2>&1
    warn "$UNIT_NAME включена и запустится после повторного входа"
else
    systemctl --user enable "$UNIT_NAME" >/dev/null 2>&1
    systemctl --user restart "$UNIT_NAME" ||
        die "$UNIT_NAME не запустилась, подробности: journalctl --user -u $UNIT_NAME"
    ok "$UNIT_NAME запущена"
fi

step "Сочетание $SHORTCUT_NAME"
if ((IS_KDE)); then
    mkdir -p "$(dirname "$DESKTOP_PATH")"
    cat >"$DESKTOP_PATH" <<EOF
[Desktop Entry]
Type=Application
Name=fixMistake
Comment=Исправить раскладку выделенного текста
Exec="$BIN_PATH"
Icon=input-keyboard
NoDisplay=true
StartupNotify=false
X-KDE-GlobalAccel-CommandShortcut=true
EOF
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1

    ACTION_ID="['$DESKTOP_ID', '_launch', 'fixMistake', 'Исправить раскладку выделенного текста']"
    OWNERS=$(kglobalaccel globalShortcutsByKey "([$SHORTCUT_CODE],)" '(0,)') ||
        die 'Служба глобальных сочетаний KDE (kglobalaccel) недоступна'
    kglobalaccel doRegister "$ACTION_ID" >/dev/null
    if [[ $OWNERS != '(@a(ssssssaiai) [],)' && $OWNERS != *"$DESKTOP_ID"* ]]; then
        warn "$SHORTCUT_NAME уже занято другим действием:"
        printf '    %s%s%s\n' "$DIM" "$OWNERS" "$RESET"
        warn 'Назначьте своё сочетание: Параметры системы → Комбинации клавиш → fixMistake'
    else
        # setForeignShortcutKeys оставляет действие неактивным, и KWin не реагирует на нажатие.
        # SetPresent (2) делает его активным сразу, NoAutoloading (4) применяет переданные клавиши.
        kglobalaccel setShortcutKeys "$ACTION_ID" "[([$SHORTCUT_CODE, 0, 0, 0],)]" 6 >/dev/null
        ACTIVE=$(gdbus call --session --dest org.kde.kglobalaccel \
            --object-path /component/net_local_fixmistake_desktop \
            --method org.kde.kglobalaccel.Component.isActive 2>/dev/null || true)
        if [[ $(kglobalaccel shortcutKeys "$ACTION_ID") == *"$SHORTCUT_CODE"* && $ACTIVE == '(true,)' ]]; then
            ok "$SHORTCUT_NAME назначено, перезаход не нужен"
        else
            warn 'KDE не принял сочетание. Назначьте его в Параметры системы → Комбинации клавиш → fixMistake'
        fi
    fi
else
    warn "Автоматическая настройка есть только для KDE Plasma."
    warn "Назначьте команду $BIN_PATH на $SHORTCUT_NAME в настройках клавиатуры вашего окружения."
fi

if [[ -f $HOME/.xbindkeysrc ]] && grep -q 'fixmistake.sh' "$HOME/.xbindkeysrc"; then
    warn 'В ~/.xbindkeysrc осталась запись старой X11-версии fixMistake, её можно удалить'
fi

if ((!NEED_RELOGIN)); then
    step 'Проверка'
    "$BIN_PATH" --check || die 'Проверка не прошла, см. вывод выше'
fi

printf '\n%sГотово.%s Выделите текст, набранный не в той раскладке, и нажмите %s.\n' "$GREEN$BOLD" "$RESET" "$SHORTCUT_NAME"
printf '%s  ghbdtn → привет    руддщ → hello    rfr ltkf& → как дела?%s\n\n' "$DIM" "$RESET"
