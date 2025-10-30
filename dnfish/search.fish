function search --description 'dnf5 search (with cowsay/cowthink + lolcat + fzf)'
    # Проверка зависимостей при первом запуске (обязательно!)
    if not _dnfish_check_dependencies
        return 1
    end

    if test (count $argv) -eq 0
        _say "Использование: search <поисковый_запрос>" warning
        return 1
    end

    set -l SearchQuery $argv

    _think "Ищу пакеты по запросу: $SearchQuery" info

    # Проверяем наличие fzf
    if not type -q fzf
        # Fallback без fzf - просто показываем обычный поиск
        dnf5 search $SearchQuery
        return 0
    end

    # Выполняем поиск напрямую в pipe к fzf (избегаем переполнения буфера)
    set -l selected (dnf5 search $SearchQuery 2>/dev/null | \
        grep -E '^\s+\S+\.\S+\s+' | \
        fzf --height=40% \
            --border \
            --header="Выбери пакет для установки (Ctrl+C для отмены)" \
            --preview='echo {} | awk "{print \$1}" | xargs -I{} dnf5 info {} 2>/dev/null' \
            --preview-window=right:60%)

    if test -z "$selected"
        _say "Поиск отменён." warning
        return 0
    end

    # Извлекаем имя пакета (первая колонка)
    set -l package_name (echo $selected | awk '{print $1}')

    # Убираем архитектуру если есть (например htop.x86_64 -> htop)
    set package_name (string replace -r '\.[^.]+$' '' $package_name)

    _say "Выбран пакет: $package_name" success
    echo ""

    # Спрашиваем установить ли
    _think "Установить $package_name?"

    while true
        read -l --prompt-str "Ответ [y/N]: " answer
        switch (string lower -- $answer)
            case y yes
                # Вызываем функцию install
                install $package_name
                break
            case '' n no
                _say "Ок, отменяем." warning
                break
            case '*'
                _say "Пожалуйста, ответь: y (да) или n (нет)." warning
        end
    end
end