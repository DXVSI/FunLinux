function remove --description 'dnf5 remove (with cowsay/cowthink + lolcat)'
    # Проверка зависимостей при первом запуске (обязательно!)
    if not _dnfish_check_dependencies
        return 1
    end

    if test (count $argv) -eq 0
        _say "Использование: remove <имя_пакета>" warning
        return 1
    end

    set -l NameArg $argv[1]

    # Проверяем установлен ли пакет ПЕРЕД вопросом
    _think "Проверяю установлен ли $NameArg..." info

    rpm -q $NameArg &>/dev/null
    set -l check_status $status

    if test $check_status -ne 0
        _say "Пакет $NameArg не установлен!" dead
        return 1
    end

    # Теперь спрашиваем об удалении
    _think "Удалить $NameArg?" warning

    while true
        read -l --prompt-str "Ответ [y/N]: " answer
        switch (string lower -- $answer)
            case y yes
                _say "Удаляю $NameArg. Прощай!" warning
                sudo dnf5 remove -y $NameArg
                set -l remove_status $status
                if test $remove_status -eq 0
                    _say "Готово! $NameArg удалён." success
                else if test $remove_status -eq 130
                    _say "Удаление прервано (Ctrl+C)." dead
                else
                    _say "Упс… удаление $NameArg не удалось (код ошибки: $remove_status)." dead
                end
                break
            case '' n no
                _say "Ок, отменяем удаление." info
                break
            case '*'
                _say "Пожалуйста, ответь: y (да) или n (нет)." warning
        end
    end
end
