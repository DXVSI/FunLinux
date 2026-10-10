# upd: обновление всей системы одной командой.
# Вспомогательные функции __upd_* загружаются вместе с upd из этого файла.

function upd --description 'Обновить систему: dnf, Flatpak, прошивки и пользовательские инструменты'
    argparse h/help l/list y/yes c/clean 'o/only=+' 's/skip=+' -- $argv
    or return 2

    if set -q _flag_help
        __upd_help
        return 0
    end

    set -l known (__upd_sources)
    set -l only (string split , -- $_flag_only | string trim | string match -rv '^$')
    set -l skip (string split , -- $_flag_skip | string trim | string match -rv '^$')
    for name in $only $skip
        if not contains -- $name $known
            __upd_say error "Неизвестный источник «$name». Список источников: upd --list"
            return 2
        end
    end

    if set -q _flag_list
        __upd_list
        return 0
    end

    # Пакеты в аргументах означают точечное обновление через dnf, как раньше
    set -l packages $argv
    if set -q packages[1]
        if set -q only[1]; or set -q skip[1]
            __upd_say error "Пакеты dnf нельзя сочетать с --only и --skip"
            return 2
        end
        set only dnf
    end

    set -l queue
    set -l missing
    for name in $known
        if set -q only[1]; and not contains -- $name $only
            continue
        end
        contains -- $name $skip; and continue

        set -l reason (__upd_check $name)
        if test $status -eq 0
            set -a queue $name
        else if set -q only[1]
            # Явно запрошенный, но недоступный источник попадёт в итог
            set -a missing "$name - $reason"
        end
    end

    if not set -q queue[1]
        if set -q missing[1]
            __upd_summary 0 $missing
        else
            __upd_say warn "Нечего обновлять: подходящие источники не найдены"
        end
        return 1
    end

    __upd_banner $queue

    if contains -- dnf $queue; or contains -- snap $queue
        if not sudo -v
            __upd_say error "Без sudo системные пакеты не обновить"
            return 1
        end
    end

    set -g __upd_reboot
    set -l report
    set -l failed 0
    set -l total (count $queue)
    set -l started (date +%s)

    for index in (seq $total)
        set -l name $queue[$index]
        __upd_step_open $index $total $name

        set -l step_started (date +%s)
        __upd_run $name "$_flag_yes" "$_flag_clean" $packages
        set -l code $status
        set -l elapsed (math (date +%s) - $step_started)

        __upd_step_close $code $elapsed
        set -a report "$name $code $elapsed"

        if test $code -ne 0
            set failed (math $failed + 1)
        else if test $name = dnf; and __upd_dnf_needs_reboot
            set -ga __upd_reboot "ядро или системные библиотеки"
        end
    end

    __upd_summary (math (date +%s) - $started) $report $missing
    set -e __upd_reboot
    test $failed -eq 0
end

function __upd_sources
    # Порядок выполнения: системное, затем пользовательское, прошивки в конце,
    # потому что fwupd может спросить подтверждение
    printf '%s\n' dnf flatpak snap brew uv pipx npm bun rustup cargo gh fisher claude fwupd
end

function __upd_title --argument-names name
    switch $name
        case dnf
            echo 'системные пакеты'
        case flatpak
            echo 'приложения Flatpak'
        case snap
            echo 'пакеты Snap'
        case brew
            echo 'Homebrew'
        case uv
            echo 'инструменты uv'
        case pipx
            echo 'приложения pipx'
        case npm
            echo 'глобальные пакеты npm'
        case bun
            echo 'Bun'
        case rustup
            echo 'тулчейны Rust'
        case cargo
            echo 'программы Cargo'
        case gh
            echo 'расширения GitHub CLI'
        case fisher
            echo 'плагины Fish'
        case claude
            echo 'Claude Code'
        case fwupd
            echo 'прошивки устройств'
    end
end

function __upd_dnf
    command -s dnf5; or command -s dnf
end

function __upd_uv_receipt
    set -l config $XDG_CONFIG_HOME
    test -n "$config"; or set config ~/.config
    echo $config/uv/uv-receipt.json
end

# Печатает причину, если источник недоступен, и возвращает 1
function __upd_check --argument-names name
    switch $name
        case dnf
            __upd_dnf >/dev/null; or __upd_unavailable
        case fwupd
            type -q fwupdmgr; or __upd_unavailable
        case cargo
            type -q cargo-install-update; or __upd_unavailable 'нужен cargo-update'
        case fisher
            functions -q fisher; or __upd_unavailable
        case uv
            type -q uv; or __upd_unavailable; or return
            if not uv tool list 2>/dev/null | string match -rq '\S'
                test -f (__upd_uv_receipt); or __upd_unavailable 'нет инструментов'
            end
        case npm
            type -q npm; or __upd_unavailable; or return
            set -l root (npm root -g 2>/dev/null)
            test -w "$root"; or __upd_unavailable "нет прав на запись в $root"
        case bun
            type -q bun; or __upd_unavailable; or return
            string match -q -- "$HOME/.bun/*" (path resolve (command -s bun))
            or __upd_unavailable 'установлен не через bun.sh'
        case claude
            type -q claude; or __upd_unavailable; or return
            string match -q -- '*/claude/versions/*' (path resolve (command -s claude))
            or __upd_unavailable 'не нативная установка'
        case gh
            type -q gh; or __upd_unavailable; or return
            test -n "$(gh extension list 2>/dev/null)"; or __upd_unavailable 'нет расширений'
        case '*'
            type -q $name; or __upd_unavailable
    end
end

function __upd_unavailable
    set -q argv[1]; and echo $argv; or echo 'не установлен'
    return 1
end

function __upd_run --argument-names name yes clean
    set -l packages $argv[4..-1]

    switch $name
        case dnf
            set -l dnf (__upd_dnf)
            sudo $dnf upgrade --refresh -y $packages; or return
            if test -n "$clean"
                sudo $dnf autoremove -y; or return
            end

        case flatpak
            flatpak update -y; or return
            if test -n "$clean"
                flatpak uninstall --unused -y; or return
            end

        case snap
            sudo snap refresh; or return

        case brew
            brew upgrade; or return
            if test -n "$clean"
                brew cleanup; or return
            end

        case uv
            uv tool upgrade --all; or return
            if test -f (__upd_uv_receipt)
                uv self update; or return
            end

        case pipx
            pipx upgrade-all; or return

        case npm
            # npm update -g не переходит на новую major-версию, а для 0.x даже
            # на новую minor, поэтому ставим latest явно
            set -l lines (npm outdated -g --parseable --depth=0)
            set -l code $status
            if test $code -ne 0; and not set -q lines[1]
                return $code
            end

            set -l latest
            for line in $lines
                set -l spec (string split : -- $line)[4]
                string match -rq '@[0-9][^@]*$' -- $spec; and set -a latest $spec
            end

            if not set -q latest[1]
                __upd_say note 'Все глобальные пакеты уже свежие'
                return 0
            end
            __upd_say note 'Обновляю: '(string join ', ' -- $latest)
            npm install -g $latest; or return

        case bun
            bun upgrade; or return

        case rustup
            rustup update; or return

        case cargo
            cargo install-update -a; or return

        case gh
            gh extension upgrade --all; or return

        case fisher
            fisher update; or return

        case claude
            claude update; or return

        case fwupd
            set -l checks --no-unreported-check --no-remote-check --no-metadata-check

            __upd_say note 'Загружаю метаданные LVFS'
            set -l output (fwupdmgr refresh 2>&1)
            set -l code $status
            # 2 означает «метаданные уже свежие»
            if not contains -- $code 0 2
                printf '%s\n' $output
                return $code
            end

            set output (fwupdmgr get-updates $checks 2>&1)
            set code $status
            if test $code -eq 2
                __upd_say note 'Обновлений прошивок нет'
                return 0
            else if test $code -ne 0
                printf '%s\n' $output
                return $code
            end
            printf '%s\n' $output

            # Перезагрузку не запускаем сами, только сообщаем о ней в итоге
            set -l args --no-reboot-check $checks
            test -n "$yes"; and set -a args --assume-yes
            sudo fwupdmgr update $args; or return
            set -ga __upd_reboot 'прошивки'
    end

    return 0
end

function __upd_dnf_needs_reboot
    set -l dnf (__upd_dnf)
    # Плагин needs-restarting может быть не установлен
    $dnf needs-restarting --help >/dev/null 2>&1; or return 1
    # Код 1 означает, что перезагрузка нужна; -r нужен dnf4, dnf5 его игнорирует
    $dnf -C -q needs-restarting -r >/dev/null 2>&1
    test $status -eq 1
end

# Оформление

function __upd_width
    set -l columns $COLUMNS
    test -n "$columns"; or set columns 80
    math "max(40, min($columns, 72))"
end

function __upd_duration --argument-names seconds
    if test $seconds -ge 3600
        printf '%dч %dм\n' (math "floor($seconds / 3600)") (math "floor($seconds % 3600 / 60)")
    else if test $seconds -ge 60
        printf '%dм %dс\n' (math "floor($seconds / 60)") (math "$seconds % 60")
    else
        printf '%dс\n' $seconds
    end
end

function __upd_badge --argument-names text
    echo
    set_color -o -b cyan black
    printf ' upd '
    set_color normal
    set_color -o
    printf ' %s\n' $text
    set_color normal
end

function __upd_say --argument-names kind
    set -l text $argv[2..-1]
    switch $kind
        case error
            begin
                set_color red
                printf '✗ '
                set_color normal
                echo $text
            end >&2
        case warn
            set_color yellow
            printf '! '
            set_color normal
            echo $text
        case note
            set_color blue
            printf '› '
            set_color normal
            echo $text
    end
end

function __upd_banner
    set -l os
    if test -r /etc/os-release
        set os (string replace -rf '^PRETTY_NAME="?([^"]*)"?$' '$1' </etc/os-release)
    end
    test -n "$os"; or set os (uname -s)

    __upd_badge 'обновление системы'
    set_color brblack
    printf '      %s · ядро %s\n' $os (uname -r)
    printf '      %s\n' (string join ' → ' -- $argv)
    set_color normal
end

function __upd_step_open --argument-names index total name
    set -l title (__upd_title $name)
    set -l head "╭─ $index/$total  "
    set -l used (string length --visible -- "$head$name · $title ")
    set -l fill (math "max(3, "(__upd_width)" - $used)")

    echo
    set_color brblack
    printf '%s' $head
    set_color -o cyan
    printf '%s' $name
    set_color normal
    printf ' · %s ' $title
    set_color brblack
    string repeat -n $fill ─
    set_color normal
end

function __upd_step_close --argument-names code elapsed
    set_color brblack
    printf '╰─ '
    if test $code -eq 0
        set_color green
        printf '✓ готово'
    else
        set_color red
        printf '✗ ошибка, код %s' $code
    end
    set_color brblack
    printf ' · %s\n' (__upd_duration $elapsed)
    set_color normal
end

# Аргументы: общее время, затем записи «имя код время» или «имя - причина»
function __upd_summary --argument-names elapsed
    set -l width (__upd_width)
    set -l ok 0
    set -l failed
    set -l skipped

    echo
    set_color brblack
    printf '━━ '
    set_color -o
    printf 'Итог '
    set_color normal
    set_color brblack
    string repeat -n (math $width - 8) ━
    set_color normal

    for entry in $argv[2..-1]
        set -l parts (string split -m2 ' ' -- $entry)
        set -l name $parts[1]
        set -l code $parts[2]
        set -l detail $parts[3]

        switch $code
            case -
                set -a skipped $name
                set_color brblack
                printf '  ○ '
            case 0
                set ok (math $ok + 1)
                set_color green
                printf '  ✓ '
            case '*'
                set -a failed $name
                set_color red
                printf '  ✗ '
        end

        set_color -o
        printf '%s' (string pad -r -w 8 -- $name)
        set_color normal
        printf ' %s ' (string pad -r -w 22 -- (__upd_title $name))

        switch $code
            case -
                set_color brblack
                printf '%s\n' $detail
            case 0
                set_color brblack
                printf '%s\n' (string pad -w 7 -- (__upd_duration $detail))
            case '*'
                set_color red
                printf '%s · код %s\n' (string pad -w 7 -- (__upd_duration $detail)) $code
        end
        set_color normal
    end

    set_color brblack
    string repeat -n $width ─
    set_color normal

    set -l took (__upd_duration $elapsed)
    if set -q failed[1]
        set_color red
        printf '  ✗ '
        set_color normal
        printf 'Ошибки: %s' (string join ', ' -- $failed)
        set_color brblack
        printf ' · успешно %s из %s · %s\n' $ok (math $ok + (count $failed)) $took
    else if test $ok -gt 0
        set_color green
        printf '  ✓ '
        set_color normal
        set -q skipped[1]; and printf 'Готово'; or printf 'Всё обновлено'
        set_color brblack
        printf ' за %s\n' $took
    end
    if set -q skipped[1]
        set_color brblack
        printf '  ○ Пропущено: %s\n' (string join ', ' -- $skipped)
    end
    if set -q __upd_reboot[1]
        set_color yellow
        printf '  ⟳ Нужна перезагрузка: %s\n' (string join ', ' -- $__upd_reboot)
    end
    set_color normal
end

function __upd_list
    __upd_badge 'источники обновлений'
    echo
    for name in (__upd_sources)
        set -l reason (__upd_check $name)
        if test $status -eq 0
            set_color green
            printf '  ● '
            set_color -o
            printf '%s' (string pad -r -w 8 -- $name)
            set_color normal
            printf ' %s\n' (__upd_title $name)
        else
            set_color brblack
            printf '  ○ %s %s %s\n' (string pad -r -w 8 -- $name) (string pad -r -w 22 -- (__upd_title $name)) $reason
        end
    end
    set_color normal
end

function __upd_help
    __upd_badge 'обновление всей системы одной командой'

    set_color -o
    printf '\n  Использование\n'
    set_color normal
    printf '    %s  %s\n' \
        (string pad -r -w 20 -- 'upd') 'обновить всё, что найдено в системе' \
        (string pad -r -w 20 -- 'upd пакет…') 'обновить только эти пакеты dnf' \
        (string pad -r -w 20 -- 'upd -o flatpak,npm') 'только выбранные источники' \
        (string pad -r -w 20 -- 'upd -s fwupd') 'всё, кроме указанных' \
        (string pad -r -w 20 -- 'upd -c') 'обновить и удалить ненужное'

    set_color -o
    printf '\n  Параметры\n'
    set_color normal
    printf '    %s  %s\n' \
        (string pad -r -w 20 -- '-o, --only СПИСОК') 'только эти источники (через запятую)' \
        (string pad -r -w 20 -- '-s, --skip СПИСОК') 'пропустить источники' \
        (string pad -r -w 20 -- '-y, --yes') 'не спрашивать подтверждение у fwupd' \
        (string pad -r -w 20 -- '-c, --clean') 'dnf autoremove, неиспользуемые Flatpak runtime, brew cleanup' \
        (string pad -r -w 20 -- '-l, --list') 'показать источники и их состояние' \
        (string pad -r -w 20 -- '-h, --help') 'эта справка'

    set_color -o
    printf '\n  Источники'
    set_color normal
    set_color brblack
    printf ' (в порядке выполнения)\n'
    set_color normal
    printf '    %s\n' (string join ' ' -- (__upd_sources))
end
