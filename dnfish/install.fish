function install --description 'dnf5 install (with cowsay/cowthink + lolcat)'
    # Проверка зависимостей при первом запуске (обязательно!)
    if not _dnfish_check_dependencies
        return 1
    end

    if test (count $argv) -eq 0
        _say "Использование: install <имя_пакета>" warning
        return 1
    end

    set -l NameArg $argv[1]

    # Проверяем существование пакета ПЕРЕД вопросом
    _think "Проверяю пакет $NameArg..." info

    dnf5 info $NameArg &>/dev/null
    set -l check_status $status

    if test $check_status -ne 0
        _say "Пакет $NameArg не найден в репозиториях!" dead
        return 1
    end

    # Теперь спрашиваем об установке
    _think "Установить $NameArg?"

    while true
        read -l --prompt-str "Ответ [y/N]: " answer
        switch (string lower -- $answer)
            case y yes
                _say "Ставлю $NameArg. Держись крепче!" info
                sudo dnf5 install -y $NameArg
                set -l install_status $status
                if test $install_status -eq 0
                    _say "Готово! $NameArg установлен." success
                else if test $install_status -eq 130
                    _say "Установка прервана (Ctrl+C)." dead
                else
                    _say "Упс… установка $NameArg не удалась (код ошибки: $install_status)." dead
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
