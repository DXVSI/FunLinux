# Проверка и установка зависимостей для dnfish
function _dnfish_check_dependencies
    # Флаг для однократной проверки за сессию
    if set -q __dnfish_deps_checked
        return 0
    end

    set -l missing_packages

    # Проверяем необходимые пакеты
    if not type -q cowsay
        set -a missing_packages cowsay
    end

    if not type -q lolcat
        set -a missing_packages lolcat
    end

    if not type -q bat
        set -a missing_packages bat
    end

    if not type -q fzf
        set -a missing_packages fzf
    end

    # Если все пакеты на месте - выходим
    if test (count $missing_packages) -eq 0
        set -g __dnfish_deps_checked 1
        return 0
    end

    # Сообщаем об отсутствующих пакетах (простой вывод без украшений)
    set_color yellow
    echo "⚠ dnfish: Отсутствуют пакеты для полного функционала: $missing_packages"
    set_color normal
    echo ""
    echo "Установить сейчас? [Y/n]"
    read -l response

    if test "$response" = "n" -o "$response" = "N"
        set_color red
        echo "Установка зависимостей отклонена. dnfish не может работать без них."
        set_color normal
        return 1
    end

    # Устанавливаем пакеты
    set_color blue
    echo "Устанавливаю: $missing_packages"
    set_color normal

    # Проверяем dnf5 или dnf (только Fedora)
    set -l install_status 1
    if command -v dnf5 &>/dev/null
        sudo dnf5 install -y $missing_packages
        set install_status $status
    else if command -v dnf &>/dev/null
        sudo dnf install -y $missing_packages
        set install_status $status
    else
        set_color red
        echo "Ошибка: dnf5/dnf не найден! dnfish работает только на Fedora."
        set_color normal
        return 1
    end

    if test $install_status -eq 0
        set_color green
        echo "Пакеты установлены!"
        set_color normal
        set -g __dnfish_deps_checked 1
        return 0
    else
        set_color red
        echo "Ошибка установки пакетов"
        set_color normal
        return 1
    end
end