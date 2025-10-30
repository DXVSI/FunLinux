function _fancy --description 'pipe to lolcat if available with color modes'
    set -l mode "$argv[1]"

    if type -q lolcat
        switch $mode
            case error dead
                # Ярко-красный цвет для ошибок
                lolcat -g ff4444:ff6666 -h 0.3
            case success
                # Зелёный градиент для успеха
                lolcat -g 00ff00:00aa00 -h 0.15
            case warning think
                # Жёлто-оранжевый для размышлений
                lolcat -g ffff00:ff8800 -h 0.2
            case info
                # Голубой градиент для информации
                lolcat -g 00ffff:0099ff -h 0.18
            case random
                # Случайные цвета для веселья
                lolcat -r
            case '*'
                # Обычная радуга по умолчанию
                lolcat -h 0.23 -v 0.1
        end
    else
        command cat
    end
end
