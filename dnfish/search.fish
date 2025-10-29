function search --description 'dnf5 search (with cowsay/cowthink + lolcat)'
    # Проверка зависимостей при первом запуске
    if not _dnfish_check_dependencies
        return 1
    end

    if test (count $argv) -eq 0
        _say "Использование: search <поисковый_запрос>" warning
        return 1
    end

    set -l SearchQuery $argv

    _think "Ищу пакеты по запросу: $SearchQuery" info

    # Выполняем поиск без sudo
    dnf5 search $SearchQuery
    set -l search_status $status

    if test $search_status -eq 0
        _say "Поиск завершён! Найдены пакеты выше." success
    else if test $search_status -eq 130
        _say "Поиск прерван (Ctrl+C)." dead
    else
        _say "Упс… поиск не дал результатов или произошла ошибка." dead
    end
end
