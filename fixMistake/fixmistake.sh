#!/usr/bin/env bash

# fixMistake: исправляет текст, набранный не в той раскладке (EN <-> RU).
# Вызывается горячей клавишей (по умолчанию Ctrl+Alt+→), работает в Wayland.
#
#   fixmistake            исправить выделенный текст в активном окне
#   fixmistake --convert  конвертировать stdin в stdout (для проверки и скриптов)
#   fixmistake --check    проверить зависимости и ydotoold

set -uo pipefail
export LC_ALL=C.UTF-8

readonly APP=fixMistake
readonly RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$UID}
readonly YDOTOOL_UNIT=fixmistake-ydotoold.service
export YDOTOOL_SOCKET=${FIXMISTAKE_YDOTOOL_SOCKET:-$RUNTIME_DIR/fixmistake-ydotool.socket}

# Сколько ждать, пока приложение отдаст выделенный текст после Ctrl+C
readonly COPY_TIMEOUT_MS=800
# Сколько ждать после Ctrl+V, прежде чем вернуть старый буфер обмена
readonly PASTE_SETTLE_MS=350

# Символы на одних и тех же клавишах в раскладках us и ru (ЙЦУКЕН).
# Строки выровнены посимвольно: i-й символ EN_KEYS стоит на той же клавише, что и i-й RU_KEYS.
readonly EN_KEYS="qwertyuiop[]asdfghjkl;'zxcvbnm,./\`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~@#\$^&|"
readonly RU_KEYS='йцукенгшщзхъфывапролджэячсмитьбю.ёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё"№;:?/'

# evdev-коды для ydotool
readonly KEY_LEFTCTRL=29 KEY_C=46 KEY_V=47

notify() {
    local message=$1 urgency=${2:-normal}
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "$APP" -i input-keyboard -u "$urgency" "$APP" "$message"
    fi
}

# Шаги пишутся в stderr: при запуске из KDE он попадает в журнал
# (journalctl --user -u 'app-net.local.fixmistake@*'). Сам текст не логируется.
log() {
    printf '%s\n' "$*" >&2
}

fail() {
    log "ошибка: $1"
    notify "$1" critical
    exit 1
}

sleep_ms() {
    sleep "$(printf '%d.%03d' $(($1 / 1000)) $(($1 % 1000)))"
}

# Конвертация

# Переводит одно слово по карте; результат в REPLY
map_word() {
    local word=$1 from=$2 to=$3 out='' ch prefix i
    for ((i = 0; i < ${#word}; i++)); do
        ch=${word:i:1}
        prefix=${from%%"$ch"*}
        if ((${#prefix} < ${#from})); then
            out+=${to:${#prefix}:1}
        else
            out+=$ch
        fi
    done
    REPLY=$out
}

# Направление выбирается по преобладающему алфавиту. Слова, в которых уже есть
# буквы целевого алфавита, не трогаются, чтобы не портить правильно набранное.
# Результат в REPLY, в CONVERTED_TO целевая раскладка: ru, en или пусто.
convert_text() {
    local text=$1 latin cyrillic from to keep rest out='' space word
    latin=${text//[^A-Za-z]/}
    cyrillic=${text//[^А-Яа-яЁё]/}

    CONVERTED_TO=''
    if ((${#latin} == 0 && ${#cyrillic} == 0)); then
        REPLY=$text
        return
    fi

    if ((${#latin} > ${#cyrillic})); then
        from=$EN_KEYS to=$RU_KEYS keep='*[А-Яа-яЁё]*' CONVERTED_TO=ru
    else
        from=$RU_KEYS to=$EN_KEYS keep='*[A-Za-z]*' CONVERTED_TO=en
    fi

    rest=$text
    while [[ -n $rest ]]; do
        space=${rest%%[![:space:]]*}
        rest=${rest#"$space"}
        word=${rest%%[[:space:]]*}
        rest=${rest#"$word"}
        out+=$space
        # shellcheck disable=SC2053 # keep намеренно используется как шаблон
        if [[ -z $word ]]; then
            continue
        elif [[ $word == $keep ]]; then
            out+=$word
        else
            map_word "$word" "$from" "$to"
            out+=$REPLY
        fi
    done
    REPLY=$out
}

# Буфер обмена (Wayland, wl-clipboard)

# Читает буфер без потери завершающих переводов строки; результат в REPLY
clip_read() {
    local data
    data=$(wl-paste --no-newline 2>/dev/null; printf x)
    REPLY=${data%x}
}

# wl-copy остаётся в фоне владельцем буфера. Без закрытия LOCK_FD он унаследует
# блокировку и будет держать её, пока буфер не сменится, а следующие запуски пропустятся.
wl_copy() {
    if [[ -n ${LOCK_FD:-} ]]; then
        wl-copy "$@" {LOCK_FD}>&-
    else
        wl-copy "$@"
    fi
}

clip_write() {
    printf '%s' "$1" | wl_copy --type 'text/plain;charset=utf-8'
}

# Ждёт, пока буфер станет равен (mode=equal) или перестанет быть равен (mode=differ) значению
clip_wait() {
    local mode=$1 value=$2 timeout_ms=$3 waited=0
    while ((waited <= timeout_ms)); do
        clip_read
        if [[ $mode == equal && $REPLY == "$value" ]] || [[ $mode == differ && $REPLY != "$value" ]]; then
            return 0
        fi
        sleep_ms 25
        waited=$((waited + 25))
    done
    return 1
}

# Сохраняет содержимое буфера любого типа (текст, картинка) в каталог
clip_save() {
    local dir=$1 types type='' candidate
    types=$(wl-paste --list-types 2>/dev/null) || return 0
    for candidate in 'image/png' 'text/plain;charset=utf-8' 'text/plain'; do
        if grep -Fxq -- "$candidate" <<<"$types"; then
            type=$candidate
            break
        fi
    done
    [[ -n $type ]] || type=$(head -n1 <<<"$types")
    [[ -n $type ]] || return 0
    wl-paste --no-newline --type "$type" >"$dir/clipboard" 2>/dev/null || return 0
    printf '%s' "$type" >"$dir/clipboard.type"
}

clip_restore() {
    local dir=$1
    if [[ -f $dir/clipboard.type ]]; then
        wl_copy --type "$(<"$dir/clipboard.type")" <"$dir/clipboard"
    else
        wl_copy --clear
    fi
}

# Ввод клавиш (ydotool)

ydotool_ready() {
    ydotool key 0 >/dev/null 2>&1
}

ensure_ydotool() {
    ydotool_ready && return 0

    systemctl --user start "$YDOTOOL_UNIT" >/dev/null 2>&1 || return 1
    local waited=0
    while ((waited < 2000)); do
        if ydotool_ready; then
            # Даём композитору заметить новое виртуальное устройство
            sleep_ms 300
            return 0
        fi
        sleep_ms 50
        waited=$((waited + 50))
    done
    return 1
}

press_ctrl() {
    ydotool key "$KEY_LEFTCTRL:1" "$1:1" "$1:0" "$KEY_LEFTCTRL:0" >/dev/null
}

# Горячая клавиша срабатывает по нажатию, и Ctrl+Alt ещё удерживаются.
# Если сразу отправить Ctrl+C, приложение получит Ctrl+Alt+C, поэтому ждём,
# пока пользователь отпустит модификаторы. Состояние клавиш читается из evdev
# (нужна группа input); если устройства недоступны, просто ждём фиксированное время.
wait_modifiers_released() {
    command -v python3 >/dev/null 2>&1 || {
        sleep_ms 400
        return
    }
    python3 -I - <<'PY' || sleep_ms 400
import fcntl, os, re, sys, time

MODIFIERS = (29, 97, 42, 54, 56, 100, 125, 126)  # Ctrl, Shift, Alt, Meta: левые и правые
EVIOCGKEY = (2 << 30) | (96 << 16) | (ord('E') << 8) | 0x18

with open('/proc/bus/input/devices') as devices:
    handlers = re.findall(r'^H: Handlers=(.*)$', devices.read(), re.M)
paths = ['/dev/input/' + name for line in handlers if 'kbd' in line.split()
         for name in line.split() if name.startswith('event')]

fds = []
for path in paths:
    try:
        fds.append(os.open(path, os.O_RDONLY | os.O_NONBLOCK))
    except OSError:
        pass
if not fds:
    sys.exit(1)

def held():
    for fd in fds:
        state = bytearray(96)
        try:
            fcntl.ioctl(fd, EVIOCGKEY, state)
        except OSError:
            continue
        if any(state[key >> 3] >> (key & 7) & 1 for key in MODIFIERS):
            return True
    return False

deadline = time.monotonic() + 3
while held() and time.monotonic() < deadline:
    time.sleep(0.02)
PY
}

# Раскладка (KDE Plasma)

switch_layout() {
    local target=$1 layouts index=0 name
    layouts=$(gdbus call --session --dest org.kde.keyboard --object-path /Layouts \
        --method org.kde.KeyboardLayouts.getLayoutsList 2>/dev/null) || return 0

    # Ответ вида ([('us', '', 'Английская (США)'), ('ru', '', 'Русская')],)
    while IFS= read -r name; do
        if [[ $target == ru && $name == ru ]] || [[ $target == en && $name != ru ]]; then
            gdbus call --session --dest org.kde.keyboard --object-path /Layouts \
                --method org.kde.KeyboardLayouts.setLayout "uint32 $index" >/dev/null 2>&1
            return 0
        fi
        index=$((index + 1))
    done < <(grep -oP "\('\K[^']*(?=', ')" <<<"$layouts")
}

# Режимы

check() {
    local ok=0 tool
    for tool in wl-paste wl-copy ydotool notify-send gdbus python3; do
        if command -v "$tool" >/dev/null 2>&1; then
            printf '  ✓ %s\n' "$tool"
        else
            printf '  ✗ %s не найден\n' "$tool"
            ok=1
        fi
    done
    if [[ -w /dev/uinput ]]; then
        printf '  ✓ доступ к /dev/uinput\n'
    else
        printf '  ✗ нет доступа к /dev/uinput (нужна группа input)\n'
        ok=1
    fi
    if ensure_ydotool; then
        printf '  ✓ ydotoold отвечает: %s\n' "$YDOTOOL_SOCKET"
    else
        printf '  ✗ ydotoold не отвечает: %s\n' "$YDOTOOL_SOCKET"
        ok=1
    fi
    return $ok
}

elapsed_ms() {
    echo $(((${EPOCHREALTIME/./} - STARTED_US) / 1000))
}

fix_selection() {
    STARTED_US=${EPOCHREALTIME/./}
    local tool
    for tool in wl-paste wl-copy ydotool; do
        command -v "$tool" >/dev/null 2>&1 || fail "Не найден $tool. Запустите install.sh"
    done
    [[ -n ${WAYLAND_DISPLAY:-} ]] || fail "Нужна сессия Wayland"

    exec {LOCK_FD}>"$RUNTIME_DIR/fixmistake.lock"
    if ! flock -n "$LOCK_FD"; then
        log 'предыдущий запуск ещё работает, пропуск'
        exit 0
    fi

    ensure_ydotool || fail "ydotoold не запущен. Проверьте: fixmistake --check"
    wait_modifiers_released
    log "модификаторы отпущены: $(elapsed_ms) мс"

    # Глобальная, чтобы trap видел её и после выхода из функции
    tmp=$(mktemp -d "$RUNTIME_DIR/fixmistake.XXXXXX") || fail "Не удалось создать временный каталог"
    trap 'rm -rf "$tmp"' EXIT
    clip_save "$tmp"

    # Метка вместо очистки: Klipper может сразу вернуть в пустой буфер старое значение
    local marker="fixmistake-$$-$RANDOM$RANDOM"
    clip_write "$marker"
    clip_wait equal "$marker" 500 || log 'метка не появилась в буфере обмена'

    press_ctrl "$KEY_C"
    if ! clip_wait differ "$marker" "$COPY_TIMEOUT_MS"; then
        log "после Ctrl+C буфер не изменился за $COPY_TIMEOUT_MS мс: нет выделения или приложение не копирует"
        clip_restore "$tmp"
        notify 'Выделите текст перед нажатием сочетания'
        exit 0
    fi
    local selected=$REPLY
    log "выделение получено: ${#selected} симв., $(elapsed_ms) мс"

    convert_text "$selected"
    local converted=$REPLY
    if [[ $converted == "$selected" ]]; then
        log 'конвертировать нечего'
        clip_restore "$tmp"
        notify 'В выделении нечего исправлять'
        exit 0
    fi

    clip_write "$converted"
    clip_wait equal "$converted" 500 || log 'исправленный текст не появился в буфере обмена'
    press_ctrl "$KEY_V"
    sleep_ms "$PASTE_SETTLE_MS"
    clip_restore "$tmp"

    switch_layout "$CONVERTED_TO"
    log "вставлено (${CONVERTED_TO}), буфер восстановлен: $(elapsed_ms) мс"
}

case ${1:-} in
    '')
        fix_selection
        ;;
    --convert)
        input=$(cat; printf x)
        convert_text "${input%x}"
        printf '%s' "$REPLY"
        ;;
    --check)
        check
        ;;
    -h | --help)
        sed -n '3,9s/^# \{0,1\}//p' "$0"
        ;;
    *)
        printf '%s: неизвестный параметр %s\n' "$APP" "$1" >&2
        exit 2
        ;;
esac
