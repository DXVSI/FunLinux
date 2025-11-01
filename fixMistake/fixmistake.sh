#!/bin/bash

# fixMistake - автоматическая конвертация текста между раскладками клавиатуры
# Использование: вызывается через горячую клавишу Ctrl+Alt+→

# Карты конвертации символов EN <-> RU
declare -A en_to_ru=(
    [q]='й' [w]='ц' [e]='у' [r]='к' [t]='е' [y]='н' [u]='г' [i]='ш' [o]='щ' [p]='з'
    [a]='ф' [s]='ы' [d]='в' [f]='а' [g]='п' [h]='р' [j]='о' [k]='л' [l]='д'
    [z]='я' [x]='ч' [c]='с' [v]='м' [b]='и' [n]='т' [m]='ь'
    [Q]='Й' [W]='Ц' [E]='У' [R]='К' [T]='Е' [Y]='Н' [U]='Г' [I]='Ш' [O]='Щ' [P]='З'
    [A]='Ф' [S]='Ы' [D]='В' [F]='А' [G]='П' [H]='Р' [J]='О' [K]='Л' [L]='Д'
    [Z]='Я' [X]='Ч' [C]='С' [V]='М' [B]='И' [N]='Т' [M]='Ь'
    [\[]='х' [\]]='ъ' [\;]='ж' [\']='э' [,]='б' [.]='ю' [/]='.'
    [\{]='Х' [\}]='Ъ' [\:]='Ж' [\"]='Э' [\<]='Б' [\>]='Ю' [\?]=','
    [\`]='ё' [\~]='Ё'
)

declare -A ru_to_en=(
    ['й']='q' ['ц']='w' ['у']='e' ['к']='r' ['е']='t' ['н']='y' ['г']='u' ['ш']='i' ['щ']='o' ['з']='p'
    ['ф']='a' ['ы']='s' ['в']='d' ['а']='f' ['п']='g' ['р']='h' ['о']='j' ['л']='k' ['д']='l'
    ['я']='z' ['ч']='x' ['с']='c' ['м']='v' ['и']='b' ['т']='n' ['ь']='m'
    ['Й']='Q' ['Ц']='W' ['У']='E' ['К']='R' ['Е']='T' ['Н']='Y' ['Г']='U' ['Ш']='I' ['Щ']='O' ['З']='P'
    ['Ф']='A' ['Ы']='S' ['В']='D' ['А']='F' ['П']='G' ['Р']='H' ['О']='J' ['Л']='K' ['Д']='L'
    ['Я']='Z' ['Ч']='X' ['С']='C' ['М']='V' ['И']='B' ['Т']='N' ['Ь']='M'
    ['х']='[' ['ъ']=']' ['ж']=';' ['э']="'" ['б']=',' ['ю']='.' ['Х']='{' ['Ъ']='}' ['Ж']=':' ['Э']='"' ['Б']='<' ['Ю']='>'
    ['ё']='`' ['Ё']='~'
)

# Функция конвертации одного символа EN -> RU
convert_char_to_ru() {
    local char="$1"
    if [[ -n "${en_to_ru[$char]}" ]]; then
        echo -n "${en_to_ru[$char]}"
    else
        echo -n "$char"
    fi
}

# Функция конвертации одного символа RU -> EN
convert_char_to_en() {
    local char="$1"
    if [[ -n "${ru_to_en[$char]}" ]]; then
        echo -n "${ru_to_en[$char]}"
    else
        echo -n "$char"
    fi
}

# Конвертация всего слова EN -> RU
convert_word_to_ru() {
    local word="$1"
    local result=""
    local length=${#word}

    for ((i=0; i<length; i++)); do
        result+=$(convert_char_to_ru "${word:$i:1}")
    done

    echo "$result"
}

# Конвертация всего слова RU -> EN
convert_word_to_en() {
    local word="$1"
    local result=""

    while IFS= read -rn1 char; do
        [[ -z "$char" ]] && continue
        result+=$(convert_char_to_en "$char")
    done <<< "$word"

    echo "$result"
}

# Проверка, является ли слово "странным" (много согласных, нет гласных)
# Для латиницы: если нет гласных a,e,i,o,u - странное
is_weird_english() {
    local word="$1"
    # Убираем все не-буквы для проверки
    local clean_word=$(echo "$word" | tr -d '[:punct:][:digit:]')

    # Если слово пустое или очень короткое - не трогаем
    [[ ${#clean_word} -lt 2 ]] && return 1

    # Проверяем наличие английских гласных
    if echo "$clean_word" | grep -qi '[aeiou]'; then
        return 1  # Есть гласные - нормальное слово
    else
        return 0  # Нет гласных - странное слово (возможно русское в en раскладке)
    fi
}

# Проверка, является ли слово "странным" для кириллицы
# Если содержит только латиницу но нет гласных - странное
is_weird_russian() {
    local word="$1"
    local clean_word=$(echo "$word" | tr -d '[:punct:][:digit:]')

    [[ ${#clean_word} -lt 2 ]] && return 1

    # Если слово содержит русские гласные - нормальное
    if echo "$clean_word" | grep -q '[аеёиоуыэюяАЕЁИОУЫЭЮЯ]'; then
        return 1  # Есть русские гласные - нормальное русское слово
    else
        # Проверяем, есть ли латинские символы
        if echo "$clean_word" | grep -q '[a-zA-Z]'; then
            return 0  # Латиница без гласных - странное (возможно английское в ru раскладке)
        fi
        return 1
    fi
}

# Определение типа слова и конвертация
process_word() {
    local word="$1"

    # Пропускаем пустые слова
    [[ -z "$word" ]] && return

    # Проверяем на кириллицу
    if echo "$word" | grep -q '[а-яА-ЯёЁ]'; then
        # Содержит кириллицу - конвертируем в английский
        convert_word_to_en "$word"
    else
        # Содержит только латиницу - конвертируем в русский
        convert_word_to_ru "$word"
    fi
}

# Основная функция обработки текста
process_text() {
    local text="$1"
    local result=""
    local word=""

    # Обрабатываем текст посимвольно, сохраняя пробелы и знаки препинания
    while IFS= read -rn1 char; do
        if [[ "$char" =~ [[:space:]] ]] || [[ -z "$char" ]]; then
            # Пробел или конец - обрабатываем накопленное слово
            if [[ -n "$word" ]]; then
                result+=$(process_word "$word")
                word=""
            fi
            result+="$char"
        else
            # Накапливаем символы слова
            word+="$char"
        fi
    done <<< "$text"

    # Обрабатываем последнее слово если есть
    if [[ -n "$word" ]]; then
        result+=$(process_word "$word")
    fi

    echo -n "$result"
}

# Главная функция
main() {
    # Проверяем наличие xdotool
    if ! command -v xdotool &> /dev/null; then
        notify-send "fixMistake" "Ошибка: xdotool не установлен!" -u critical
        exit 1
    fi

    # Явно отпускаем все модификаторы перед началом работы
    xdotool keyup ctrl keyup alt keyup shift keyup super
    sleep 0.1

    # Пробуем получить выделенный текст напрямую из PRIMARY selection
    local selected_text=$(xclip -o -selection primary 2>/dev/null)

    # Если в PRIMARY ничего нет, пробуем скопировать через Ctrl+C
    if [[ -z "$selected_text" ]]; then
        # Очищаем буфер обмена перед копированием
        xclip -selection clipboard < /dev/null
        sleep 0.1

        # Копируем выделенный текст (Ctrl+C)
        xdotool key ctrl+c
        sleep 0.3  # Увеличиваем время ожидания

        # Снова отпускаем модификаторы после копирования
        xdotool keyup ctrl keyup alt keyup shift keyup super
        sleep 0.1

        # Получаем скопированный текст
        selected_text=$(xclip -o -selection clipboard 2>/dev/null)
    fi

    # Если ничего не выделено - выходим
    if [[ -z "$selected_text" ]]; then
        notify-send "fixMistake" "Нет выделенного текста" -u normal
        exit 0
    fi

    # Обрабатываем текст
    local converted_text=$(process_text "$selected_text")

    # Если текст не изменился - уведомляем
    if [[ "$selected_text" == "$converted_text" ]]; then
        notify-send "fixMistake" "Текст не требует конвертации" -u normal
        exit 0
    fi

    # Сохраняем текущее содержимое буфера обмена
    local old_clipboard=$(xclip -o -selection clipboard 2>/dev/null || echo "")

    # Удаляем выделенный текст
    xdotool key --clearmodifiers BackSpace
    sleep 0.05

    # Копируем конвертированный текст в буфер и вставляем
    echo -n "$converted_text" | xclip -selection clipboard
    sleep 0.05
    xdotool key --clearmodifiers ctrl+v
    sleep 0.1  # Ждём завершения вставки

    # Финальная очистка всех модификаторов
    xdotool keyup ctrl keyup alt keyup shift keyup super

    # Теперь очищаем или восстанавливаем буфер
    if [[ -n "$old_clipboard" ]]; then
        # Восстанавливаем оригинальное содержимое
        echo -n "$old_clipboard" | xclip -selection clipboard
    else
        # Если буфер был пуст, очищаем его полностью
        xclip -i /dev/null -selection clipboard 2>/dev/null
    fi

    # Показываем уведомление
    notify-send "fixMistake" "Текст исправлен!" -u low
}

# Запуск
main