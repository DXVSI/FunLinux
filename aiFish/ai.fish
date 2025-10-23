# aiFish - AI помощник для Fish Shell
# Все функции объединены для правильной работы

# === ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ===
set -g AIFISH_CONFIG_DIR "$HOME/.config/aiFish"
set -g AIFISH_CONFIG_FILE "$AIFISH_CONFIG_DIR/config.json"
set -g AIFISH_CONTEXT_DIR "$AIFISH_CONFIG_DIR/contexts"
set -g AIFISH_HISTORY_DIR "$AIFISH_CONFIG_DIR/history"
set -g AIFISH_CURRENT_CONTEXT "$AIFISH_CONFIG_DIR/current_context.json"
set -g AIFISH_MODELS_CACHE "$AIFISH_CONFIG_DIR/models_cache.json"

# === DISPLAY FUNCTIONS ===

function _ai_display_fancy
    set -l mode "$argv[1]"
    if type -q lolcat
        switch $mode
            case error dead
                lolcat -g ff4444:ff6666 -h 0.3
            case success
                lolcat -g 00ff00:00aa00 -h 0.15
            case warning
                lolcat -g ffff00:ff8800 -h 0.2
            case info
                lolcat -g 00ffff:0099ff -h 0.18
            case think
                lolcat -g cc99ff:9966ff -h 0.2
            case random
                lolcat -r
            case '*'
                lolcat -h 0.23 -v 0.1
        end
    else
        cat
    end
end

function _ai_display_say
    set -l msg "$argv[1]"
    set -l mode "$argv[2]"
    if type -q cowsay
        switch $mode
            case dead
                echo "$msg" | cowsay -d -n | _ai_display_fancy error
            case success
                echo "$msg" | cowsay -n | _ai_display_fancy success
            case warning
                echo "$msg" | cowsay -n | _ai_display_fancy warning
            case info
                echo "$msg" | cowsay -n | _ai_display_fancy info
            case think
                echo "$msg" | cowsay -n | _ai_display_fancy think
            case random
                echo "$msg" | cowsay -n | _ai_display_fancy random
            case '*'
                echo "$msg" | cowsay -n | _ai_display_fancy
        end
    else
        echo "$msg" | _ai_display_fancy $mode
    end
end

function _ai_display_think
    set -l msg "$argv[1]"
    set -l mode "$argv[2]"
    if type -q cowthink
        echo "$msg" | cowthink -n | _ai_display_fancy think
    else if type -q cowsay
        echo "$msg" | cowsay -n | _ai_display_fancy $mode
    else
        echo "$msg"
    end
end

function _ai_display_error
    _ai_display_say "$argv[1]" dead
end

function _ai_display_success
    _ai_display_say "$argv[1]" success
end

function _ai_display_info
    _ai_display_say "$argv[1]" info
end

function _ai_display_warning
    _ai_display_say "$argv[1]" warning
end

# === CONFIG FUNCTIONS ===

function _ai_config_init
    if not test -d $AIFISH_CONFIG_DIR
        mkdir -p $AIFISH_CONFIG_DIR
        mkdir -p $AIFISH_CONTEXT_DIR
        mkdir -p $AIFISH_HISTORY_DIR
    end

    if not test -f $AIFISH_CONFIG_FILE
        _ai_config_create_default
    end

    if not test -f $AIFISH_CURRENT_CONTEXT
        echo '{"messages":[]}' > $AIFISH_CURRENT_CONTEXT
    end
    return 0
end

function _ai_config_create_default
    echo '{
  "default_model": "gpt-4o-mini",
  "last_used_model": "gpt-4o-mini",
  "max_context_messages": 20,
  "max_tokens": 1000,
  "temperature": 0.7,
  "show_cost": false,
  "auto_save": true,
  "aliases": {
    "fast": "gpt-3.5-turbo",
    "balanced": "gpt-4o-mini",
    "smart": "gpt-4o",
    "genius": "gpt-4.1",
    "think": "o4-mini",
    "ultimate": "gpt-5-mini"
  }
}' | jq '.' > $AIFISH_CONFIG_FILE
    return 0
end

function _ai_config_get
    set -l key $argv[1]
    if not test -f $AIFISH_CONFIG_FILE
        _ai_config_init
    end
    jq -r ".$key // empty" $AIFISH_CONFIG_FILE
end

function _ai_config_set
    set -l key $argv[1]
    set -l value $argv[2]
    if not test -f $AIFISH_CONFIG_FILE
        _ai_config_init
    end
    set -l new_config (jq ".$key = \"$value\"" $AIFISH_CONFIG_FILE)
    echo $new_config | jq '.' > $AIFISH_CONFIG_FILE
    return 0
end

function _ai_check_api_key
    if set -q OPENAI_API_KEY; and test -n "$OPENAI_API_KEY"
        return 0
    end
    return 1
end

function _ai_check_dependencies
    set -l missing_required
    set -l missing_optional

    # Обязательные зависимости
    if not type -q curl
        set -a missing_required "curl"
    end
    if not type -q jq
        set -a missing_required "jq"
    end

    # Опциональные зависимости
    if not python3 -c "import rich" 2>/dev/null
        set -a missing_optional "python3-rich"
    end
    if not type -q cowsay
        set -a missing_optional "cowsay"
    end
    if not type -q lolcat
        set -a missing_optional "lolcat"
    end
    if not type -q fzf
        set -a missing_optional "fzf"
    end

    # Устанавливаем обязательные автоматически
    if test (count $missing_required) -gt 0
        echo "Устанавливаю необходимые зависимости: "(string join ", " $missing_required)
        sudo dnf5 install -y $missing_required
        if test $status -ne 0
            echo "Ошибка установки зависимостей!"
            return 1
        end
    end

    # Предлагаем установить опциональные
    if test (count $missing_optional) -gt 0
        echo ""
        echo "Опциональные пакеты не найдены: "(string join ", " $missing_optional)
        echo "python3-rich - вывод markdown с подсветкой синтаксиса"
        echo "cowsay/lolcat - думающая корова с цветами"
        echo "fzf - выбор моделей стрелочками"
        read -l -P "Установить их для лучшего опыта? [Y/n]: " install_opt

        if test -z "$install_opt" -o "$install_opt" = "y" -o "$install_opt" = "Y"
            sudo dnf5 install -y $missing_optional
        else
            echo "Пропущено. Можешь установить позже: sudo dnf5 install -y "(string join " " $missing_optional)
        end
    end

    return 0
end

# === API FUNCTIONS ===

function _ai_api_call
    set -l model $argv[1]
    set -l messages_json $argv[2]

    if not _ai_check_api_key
        _ai_display_error "API ключ не найден! Установи: set -Ux OPENAI_API_KEY \"sk-...\""
        return 1
    end

    set -l temperature (_ai_config_get "temperature")
    set -l max_tokens (_ai_config_get "max_tokens")
    test -z "$temperature" && set temperature 0.7
    test -z "$max_tokens" && set max_tokens 1000

    set -l request_body (echo '{}' | jq \
        --arg model "$model" \
        --argjson messages "$messages_json" \
        --argjson temperature $temperature \
        --argjson max_tokens $max_tokens \
        '. + {
            "model": $model,
            "messages": $messages,
            "temperature": $temperature,
            "max_tokens": $max_tokens
        }')

    set -l response (curl -s -w "\n\nHTTP_CODE:%{http_code}" --max-time 60 \
        https://api.openai.com/v1/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "$request_body" 2>&1)

    set -l curl_status $status

    # Проверяем ошибки curl
    if test $curl_status -ne 0
        _ai_display_error "Ошибка сети (curl код $curl_status)!
Проверь интернет соединение."
        return 1
    end

    # Извлекаем HTTP код и тело
    set -l http_code
    set -l body

    # HTTP_CODE может быть в конце строки
    if string match -q "*HTTP_CODE:*" -- "$response"
        # Разделяем по HTTP_CODE:
        set -l parts (string split "HTTP_CODE:" -- "$response")
        set body $parts[1]
        # Берем первые 3 цифры из части после HTTP_CODE:
        set http_code (string sub -l 3 -- (string trim -- $parts[2]))
    else
        _ai_display_error "Не удалось получить HTTP код!"
        return 1
    end

    # Проверяем что получили валидный код
    if not string match -qr '^[0-9]+$' -- "$http_code"
        _ai_display_error "Неверный HTTP код: $http_code"
        return 1
    end

    if test "$http_code" = "200"
        # Сохраняем напрямую во временный файл через jq
        set -l tmpfile "/tmp/ai_content_$fish_pid.txt"
        echo "$body" | jq -r '.choices[0].message.content // empty' 2>/dev/null > $tmpfile
        set -l tokens (echo "$body" | jq -r '.usage.total_tokens // 0' 2>/dev/null)

        if not test -s $tmpfile
            _ai_display_error "Пустой ответ от API!
Тело ответа: $body"
            rm -f $tmpfile
            return 1
        end

        # НЕ выводим и НЕ удаляем файл - пусть главная функция сама управляет им
        # Только токены отправляем в stderr
        echo "$tokens" >&2
        return 0
    else
        set -l error_msg (echo "$body" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
        set -l error_type (echo "$body" | jq -r '.error.type // ""' 2>/dev/null)

        if test -z "$error_msg"
            set error_msg "Неизвестная ошибка"
        end

        # Специальная обработка для unsupported model
        if string match -q "*model*" "$error_msg"
            _ai_display_error "Ошибка API (код $http_code): $error_msg

Эта модель не поддерживает chat completions.
Используй: ai setmodel - чтобы выбрать подходящую модель."
        else
            _ai_display_error "Ошибка API (код $http_code): $error_msg"
        end
        return 1
    end
end

function _ai_api_models
    if not _ai_check_api_key
        return 1
    end

    # Проверяем кэш (24 часа)
    if test -f $AIFISH_MODELS_CACHE
        set -l cache_age (math (date +%s) - (stat -c %Y $AIFISH_MODELS_CACHE 2>/dev/null || echo 0))
        if test $cache_age -lt 86400
            command cat $AIFISH_MODELS_CACHE
            return 0
        end
    end

    # Обновляем кэш
    set -l response (curl -s -w "\n\nHTTP_CODE:%{http_code}" \
        https://api.openai.com/v1/models \
        -H "Authorization: Bearer $OPENAI_API_KEY" 2>&1)

    set -l http_code
    set -l body

    if string match -q "*HTTP_CODE:*" -- "$response"
        set -l parts (string split "HTTP_CODE:" -- "$response")
        set body $parts[1]
        set http_code (string sub -l 3 -- (string trim -- $parts[2]))
    else
        return 1
    end

    if test "$http_code" = "200"
        # Фильтруем только модели для chat completions (исключаем embeddings, whisper, tts, и т.д.)
        echo "$body" | jq -r '.data[] |
            select(.id | test("gpt-3.5-turbo|gpt-4|gpt-5|o[0-9]|o1|o3|o4")) |
            select(.id | test("embed|whisper|tts|dall-e|davinci|babbage|ada|curie|transcribe|realtime|search-api|codex|image") | not) |
            .id' | sort > $AIFISH_MODELS_CACHE
        command cat $AIFISH_MODELS_CACHE
        return 0
    else
        return 1
    end
end

# === MODELS FUNCTIONS ===

function _ai_models_resolve_alias
    set -l alias_or_model $argv[1]
    set -l resolved (_ai_config_get "aliases.$alias_or_model")
    if test -n "$resolved"
        echo $resolved
    else
        echo $alias_or_model
    end
end

function _ai_models_get_description
    set -l model $argv[1]

    # Определяем описание и стоимость для известных моделей
    switch $model
        # GPT-3.5
        case "gpt-3.5-turbo*"
            echo "Быстрая и дешевая модель (~\$0.002/1K токенов)"

        # GPT-4o
        case "gpt-4o-mini"
            echo "Эффективная мультимодальная (~\$0.00015/1K токенов)"
        case "gpt-4o"
            echo "Умная мультимодальная (~\$0.005/1K токенов)"
        case "gpt-4o-*"
            echo "Модель семейства GPT-4o"

        # GPT-4.1
        case "gpt-4.1*"
            echo "Самая умная, 1M токенов (~\$0.006/1K токенов)"

        # Reasoning модели
        case "o4-mini"
            echo "Быстрая рассуждающая модель (~\$0.0011/1K токенов)"
        case "o3"
            echo "Продвинутая reasoning модель (~\$0.002/1K токенов)"
        case "o1*"
            echo "Reasoning модель для сложных задач"

        # GPT-5
        case "gpt-5-mini"
            echo "Новейшая эффективная модель (~\$0.008/1K токенов)"
        case "gpt-5"
            echo "Новейшая продвинутая модель (требует регистрацию)"
        case "gpt-5-*"
            echo "Модель семейства GPT-5"

        case '*'
            echo "Модель OpenAI"
    end
end

function _ai_models_list
    set -l verbose false
    if test "$argv[1]" = "--verbose"
        set verbose true
    end

    _ai_display_info "Получаю список доступных моделей..."

    set -l models (_ai_api_models)
    if test $status -ne 0
        _ai_display_error "Не удалось получить список моделей"
        return 1
    end

    echo ""
    echo "Доступные модели:"
    echo ""

    set -l current_model (_ai_config_get "default_model")

    for model in $models
        set -l marker " "
        if test "$model" = "$current_model"
            set marker "→"
        end

        if test "$verbose" = "true"
            set -l desc (_ai_models_get_description "$model")
            printf "%s %-20s  %s\n" $marker $model $desc
        else
            printf "%s %s\n" $marker $model
        end
    end

    echo ""
    echo "Текущая модель: $current_model"

    # Показываем алиасы
    echo ""
    echo "Алиасы:"
    echo "  --fast      → gpt-3.5-turbo  (быстро и дешево)"
    echo "  --balanced  → gpt-4o-mini    (оптимально)"
    echo "  --smart     → gpt-4o         (умная)"
    echo "  --genius    → gpt-4.1        (самая умная)"
    echo "  --think     → o4-mini        (для сложных задач)"
    echo "  --ultimate  → gpt-5-mini     (новейшая)"

    return 0
end

function _ai_models_select_interactive
    set -l models (_ai_api_models)
    if test $status -ne 0
        _ai_display_error "Не удалось получить список моделей"
        return 1
    end

    set -l current_model (_ai_config_get "default_model")

    # Если есть fzf - используем его для выбора стрелочками
    if type -q fzf
        echo "Выбери модель (используй стрелки ↑↓, Enter для выбора, Esc для отмены):" >&2
        echo ""

        # Группируем модели по семействам для красивого отображения
        set -l formatted_list

        # GPT-3.5
        for model in $models
            if string match -q "gpt-3.5*" $model
                set -l marker " "
                if test "$model" = "$current_model"
                    set marker "→"
                end
                set -l desc (_ai_models_get_description "$model")
                set -a formatted_list "$marker $model | $desc"
            end
        end

        # GPT-4o
        for model in $models
            if string match -q "gpt-4o*" $model
                set -l marker " "
                if test "$model" = "$current_model"
                    set marker "→"
                end
                set -l desc (_ai_models_get_description "$model")
                set -a formatted_list "$marker $model | $desc"
            end
        end

        # GPT-4.1
        for model in $models
            if string match -q "gpt-4.1*" $model
                set -l marker " "
                if test "$model" = "$current_model"
                    set marker "→"
                end
                set -l desc (_ai_models_get_description "$model")
                set -a formatted_list "$marker $model | $desc"
            end
        end

        # Reasoning
        for model in $models
            if string match -qr "^o[0-9]" $model
                set -l marker " "
                if test "$model" = "$current_model"
                    set marker "→"
                end
                set -l desc (_ai_models_get_description "$model")
                set -a formatted_list "$marker $model | $desc"
            end
        end

        # GPT-5
        for model in $models
            if string match -q "gpt-5*" $model
                set -l marker " "
                if test "$model" = "$current_model"
                    set marker "→"
                end
                set -l desc (_ai_models_get_description "$model")
                set -a formatted_list "$marker $model | $desc"
            end
        end

        # Другие
        for model in $models
            if not string match -q "gpt-*" $model; and not string match -qr "^o[0-9]" $model
                set -l marker " "
                if test "$model" = "$current_model"
                    set marker "→"
                end
                set -l desc (_ai_models_get_description "$model")
                set -a formatted_list "$marker $model | $desc"
            end
        end

        # Выбор через fzf
        set -l selected (printf "%s\n" $formatted_list | fzf --height=50% --reverse --border --prompt="Модель: " --pointer="▶" --marker="✓")

        if test -z "$selected"
            echo "Отменено"
            return 0
        end

        # Извлекаем название модели (между маркером и |)
        set -l selected_model (echo "$selected" | string trim | string replace -r '^[→ ]+' '' | string replace -r ' \|.*$' '')

        _ai_config_set "default_model" "$selected_model"
        _ai_display_success "Модель изменена на: $selected_model"
        return 0
    end

    # Fallback на выбор по номеру если нет fzf
    _ai_display_info "Интерактивный выбор модели (установи fzf для выбора стрелочками)"

    echo ""

    # Группируем модели по семействам
    set -l gpt35_models
    set -l gpt4o_models
    set -l gpt41_models
    set -l reasoning_models
    set -l gpt5_models
    set -l other_models

    for model in $models
        if string match -q "gpt-3.5*" $model
            set -a gpt35_models $model
        else if string match -q "gpt-4o*" $model
            set -a gpt4o_models $model
        else if string match -q "gpt-4.1*" $model
            set -a gpt41_models $model
        else if string match -qr "^o[0-9]" $model
            set -a reasoning_models $model
        else if string match -q "gpt-5*" $model
            set -a gpt5_models $model
        else
            set -a other_models $model
        end
    end

    # Создаем меню
    set -l menu_models

    if test (count $gpt35_models) -gt 0
        echo "GPT-3.5 (быстро и дешево):"
        for model in $gpt35_models
            set -l marker " "
            if test "$model" = "$current_model"
                set marker "→"
            end
            set -a menu_models $model
            printf "  %2d%s %s\n" (count $menu_models) $marker $model
        end
        echo ""
    end

    if test (count $gpt4o_models) -gt 0
        echo "GPT-4o (рекомендуется):"
        for model in $gpt4o_models
            set -l marker " "
            if test "$model" = "$current_model"
                set marker "→"
            end
            set -a menu_models $model
            printf "  %2d%s %s\n" (count $menu_models) $marker $model
        end
        echo ""
    end

    if test (count $gpt41_models) -gt 0
        echo "GPT-4.1 (самая умная):"
        for model in $gpt41_models
            set -l marker " "
            if test "$model" = "$current_model"
                set marker "→"
            end
            set -a menu_models $model
            printf "  %2d%s %s\n" (count $menu_models) $marker $model
        end
        echo ""
    end

    if test (count $reasoning_models) -gt 0
        echo "Reasoning модели (для сложных задач):"
        for model in $reasoning_models
            set -l marker " "
            if test "$model" = "$current_model"
                set marker "→"
            end
            set -a menu_models $model
            printf "  %2d%s %s\n" (count $menu_models) $marker $model
        end
        echo ""
    end

    if test (count $gpt5_models) -gt 0
        echo "GPT-5 (новейшая):"
        for model in $gpt5_models
            set -l marker " "
            if test "$model" = "$current_model"
                set marker "→"
            end
            set -a menu_models $model
            printf "  %2d%s %s\n" (count $menu_models) $marker $model
        end
        echo ""
    end

    if test (count $other_models) -gt 0
        echo "Другие модели:"
        for model in $other_models
            set -l marker " "
            if test "$model" = "$current_model"
                set marker "→"
            end
            set -a menu_models $model
            printf "  %2d%s %s\n" (count $menu_models) $marker $model
        end
        echo ""
    end

    # Запрашиваем выбор
    read -l -P "Выбери номер модели (Enter - оставить текущую): " choice

    if test -z "$choice"
        echo "Модель не изменена"
        return 0
    end

    if not string match -qr '^[0-9]+$' -- "$choice"
        _ai_display_error "Неверный выбор"
        return 1
    end

    if test "$choice" -lt 1 -o "$choice" -gt (count $menu_models)
        _ai_display_error "Номер вне диапазона"
        return 1
    end

    set -l selected_model $menu_models[$choice]
    _ai_config_set "default_model" "$selected_model"
    _ai_display_success "Модель изменена на: $selected_model"

    return 0
end

function _ai_models_set
    set -l model $argv[1]

    if test -z "$model"
        _ai_display_error "Укажи название модели"
        return 1
    end

    # Резолвим алиас
    set -l resolved_model (_ai_models_resolve_alias "$model")

    _ai_config_set "default_model" "$resolved_model"
    _ai_display_success "Модель по умолчанию установлена: $resolved_model"

    return 0
end

function _ai_models_show_current
    set -l model (_ai_config_get "default_model")
    set -l desc (_ai_models_get_description "$model")

    echo ""
    echo "Текущая модель: $model"
    echo "Описание: $desc"
    echo ""

    return 0
end

function _ai_models_refresh_cache
    if test -f $AIFISH_MODELS_CACHE
        rm -f $AIFISH_MODELS_CACHE
    end

    _ai_display_info "Обновляю кэш моделей..."

    _ai_api_models > /dev/null
    if test $status -eq 0
        _ai_display_success "Кэш моделей обновлен"
        return 0
    else
        _ai_display_error "Не удалось обновить кэш"
        return 1
    end
end

# === CONTEXT FUNCTIONS ===

function _ai_context_init
    echo '{"messages":[],"stats":{"total_tokens":0,"messages_count":0}}' > $AIFISH_CURRENT_CONTEXT
    return 0
end

function _ai_context_get_messages
    if not test -f $AIFISH_CURRENT_CONTEXT
        echo '[]'
        return 0
    end

    # Проверяем что файл не пустой
    if not test -s $AIFISH_CURRENT_CONTEXT
        _ai_context_init
    end

    set -l messages (command cat $AIFISH_CURRENT_CONTEXT | jq -c '.messages // []' 2>/dev/null)
    if test -z "$messages"
        echo '[]'
    else
        echo $messages
    end
end

function _ai_context_add_message
    set -l role $argv[1]
    set -l content_or_file $argv[2]
    set -l tokens $argv[3]
    test -z "$tokens" && set tokens 0

    if not test -f $AIFISH_CURRENT_CONTEXT
        _ai_context_init
    end

    # Проверяем что файл не пустой и валидный
    if not test -s $AIFISH_CURRENT_CONTEXT
        _ai_context_init
    end

    # Если это файл - читаем из него, иначе используем как текст
    set -l content
    if test -f "$content_or_file"
        set content (jq -Rs '.' < "$content_or_file")
    else
        set content (echo "$content_or_file" | jq -Rs '.')
    end

    set -l current_content (command cat $AIFISH_CURRENT_CONTEXT)
    set -l updated_context (echo "$current_content" | jq \
        --argjson content "$content" \
        --arg role "$role" \
        --argjson tokens "$tokens" \
        '.messages += [{"role": $role, "content": $content, "tokens": $tokens}] |
         .stats.messages_count = (.messages | length) |
         .stats.total_tokens += $tokens')

    echo "$updated_context" > $AIFISH_CURRENT_CONTEXT

    # Trim if needed
    set -l max_messages (_ai_config_get "max_context_messages")
    test -z "$max_messages" && set max_messages 20
    set -l count (command cat $AIFISH_CURRENT_CONTEXT | jq '.messages | length')
    if test -n "$count" -a "$count" -gt "$max_messages"
        set -l trimmed (command cat $AIFISH_CURRENT_CONTEXT | jq \
            --argjson max $max_messages \
            '.messages = (.messages | .[-$max:])')
        echo $trimmed | jq '.' > $AIFISH_CURRENT_CONTEXT
    end

    return 0
end

function _ai_context_clear
    _ai_context_init
    _ai_display_success "Контекст очищен"
end

# === MAIN FUNCTION ===

function ai --description 'AI assistant for Fish Shell'
    # Инициализация
    _ai_config_init

    # Простой парсинг аргументов
    set -l query
    set -l model_choice
    set -l flag_new false
    set -l flag_raw false
    set -l flag_clear false
    set -l flag_help false
    set -l flag_setup false
    set -l flag_models false
    set -l flag_models_verbose false
    set -l flag_select false
    set -l flag_set_model false
    set -l set_model_value
    set -l flag_current_model false
    set -l flag_refresh_models false

    # Парсим аргументы
    set -l i 1
    while test $i -le (count $argv)
        set -l arg $argv[$i]
        switch $arg
            case --help -h help
                set flag_help true
            case --setup setup
                set flag_setup true
            case --new
                set flag_new true
            case --raw
                set flag_raw true
            case --clear clear
                set flag_clear true
            case --models models
                set flag_models true
            case --verbose
                set flag_models_verbose true
            case --select select setmodel
                set flag_select true
            case --set-model
                set flag_set_model true
                set i (math $i + 1)
                if test $i -le (count $argv)
                    set set_model_value $argv[$i]
                end
            case --current-model current
                set flag_current_model true
            case --refresh-models refresh
                set flag_refresh_models true
            case --fast
                set model_choice "fast"
            case --balanced
                set model_choice "balanced"
            case --smart
                set model_choice "smart"
            case --genius
                set model_choice "genius"
            case --think
                set model_choice "think"
            case --ultimate
                set model_choice "ultimate"
            case --model
                set i (math $i + 1)
                set model_choice $argv[$i]
            case '*'
                set query $query $arg
        end
        set i (math $i + 1)
    end

    # Обработка флагов без запроса
    if test "$flag_help" = "true"
        echo "aiFish - AI помощник для Fish Shell"
        echo ""
        echo "Использование:"
        echo "  ai \"вопрос\"                  Простой запрос"
        echo "  ai --new \"вопрос\"            Новый диалог"
        echo "  ai --raw \"вопрос\"            Без cowsay (для скриптов)"
        echo ""
        echo "Работа с моделями:"
        echo "  ai --setmodel                 Выбор модели (стрелочками)"
        echo "  ai --models                   Список всех моделей"
        echo "  ai --current                  Показать текущую модель"
        echo ""
        echo "Управление контекстом:"
        echo "  ai --clear                    Очистить контекст"
        echo ""
        echo "Настройка:"
        echo "  ai --setup                    Мастер настройки"
        echo "  ai --help                     Эта справка"
        return 0
    end

    # Флаги работы с моделями
    if test "$flag_models" = "true"
        if test "$flag_models_verbose" = "true"
            _ai_models_list --verbose
        else
            _ai_models_list
        end
        return 0
    end

    if test "$flag_select" = "true"
        _ai_models_select_interactive
        return 0
    end

    if test "$flag_set_model" = "true"
        _ai_models_set "$set_model_value"
        return 0
    end

    if test "$flag_current_model" = "true"
        _ai_models_show_current
        return 0
    end

    if test "$flag_refresh_models" = "true"
        _ai_models_refresh_cache
        return 0
    end

    if test "$flag_setup" = "true"
        _ai_display_info "Мастер настройки aiFish"
        echo ""
        if not _ai_check_dependencies
            return 1
        end
        if _ai_check_api_key
            _ai_display_success "API ключ найден"
        else
            echo "Получи API ключ на: https://platform.openai.com/api-keys"
            read -P "Введи API ключ (sk-...): " api_key
            if test -n "$api_key"
                set -Ux OPENAI_API_KEY "$api_key"
                _ai_display_success "API ключ установлен"
            else
                _ai_display_error "API ключ не введен"
                return 1
            end
        end
        _ai_display_success "Настройка завершена! Используй: ai \"твой вопрос\""
        return 0
    end

    if test "$flag_clear" = "true"
        _ai_context_clear
        return 0
    end

    # Проверки
    if not _ai_check_dependencies
        return 1
    end

    if not _ai_check_api_key
        _ai_display_error "API ключ не установлен! Используй: ai --setup"
        return 1
    end

    # Получаем запрос
    if test (count $query) -gt 0
        set query (string join " " -- $query)
    else if not isatty stdin
        set query (cat)
    else
        _ai_display_error "Укажи запрос! Используй: ai \"вопрос\""
        return 1
    end

    if test -z "$query"
        _ai_display_error "Запрос пуст!"
        return 1
    end

    # Определяем модель
    set -l model (_ai_config_get "default_model")
    if test -n "$model_choice"
        set model (_ai_models_resolve_alias "$model_choice")
    end

    # Очищаем контекст если нужно
    if test "$flag_new" = "true"
        _ai_context_clear
    end

    # Показываем модель
    if test "$flag_raw" != "true"
        if type -q lolcat
            echo "→ Использую модель: $model" | lolcat
        else
            echo "→ Использую модель: $model"
        end
        echo ""
    end

    # Добавляем запрос в контекст
    _ai_context_add_message "user" "$query"

    # Получаем сообщения
    set -l messages (_ai_context_get_messages)

    # Показываем что корова думает (если не raw режим)
    if test "$flag_raw" != "true"
        if type -q cowthink
            echo "Думаю над вопросом..." | cowthink -n | _ai_display_fancy think
        else
            echo "⏳ Думаю над вопросом..."
        end
        echo ""
    end

    # Делаем запрос (stdout=content, stderr=tokens)
    # Контент теперь сохраняется в файл напрямую, поэтому перенаправляем в переменную
    set -l content_file "/tmp/ai_content_$fish_pid.txt"
    _ai_api_call "$model" "$messages" 2>/tmp/ai_tokens_$fish_pid
    set -l api_status $status

    if test $api_status -ne 0
        rm -f /tmp/ai_tokens_$fish_pid
        rm -f $content_file
        return 1
    end

    # Проверяем что файл создан
    if not test -s $content_file
        _ai_display_error "Получен пустой ответ!"
        rm -f /tmp/ai_tokens_$fish_pid
        rm -f $content_file
        return 1
    end

    # Читаем токены из временного файла
    set -l tokens 0
    if test -f /tmp/ai_tokens_$fish_pid
        set tokens (command cat /tmp/ai_tokens_$fish_pid)
        rm -f /tmp/ai_tokens_$fish_pid
    end

    # Добавляем ответ в контекст ПЕРЕД выводом - передаём путь к файлу
    _ai_context_add_message "assistant" "$content_file" "$tokens"

    # Выводим ответ
    if test "$flag_raw" = "true"
        command cat $content_file
    else
        # Выводим с подсветкой markdown
        if python3 -c "import rich" 2>/dev/null
            # python3-rich для рендеринга markdown (без пейджера!)
            python3 -m rich.markdown $content_file
        else if type -q glow
            # glow без пейджера
            glow -s dark -w 120 $content_file
        else
            # Простой вывод если ничего нет
            command cat $content_file
        end
    end

    # Удаляем файл с контентом
    rm -f $content_file
    return 0
end
