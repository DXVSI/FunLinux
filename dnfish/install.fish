function install --description 'dnf5 install (with cowsay/cowthink + lolcat)'
    # Проверка зависимостей при первом запуске (обязательно!)
    if not _dnfish_check_dependencies
        return 1
    end

    if test (count $argv) -eq 0
        _say "Использование: install <имя_пакета> [пакет2 пакет3 ...]" warning
        return 1
    end

    set -l packages $argv

    # Проверяем существование пакетов ПЕРЕД вопросом
    if test (count $packages) -eq 1
        _think "Проверяю пакет $packages..." info
    else
        _think "Проверяю пакеты: $packages..." info
    end

    for pkg in $packages
        dnf5 info $pkg &>/dev/null
        if test $status -ne 0
            _say "Пакет $pkg не найден в репозиториях!" dead
            return 1
        end
    end

    # Теперь спрашиваем об установке
    if test (count $packages) -eq 1
        _think "Установить $packages?"
    else
        _think "Установить пакеты: $packages?"
    end

    while true
        read -l --prompt-str "Ответ [y/N]: " answer
        switch (string lower -- $answer)
            case y yes
                _say "Ставлю пакеты. Держись крепче!" info
                sudo dnf5 install -y $packages
                set -l install_status $status
                if test $install_status -eq 0
                    _say "Готово! Пакеты установлены." success
                else if test $install_status -eq 130
                    _say "Установка прервана (Ctrl+C)." dead
                else
                    _say "Упс… установка не удалась (код ошибки: $install_status)." dead
                end
                break
            case '' n no
                _say "Ок, отменяем." warning
                break
            case '*'
                _say "Пожалуйста, ответь: y (да) или n (нет)." warning
        end
    end
end
