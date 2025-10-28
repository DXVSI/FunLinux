# fishDisk - Упрощенное управление дисками для Fish Shell
# Все функции в одном файле

# ============================================
# UI КОМПОНЕНТЫ
# ============================================

# Проверка и установка зависимостей
function _disk_check_dependencies
    set -l missing_required
    set -l missing_optional

    # Обязательные зависимости
    set -l required lsblk blkid mount umount df sudo
    for cmd in $required
        if not command -v $cmd &>/dev/null
            set -a missing_required $cmd
        end
    end

    # Опциональные зависимости (улучшают функционал)
    set -l optional fzf cowsay lolcat lsof parted ntfs-3g
    for cmd in $optional
        if not command -v $cmd &>/dev/null
            set -a missing_optional $cmd
        end
    end

    # Если есть отсутствующие обязательные
    if test (count $missing_required) -gt 0
        echo "❌ Отсутствуют обязательные зависимости: $missing_required"
        echo ""
        echo "Установить сейчас? [Y/n]"
        read -l response

        if test "$response" = "" -o "$response" = "y" -o "$response" = "Y"
            _disk_install_packages $missing_required
        else
            return 1
        end
    end

    # Если есть отсутствующие опциональные
    if test (count $missing_optional) -gt 0
        echo "ℹ️  Отсутствуют опциональные зависимости: $missing_optional"
        echo "Они улучшают интерфейс но не обязательны."
        echo ""
        echo "Установить? [Y/n]"
        read -l response

        if test "$response" = "" -o "$response" = "y" -o "$response" = "Y"
            _disk_install_packages $missing_optional
        end
    end

    return 0
end

# Установка пакетов через dnf5/dnf (только Fedora)
function _disk_install_packages
    set -l packages $argv

    echo "📦 Устанавливаю: $packages"

    # Проверяем dnf5 или dnf (только Fedora)
    if command -v dnf5 &>/dev/null
        sudo dnf5 install -y $packages
    else if command -v dnf &>/dev/null
        sudo dnf install -y $packages
    else
        echo "❌ Не найден dnf5 или dnf! fishDisk работает только на Fedora."
        return 1
    end

    echo "✅ Пакеты установлены!"
end

# Простое цветное сообщение (без cowsay)
function _disk_message
    set -l message $argv[1]
    set -l mode $argv[2]

    switch $mode
        case success
            set_color green
            echo "✅ $message"
        case error
            set_color red
            echo "❌ $message"
        case warning
            set_color yellow
            echo "⚠️  $message"
        case info
            set_color blue
            echo "ℹ️  $message"
        case '*'
            echo $message
    end
    set_color normal
end

# Ошибка (простое сообщение)
function _disk_error
    _disk_message $argv[1] error
end

# Успех (простое сообщение)
function _disk_success
    _disk_message $argv[1] success
end

# Предупреждение (простое, без cowsay)
function _disk_warning
    _disk_message $argv[1] warning
end

# Информация (простое, без cowsay)
function _disk_info
    _disk_message $argv[1] info
end

# Выбор диска через fzf
function _disk_select_device
    set -l show_mounted $argv[1]  # "mounted" или "unmounted" или "all" или "setup"

    # Проверяем наличие fzf
    if not command -v fzf &>/dev/null
        return 1  # fzf не установлен
    end

    # Для setup показываем разделы + пустые диски
    set -l partitions_only yes
    if test "$show_mounted" = "setup"
        set partitions_only no
    end

    # Получаем список дисков
    set -l disks (_disk_list_all no $partitions_only)
    set -l filtered_disks

    for disk_info in $disks
        set -l parts (string split "|" $disk_info)
        set -l dev $parts[1]
        set -l size $parts[2]
        set -l fstype $parts[3]
        set -l label $parts[4]
        set -l mountpoint $parts[5]
        set -l usage $parts[6]
        set -l is_system $parts[7]
        set -l device_type $parts[8]

        # Для setup фильтруем физические диски
        if test "$show_mounted" = "setup"
            if test "$device_type" = "disk"
                # Показываем только пустые диски
                if _disk_has_partitions $dev
                    continue  # у диска есть разделы - показываем сами разделы
                end
            end
        end

        # Фильтруем по типу монтирования
        switch $show_mounted
            case mounted
                if test "$mountpoint" = "-"
                    continue
                end
            case unmounted
                if test "$mountpoint" != "-"
                    continue
                end
        end

        # Формируем строку для fzf
        set -l label_display $label
        if test "$label" = "-"
            set label_display "no label"
        end

        set -l mount_display $mountpoint
        if test "$mountpoint" = "-"
            set mount_display "not mounted"
        end

        # Пометка для пустых дисков
        if test "$device_type" = "disk"
            set label_display "[empty disk - needs partitioning]"
            set fstype "raw"
        end

        # Формат: device | size | fstype | label | mount
        set -l fzf_line "$dev|$size|$fstype|$label_display|$mount_display"
        set -a filtered_disks $fzf_line
    end

    if test (count $filtered_disks) -eq 0
        return 2  # нет дисков
    end

    # Показываем через fzf
    set -l selected (printf "%s\n" $filtered_disks | fzf \
        --height=40% \
        --border \
        --header="Выбери диск (Ctrl+C для отмены)" \
        --delimiter="|" \
        --with-nth=1,2,3,4,5 \
        --preview='printf "Устройство: {1}\nРазмер: {2}\nФайловая система: {3}\nМетка: {4}\nТочка монтирования: {5}\n"' \
        --preview-window=right:40%)

    if test -z "$selected"
        return 3  # отменено
    end

    # Извлекаем устройство
    echo $selected | cut -d'|' -f1
end

# Таблица дисков - заголовок
function _disk_table_header
    set_color blue --bold
    printf "%-15s │ %-8s │ %-6s │ %-15s │ %-20s │ %-6s\n" \
        "Device" "Size" "Type" "Label" "Mount Point" "Usage"
    set_color normal
    echo "────────────────┼──────────┼────────┼─────────────────┼──────────────────────┼────────"
end

# Таблица дисков - строка
function _disk_table_row
    set -l device $argv[1]
    set -l size $argv[2]
    set -l type $argv[3]
    set -l label $argv[4]
    set -l mountpoint $argv[5]
    set -l usage $argv[6]
    set -l is_system $argv[7]
    set -l device_type $argv[8]  # "disk" или "part"

    # Цвет в зависимости от статуса
    if test "$is_system" = "yes"
        set_color cyan --dim
        set -l lock "🔒 "
        printf "%s%-13s │ %-8s │ %-6s │ %-15s │ %-20s │ %-6s\n" \
            $lock $device $size $type $label $mountpoint $usage
    else if test "$device_type" = "disk"
        # Физический диск - помечаем серым с пометкой
        set_color white --dim
        printf "%-15s │ %-8s │ %-6s │ %-15s │ %-20s │ %-6s\n" \
            $device $size $type "[physical disk]" $mountpoint $usage
    else if test "$mountpoint" = "-"
        set_color white --dim
        printf "%-15s │ %-8s │ %-6s │ %-15s │ %-20s │ %-6s\n" \
            $device $size $type $label $mountpoint $usage
    else
        set_color green
        printf "%-15s │ %-8s │ %-6s │ %-15s │ %-20s │ %-6s\n" \
            $device $size $type $label $mountpoint $usage
    end
    set_color normal
end

# ============================================
# СКАНИРОВАНИЕ ДИСКОВ
# ============================================

# Проверить есть ли на диске разделы
function _disk_has_partitions
    set -l device $argv[1]

    if not string match -q "/dev/*" $device
        set device "/dev/$device"
    end

    # Получаем список дочерних устройств
    set -l children (lsblk -nlo NAME $device 2>/dev/null | tail -n +2)

    if test (count $children) -gt 0
        return 0  # есть разделы
    end

    return 1  # пустой диск
end

# Получить UUID раздела
function _disk_get_uuid
    set -l device $argv[1]

    # Добавляем /dev/ если не указан полный путь
    if not string match -q "/dev/*" $device
        set device "/dev/$device"
    end

    # Используем blkid для получения UUID
    sudo blkid -s UUID -o value $device 2>/dev/null
end

# Получить метку диска
function _disk_get_label
    set -l device $argv[1]

    if not string match -q "/dev/*" $device
        set device "/dev/$device"
    end

    sudo blkid -s LABEL -o value $device 2>/dev/null
end

# Получить тип файловой системы
function _disk_get_fstype
    set -l device $argv[1]

    if not string match -q "/dev/*" $device
        set device "/dev/$device"
    end

    sudo blkid -s TYPE -o value $device 2>/dev/null
end

# Проверить примонтирован ли диск
function _disk_is_mounted
    set -l device $argv[1]

    if not string match -q "/dev/*" $device
        set device "/dev/$device"
    end

    # Проверяем через findmnt
    if command -v findmnt &>/dev/null
        findmnt -n -o SOURCE $device &>/dev/null
        return $status
    else
        # Fallback на проверку через mount
        mount | grep -q "^$device "
        return $status
    end
end

# Получить точку монтирования
function _disk_get_mountpoint
    set -l device $argv[1]

    if not string match -q "/dev/*" $device
        set device "/dev/$device"
    end

    if command -v findmnt &>/dev/null
        findmnt -n -o TARGET $device 2>/dev/null
    else
        mount | grep "^$device " | awk '{print $3}'
    end
end

# Получить процент использования
function _disk_get_usage
    set -l device $argv[1]

    set -l mountpoint (_disk_get_mountpoint $device)

    if test -z "$mountpoint"
        echo "-"
        return 0
    end

    # Используем df для получения использования
    df -h $mountpoint 2>/dev/null | awk 'NR==2 {print $5}'
end

# Проверить является ли диск системным
function _disk_is_system
    set -l device $argv[1]

    if not string match -q "/dev/*" $device
        set device "/dev/$device"
    end

    # Критичные точки монтирования
    set -l critical_mounts "/" "/boot" "/boot/efi" "/home" "/usr" "/var" "/etc"

    # Проверяем монтирование критичных путей
    for mount_point in $critical_mounts
        set -l mounted_device (findmnt -n -o SOURCE $mount_point 2>/dev/null)
        # Убираем [subvolume] если есть (для btrfs)
        set mounted_device (string replace -r '\[.*\]' '' $mounted_device)
        if string match -q "$device*" $mounted_device
            return 0  # это системный диск!
        end
    end

    # Проверяем swap
    if swapon --show=NAME --noheadings 2>/dev/null | grep -q "^$device"
        return 0
    end

    # Проверяем метки которые указывают на системный диск
    set -l label (_disk_get_label $device)
    if string match -qi -r "(fedora|system|root|boot|efi)" $label
        # Дополнительная проверка - если не примонтирован, то не системный
        if not _disk_is_mounted $device
            return 1
        end
        return 0
    end

    return 1  # безопасно
end

# Получить размер в человеко-читаемом формате
function _disk_get_size
    set -l device $argv[1]

    if not string match -q "/dev/*" $device
        set device "/dev/$device"
    end

    lsblk -ndo SIZE $device 2>/dev/null
end

# Получить список всех дисков с полной информацией
function _disk_list_all
    set -l show_system $argv[1]
    set -l partitions_only $argv[2]  # "yes" - только разделы, без целых дисков

    # Получаем список всех блочных устройств через lsblk -P (pairs format)
    lsblk -nPo NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null | while read -l line
        # Парсим пары KEY="VALUE"
        set -l device (string match -r 'NAME="([^"]*)"' $line)[2]
        set -l size (string match -r 'SIZE="([^"]*)"' $line)[2]
        set -l type (string match -r 'TYPE="([^"]*)"' $line)[2]
        set -l fstype (string match -r 'FSTYPE="([^"]*)"' $line)[2]
        set -l label (string match -r 'LABEL="([^"]*)"' $line)[2]
        set -l mountpoint (string match -r 'MOUNTPOINT="([^"]*)"' $line)[2]

        # Пропускаем loop, rom, zram устройства
        if string match -q -r "loop|rom" $device
            continue
        end
        if string match -q -r "loop|rom" $type
            continue
        end

        # Если нужны только разделы - пропускаем целые диски
        if test "$partitions_only" = "yes"
            if test "$type" = "disk"
                continue
            end
        end

        set -l usage (_disk_get_usage $device)
        set -l is_system no

        # Проверяем системный ли это диск
        if _disk_is_system $device
            set is_system yes
            # Если не показываем системные - пропускаем
            if test "$show_system" != "yes"
                continue
            end
        end

        # Значения по умолчанию для пустых полей
        if test -z "$size"
            set size "-"
        end
        if test -z "$fstype"
            set fstype "-"
        end
        if test -z "$label"
            set label "-"
        end
        if test -z "$mountpoint"
            set mountpoint "-"
        end
        if test -z "$usage"
            set usage "-"
        end

        # Выводим строку через разделитель | для надежного парсинга
        echo "$device|$size|$fstype|$label|$mountpoint|$usage|$is_system|$type"
    end
end

# ============================================
# МОНТИРОВАНИЕ
# ============================================

# Предложить точку монтирования на основе метки или размера
function _disk_suggest_mountpoint
    set -l device $argv[1]

    if not string match -q "/dev/*" $device
        set device "/dev/$device"
    end

    # Получаем метку
    set -l label (_disk_get_label $device)

    # Если есть метка - используем её
    if test -n "$label"
        echo "/mnt/$label"
        return 0
    end

    # Если метки нет - предлагаем на основе размера
    set -l size (_disk_get_size $device)

    # Парсим размер (например "1.8T" или "500G")
    set -l size_num (string match -r '^[0-9.]+' $size)
    set -l size_unit (string match -r '[KMGT]' $size)

    set -l suggested_name "disk"

    # Конвертируем в GB для сравнения
    switch $size_unit
        case K
            set suggested_name "flash"
        case M
            set suggested_name "flash"
        case G
            if test (math "$size_num < 32") -eq 1
                set suggested_name "flash"
            else if test (math "$size_num < 256") -eq 1
                set suggested_name "ssd"
            else
                set suggested_name "data"
            end
        case T
            set suggested_name "archive"
    end

    echo "/mnt/$suggested_name"
end

# Создать точку монтирования
function _disk_create_mountpoint
    set -l mountpoint $argv[1]

    # Проверяем существует ли
    if test -d "$mountpoint"
        return 0
    end

    # Создаём директорию
    sudo mkdir -p "$mountpoint" 2>/dev/null

    if test $status -ne 0
        _disk_error "Не могу создать директорию $mountpoint"
        return 1
    end

    return 0
end

# Установить владельца на текущего пользователя
function _disk_set_ownership
    set -l mountpoint $argv[1]
    set -l fstype $argv[2]

    # Для ext4/btrfs/xfs - просто меняем владельца
    if string match -q -r "ext[234]|btrfs|xfs" $fstype
        sudo chown -R $USER:$USER "$mountpoint" 2>/dev/null
        return $status
    end

    # Для ntfs/vfat - права устанавливаются при монтировании через uid/gid
    # Ничего не делаем, они уже должны быть правильные
    return 0
end

# Команда: disk mount
function _disk_cmd_mount
    set -l device $argv[1]

    # Если устройство не указано - интерактивный выбор
    if test -z "$device"
        # Пробуем fzf
        set device (_disk_select_device unmounted)
        set -l fzf_status $status

        if test $fzf_status -eq 1
            # fzf не установлен - fallback на ручной ввод
            echo ""
            echo "Доступные диски для монтирования:"
            echo ""

            set -l disks (_disk_list_all no)
            set -l unmounted_disks

            for disk_info in $disks
                set -l parts (string split "|" $disk_info)
                set -l dev $parts[1]
                set -l mountpoint $parts[5]

                if test "$mountpoint" != "-"
                    continue
                end

                set -a unmounted_disks $disk_info
            end

            if test (count $unmounted_disks) -eq 0
                _disk_warning "Нет доступных дисков для монтирования"
                return 0
            end

            _disk_table_header
            for disk_info in $unmounted_disks
                set -l parts (string split "|" $disk_info)
                _disk_table_row $parts[1] $parts[2] $parts[3] $parts[4] $parts[5] $parts[6] $parts[7] $parts[8]
            end
            echo ""

            echo "Введите устройство для монтирования (например: sda1):"
            read -l device

            if test -z "$device"
                echo "Отменено"
                return 0
            end
        else if test $fzf_status -eq 2
            _disk_warning "Нет доступных дисков для монтирования"
            return 0
        else if test $fzf_status -eq 3
            echo "Отменено"
            return 0
        end
    end

    # Добавляем /dev/ если не указан
    if not string match -q "/dev/*" $device
        set device "/dev/$device"
    end

    # Проверяем существование устройства
    if not test -b "$device"
        _disk_error "Устройство $device не найдено!"
        return 1
    end

    # Проверяем что это не системный диск
    if _disk_is_system $device
        _disk_error "Это системный диск! Операция ЗАПРЕЩЕНА!"
        return 1
    end

    # Проверяем что не примонтирован
    if _disk_is_mounted $device
        set -l current_mount (_disk_get_mountpoint $device)
        _disk_warning "Диск уже примонтирован в $current_mount"
        return 0
    end

    # Получаем информацию о диске
    set -l fstype (_disk_get_fstype $device)
    set -l label (_disk_get_label $device)
    set -l size (_disk_get_size $device)

    # Проверяем файловую систему
    if test -z "$fstype"
        _disk_error "Не могу определить файловую систему! Возможно диск не отформатирован."
        echo "Используй 'disk setup' для форматирования."
        return 1
    end

    echo ""
    echo "Диск: $device"
    echo "  Размер: $size"
    echo "  Файловая система: $fstype"
    if test -n "$label"
        echo "  Метка: $label"
    end
    echo ""

    # Предлагаем точку монтирования
    set -l suggested_mount (_disk_suggest_mountpoint $device)
    echo "Точка монтирования: $suggested_mount"
    echo "Использовать или ввести свою? [Y/ввести путь]"
    read -l mountpoint_choice

    set -l mountpoint $suggested_mount
    if test -n "$mountpoint_choice" -a "$mountpoint_choice" != "y" -a "$mountpoint_choice" != "Y"
        set mountpoint $mountpoint_choice
    end

    # Создаём точку монтирования
    if not _disk_create_mountpoint $mountpoint
        return 1
    end

    echo ""
    echo "Монтирую $device в $mountpoint..."

    # Монтируем с опциями в зависимости от FS
    switch $fstype
        case "ntfs"
            # Для NTFS используем ntfs-3g с правами пользователя
            set -l uid (id -u)
            set -l gid (id -g)
            sudo mount -t ntfs-3g -o uid=$uid,gid=$gid,umask=0022 $device $mountpoint
        case "vfat" "exfat"
            # Для FAT тоже uid/gid
            set -l uid (id -u)
            set -l gid (id -g)
            sudo mount -o uid=$uid,gid=$gid,umask=0022 $device $mountpoint
        case "*"
            # Для ext4/btrfs/xfs - defaults
            sudo mount $device $mountpoint
    end

    if test $status -ne 0
        _disk_error "Ошибка монтирования!"
        return 1
    end

    # Устанавливаем владельца для ext4/btrfs/xfs
    _disk_set_ownership $mountpoint $fstype

    # Проверяем успешность
    if _disk_is_mounted $device
        _disk_success "Диск успешно примонтирован в $mountpoint!"

        # Показываем использование
        set -l usage (_disk_get_usage $device)
        echo ""
        echo "Использование: $usage"
        echo "Теперь можешь использовать: cd $mountpoint"
        echo ""
        echo "Для автоматического монтирования при загрузке используй:"
        echo "  disk auto $device"
    else
        _disk_error "Монтирование выполнено, но диск не виден как примонтированный"
        return 1
    end

    return 0
end

# ============================================
# КОМАНДЫ
# ============================================

# Показать help
function _disk_show_help
    echo ""
    set_color blue --bold
    echo "fishDisk - Упрощенное управление дисками для Fedora"
    set_color normal
    echo ""
    echo "КОМАНДЫ:"
    echo ""
    echo "Все команды поддерживают интерактивный режим - если не указать параметры,"
    echo "будет показан удобный выбор через fzf (стрелки + Enter)."
    echo ""

    set_color green
    echo "  disk list [--all]"
    set_color normal
    echo "    Показать все доступные диски и разделы"
    echo "    --all - включая системные диски"
    echo ""

    set_color green
    echo "  disk mount [устройство]"
    set_color normal
    echo "    Примонтировать диск с автоматическими правами доступа"
    echo "    • Без параметра - интерактивный выбор через fzf"
    echo "    • Автоматически создает точку монтирования"
    echo "    • Устанавливает права для вашего пользователя"
    echo "    • Поддерживает ext4, btrfs, xfs, ntfs, vfat, exfat"
    echo ""

    set_color green
    echo "  disk auto [устройство]"
    set_color normal
    echo "    Добавить примонтированный диск в /etc/fstab"
    echo "    • Требует указать устройство (например: disk auto sda2)"
    echo "    • Автоматически получает UUID"
    echo "    • Создает backup fstab перед изменением"
    echo "    • Тестирует конфигурацию через mount -a"
    echo "    • Откатывает при ошибке"
    echo ""

    set_color green
    echo "  disk setup [устройство]"
    set_color normal
    echo "    Полная настройка диска (всё в одном)"
    echo "    • Без параметра - интерактивный wizard с выбором диска"
    echo "    • Форматирование в выбранную ФС (ext4/btrfs/xfs/ntfs/exfat)"
    echo "    • Установка метки диска (с транслитерацией кириллицы)"
    echo "    • Автоматическое монтирование с правами"
    echo "    • Добавление в fstab"
    echo ""

    set_color green
    echo "  disk unmount [устройство|точка]"
    set_color normal
    echo "    Размонтировать диск"
    echo "    • Без параметра - интерактивный выбор примонтированных дисков"
    echo "    • Проверяет открытые файлы (быстро через fuser)"
    echo "    • Опционально удаляет из fstab"
    echo ""

    set_color green
    echo "  disk fix [устройство|точка]"
    set_color normal
    echo "    Исправить права доступа на диске"
    echo "    • Без параметра - интерактивный выбор дисков"
    echo "    • Диагностика владельца и прав"
    echo "    • Автоматическое исправление через chown/chmod"
    echo ""

    echo "ОПЦИИ:"
    echo "  --help, -h             Показать эту справку"
    echo "  --version, -v          Показать версию"
    echo ""

    set_color yellow --bold
    echo "БЫСТРЫЙ СТАРТ:"
    set_color normal
    echo ""
    echo "1. Посмотреть доступные диски:"
    echo "   disk list"
    echo ""
    echo "2. Примонтировать существующий диск:"
    echo "   disk mount sda2"
    echo "   disk auto sda2          # Добавить в fstab для автомонтирования"
    echo ""
    echo "3. Форматировать и настроить новый диск (всё в одной команде):"
    echo "   disk setup"
    echo "   → Выбираешь диск через fzf"
    echo "   → Выбираешь файловую систему (ext4/btrfs/xfs)"
    echo "   → Вводишь метку диска"
    echo "   → Подтверждаешь через DELETE"
    echo "   → Готово! Диск отформатирован, примонтирован и в fstab"
    echo ""

    set_color cyan
    echo "WORKFLOW ПРИМЕРЫ:"
    set_color normal
    echo ""
    echo "• Добавить диск Windows (NTFS) в систему:"
    echo "  disk mount sda2           # Монтирует с правильными uid/gid"
    echo "  disk auto sda2            # Добавляет в fstab"
    echo ""
    echo "• Отформатировать флешку в exFAT:"
    echo "  disk setup sdb1           # Wizard форматирования"
    echo ""
    echo "• Размонтировать диск перед извлечением:"
    echo "  disk unmount /mnt/flash   # Безопасное размонтирование"
    echo ""
    echo "• Исправить проблемы с правами:"
    echo "  disk fix /mnt/data        # Автоматическая диагностика и fix"
    echo ""

    set_color red
    echo "БЕЗОПАСНОСТЬ:"
    set_color normal
    echo "  • Системные диски защищены от форматирования"
    echo "  • Автоматический backup /etc/fstab перед изменениями"
    echo "  • Двойное подтверждение для опасных операций"
    echo ""
end

# Команда: disk list
function _disk_cmd_list
    set -l show_system no

    # Парсинг опций
    for arg in $argv
        switch $arg
            case --all -a --show-system
                set show_system yes
        end
    end

    echo "Сканирую диски..."
    echo ""

    # Получаем список дисков
    set -l disks (_disk_list_all $show_system)

    if test -z "$disks"
        _disk_warning "Диски не найдены"
        return 0
    end

    # Показываем заголовок таблицы
    _disk_table_header

    # Показываем каждый диск
    for disk_info in $disks
        # Парсим информацию через разделитель |
        set -l parts (string split "|" $disk_info)
        set -l device $parts[1]
        set -l size $parts[2]
        set -l fstype $parts[3]
        set -l label $parts[4]
        set -l mountpoint $parts[5]
        set -l usage $parts[6]
        set -l is_system $parts[7]
        set -l device_type $parts[8]

        _disk_table_row $device $size $fstype $label $mountpoint $usage $is_system $device_type
    end

    echo ""

    # Дополнительная информация
    if test "$show_system" = "yes"
        echo ""
        echo "🔒 - Системный диск (защищен)"
    else
        echo ""
        echo "Совет: 'disk list --all' покажет системные диски"
    end
end

# ============================================
# РАЗМОНТИРОВАНИЕ
# ============================================

# Проверка открытых файлов на диске (быстрая версия)
function _disk_check_open_files
    set -l mountpoint $argv[1]

    # Используем fuser (быстрее чем lsof +D)
    if command -v fuser &>/dev/null
        # fuser возвращает 0 если есть процессы
        sudo fuser -m "$mountpoint" &>/dev/null
        if test $status -eq 0
            return 1  # Есть открытые файлы
        end
    end

    return 0  # Нет открытых файлов или не можем проверить
end

# Команда: disk unmount
function _disk_cmd_unmount
    set -l target $argv[1]

    # Если не указано - интерактивный выбор
    if test -z "$target"
        # Пробуем fzf
        set target (_disk_select_device mounted)
        set -l fzf_status $status

        if test $fzf_status -eq 1
            # fzf не установлен - fallback
            echo ""
            echo "Примонтированные диски:"
            echo ""

            set -l disks (_disk_list_all no)
            set -l mounted_disks

            for disk_info in $disks
                set -l parts (string split "|" $disk_info)
                set -l dev $parts[1]
                set -l mountpoint $parts[5]

                if test "$mountpoint" = "-"
                    continue
                end

                set -a mounted_disks $disk_info
            end

            if test (count $mounted_disks) -eq 0
                _disk_warning "Нет примонтированных дисков для размонтирования"
                return 0
            end

            _disk_table_header
            for disk_info in $mounted_disks
                set -l parts (string split "|" $disk_info)
                _disk_table_row $parts[1] $parts[2] $parts[3] $parts[4] $parts[5] $parts[6] $parts[7] $parts[8]
            end
            echo ""

            echo "Введите устройство или точку монтирования (например: sda1 или /mnt/data):"
            read -l target

            if test -z "$target"
                echo "Отменено"
                return 0
            end
        else if test $fzf_status -eq 2
            _disk_warning "Нет примонтированных дисков для размонтирования"
            return 0
        else if test $fzf_status -eq 3
            echo "Отменено"
            return 0
        end
    end

    # Определяем это устройство или точка монтирования
    set -l device ""
    set -l mountpoint ""

    if string match -q "/dev/*" $target
        set device $target
        set mountpoint (_disk_get_mountpoint $device)
    else if string match -q "/*" $target
        set mountpoint $target
        # Находим устройство по точке монтирования
        set device (findmnt -n -o SOURCE "$mountpoint" 2>/dev/null)
    else
        # Пробуем как имя устройства
        set device "/dev/$target"
        set mountpoint (_disk_get_mountpoint $device)
    end

    # Проверяем что диск примонтирован
    if test -z "$mountpoint"
        _disk_error "Диск не примонтирован или не найден"
        return 1
    end

    # Проверка что это не системный
    if _disk_is_system $device
        _disk_error "Это системный диск! Размонтирование ЗАПРЕЩЕНО!"
        return 1
    end

    echo ""
    echo "Размонтирование:"
    echo "  Устройство: $device"
    echo "  Точка монтирования: $mountpoint"
    echo ""

    # Проверяем открытые файлы
    if not _disk_check_open_files "$mountpoint"
        _disk_warning "На диске есть открытые файлы!"
        echo ""
        echo "Процессы использующие диск:"
        sudo fuser -vm "$mountpoint" 2>/dev/null
        echo ""
        echo "Принудительно размонтировать? [y/N]"
        read -l force

        if test "$force" != "y" -a "$force" != "Y"
            echo "Отменено"
            return 0
        end
    end

    # Размонтируем
    echo "Размонтирую..."
    sudo umount "$mountpoint"

    if test $status -ne 0
        _disk_error "Не удалось размонтировать!"
        echo "Попробуй принудительное размонтирование:"
        echo "  sudo umount -l $mountpoint"
        return 1
    end

    _disk_success "Диск успешно размонтирован!"

    # Спрашиваем про удаление из fstab
    if grep -q "$device" /etc/fstab 2>/dev/null
        echo ""
        echo "Диск прописан в /etc/fstab (автоматическое монтирование)"
        echo "Удалить из fstab? [y/N]"
        read -l remove_fstab

        if test "$remove_fstab" = "y" -o "$remove_fstab" = "Y"
            # Создаём backup
            sudo cp /etc/fstab /etc/fstab.backup.(date +%Y%m%d_%H%M%S)

            # Удаляем строку с устройством
            sudo sed -i "\|$device|d" /etc/fstab

            _disk_success "Удалено из fstab"
        end
    end

    return 0
end

# ============================================
# РАБОТА С FSTAB
# ============================================

# Команда: disk auto - добавление в fstab для автомонтирования
function _disk_cmd_auto
    set -l device $argv[1]

    if test -z "$device"
        echo ""
        set_color yellow
        echo "Использование: disk auto <устройство>"
        set_color normal
        echo ""
        echo "Примеры:"
        echo "  disk auto sda1"
        echo "  disk auto /dev/sda1"
        echo ""
        echo "Эта команда добавляет примонтированный диск в /etc/fstab"
        echo "для автоматического монтирования при загрузке системы."
        return 1
    end

    # Добавляем /dev/ если нет
    if not string match -q "/dev/*" $device
        set device "/dev/$device"
    end

    # Проверка существования
    if not test -b "$device"
        _disk_error "Устройство $device не найдено!"
        return 1
    end

    # Проверка системного
    if _disk_is_system $device
        _disk_error "Это системный диск!"
        return 1
    end

    # Должен быть примонтирован
    if not _disk_is_mounted $device
        _disk_error "Диск не примонтирован! Сначала выполни: disk mount $device"
        return 1
    end

    # Получаем информацию
    set -l mountpoint (_disk_get_mountpoint $device)
    set -l fstype (_disk_get_fstype $device)
    set -l uuid (_disk_get_uuid $device)
    set -l label (_disk_get_label $device)

    # Проверяем не добавлен ли уже
    if grep -q "$uuid" /etc/fstab 2>/dev/null
        _disk_warning "Диск уже есть в fstab"
        return 0
    end

    echo ""
    echo "Добавление в /etc/fstab:"
    echo "  UUID: $uuid"
    echo "  Точка: $mountpoint"
    echo "  ФС: $fstype"
    if test -n "$label"
        echo "  Метка: $label"
    end
    echo ""

    # Определяем опции монтирования
    set -l mount_opts "defaults"
    switch $fstype
        case "ext4" "ext3" "ext2"
            set mount_opts "defaults,noatime"
        case "btrfs"
            set mount_opts "defaults,noatime,compress=zstd"
        case "xfs"
            set mount_opts "defaults,noatime"
        case "ntfs"
            set -l uid (id -u)
            set -l gid (id -g)
            set mount_opts "defaults,uid=$uid,gid=$gid,umask=0022"
        case "vfat" "exfat"
            set -l uid (id -u)
            set -l gid (id -g)
            set mount_opts "defaults,uid=$uid,gid=$gid,umask=0022"
    end

    # Создаём backup fstab
    sudo cp /etc/fstab /etc/fstab.backup.(date +%Y%m%d_%H%M%S)

    # Формируем строку
    set -l comment ""
    if test -n "$label"
        set comment "# $label"
    end

    # Добавляем в fstab
    echo "$comment" | sudo tee -a /etc/fstab >/dev/null
    echo "UUID=$uuid  $mountpoint  $fstype  $mount_opts  0  2" | sudo tee -a /etc/fstab >/dev/null

    # Тестируем
    echo "Тестирую конфигурацию..."
    sudo mount -a

    if test $status -ne 0
        _disk_error "Ошибка в fstab! Откатываю изменения..."
        sudo mv /etc/fstab.backup.(date +%Y%m%d_%H%M%S | tail -1) /etc/fstab
        return 1
    end

    _disk_success "Диск добавлен в fstab! Будет монтироваться автоматически при загрузке"

    return 0
end

# ============================================
# ФОРМАТИРОВАНИЕ
# ============================================

# Создать раздел на весь диск
function _disk_create_partition
    set -l device $argv[1]

    if not string match -q "/dev/*" $device
        set device "/dev/$device"
    end

    echo "Создаю таблицу разделов GPT..."

    # Используем parted для создания GPT и раздела на весь диск
    sudo parted -s $device mklabel gpt
    if test $status -ne 0
        return 1
    end

    echo "Создаю раздел на весь диск..."
    sudo parted -s $device mkpart primary 0% 100%
    if test $status -ne 0
        return 1
    end

    # Ждём пока система обнаружит новый раздел
    sleep 2
    sudo partprobe $device 2>/dev/null

    # Определяем имя созданного раздела (обычно это device + 1)
    set -l partition_name
    if string match -qr 'nvme|mmcblk' $device
        set partition_name "$device"p1
    else
        set partition_name "$device"1
    end

    echo $partition_name
    return 0
end

# Валидация метки
function _disk_validate_label
    set -l label $argv[1]
    set -l fstype $argv[2]

    # Проверка на кириллицу
    if string match -qr '[а-яА-ЯёЁ]' $label
        return 2
    end

    # Проверка длины
    switch $fstype
        case ext4 ext3 ext2
            if test (string length $label) -gt 16
                return 1
            end
        case xfs
            if test (string length $label) -gt 12
                return 1
            end
        case ntfs
            if test (string length $label) -gt 32
                return 1
            end
        case vfat exfat
            if test (string length $label) -gt 11
                return 1
            end
    end

    # Проверка символов
    if not string match -qr '^[a-zA-Z0-9_-]+$' $label
        return 1
    end

    return 0
end

# Транслитерация
function _disk_transliterate
    set -l text $argv[1]
    echo $text | sed '
        y/абвгдеёжзийклмнопрстуфхцчшщъыьэюя/abvgdeyozhzijklmnoprstufhtsчshsh_y_eyuya/
        y/АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ/ABVGDEYOZHZIJKLMNOPRSTUFHTSЧSHSH_Y_EYUYA/
    '
end

# Команда: disk setup - форматирование и настройка
function _disk_cmd_setup
    set -l device $argv[1]

    # Интерактивный выбор диска
    if test -z "$device"
        # Пробуем fzf с режимом setup (показывает разделы + пустые диски)
        set device (_disk_select_device setup)
        set -l fzf_status $status

        if test $fzf_status -eq 1
            # fzf не установлен - fallback
            echo ""
            echo "Доступные диски для форматирования:"
            echo ""

            set -l disks (_disk_list_all no)
            set -l safe_disks

            for disk_info in $disks
                set -l parts (string split "|" $disk_info)
                set -a safe_disks $disk_info
            end

            if test (count $safe_disks) -eq 0
                _disk_warning "Нет доступных дисков"
                return 0
            end

            _disk_table_header
            for disk_info in $safe_disks
                set -l parts (string split "|" $disk_info)
                _disk_table_row $parts[1] $parts[2] $parts[3] $parts[4] $parts[5] $parts[6] $parts[7] $parts[8]
            end
            echo ""

            echo "Введите устройство (например: sda1):"
            read -l device

            if test -z "$device"
                echo "Отменено"
                return 0
            end
        else if test $fzf_status -eq 2
            _disk_warning "Нет доступных дисков"
            return 0
        else if test $fzf_status -eq 3
            echo "Отменено"
            return 0
        end
    end

    # Добавляем /dev/
    if not string match -q "/dev/*" $device
        set device "/dev/$device"
    end

    # Проверки
    if not test -b "$device"
        _disk_error "Устройство не найдено!"
        return 1
    end

    if _disk_is_system $device
        _disk_error "Это СИСТЕМНЫЙ диск! Форматирование ЗАБЛОКИРОВАНО!"
        return 1
    end

    if _disk_is_mounted $device
        _disk_error "Диск примонтирован! Сначала размонтируй: disk unmount $device"
        return 1
    end

    # Определяем это пустой диск или раздел
    set -l is_empty_disk no
    set -l device_type (lsblk -ndo TYPE $device 2>/dev/null)

    if test "$device_type" = "disk"
        if not _disk_has_partitions $device
            set is_empty_disk yes
        end
    end

    # Информация о диске
    set -l size (_disk_get_size $device)
    set -l current_fs (_disk_get_fstype $device)
    set -l current_label (_disk_get_label $device)

    echo ""
    set_color red --bold
    echo "⚠️  ВНИМАНИЕ! ВСЕ ДАННЫЕ БУДУТ УДАЛЕНЫ! ⚠️"
    set_color normal
    echo ""
    echo "Диск: $device"
    echo "  Размер: $size"
    if test "$is_empty_disk" = "yes"
        echo "  Тип: Пустой диск (будет создан раздел GPT)"
    else
        if test -n "$current_fs"
            echo "  Текущая ФС: $current_fs"
        end
        if test -n "$current_label"
            echo "  Текущая метка: $current_label"
        end
    end
    echo ""

    # Выбор файловой системы
    echo "Выбери файловую систему:"
    echo "  1) ext4      (рекомендуется для Linux)"
    echo "  2) btrfs     (продвинутая с snapshots)"
    echo "  3) xfs       (для больших файлов)"
    echo "  4) ntfs      (совместимость с Windows)"
    echo "  5) exfat     (USB, кроссплатформенная)"
    echo ""
    echo "Выбор [1-5]:"
    read -l fs_choice

    set -l fstype ""
    switch $fs_choice
        case 1
            set fstype "ext4"
        case 2
            set fstype "btrfs"
        case 3
            set fstype "xfs"
        case 4
            set fstype "ntfs"
        case 5
            set fstype "exfat"
        case '*'
            echo "Отменено"
            return 0
    end

    # Запрос метки
    echo ""
    echo "Введите метку диска:"
    echo "  Примеры: Data, Backup, Games, Storage"
    echo "  Ограничения: латиница, цифры, _-  (без пробелов)"
    echo ""
    read -l label

    if test -z "$label"
        _disk_error "Метка обязательна!"
        return 1
    end

    # Валидация метки
    _disk_validate_label "$label" "$fstype"
    set -l validate_result $status

    if test $validate_result -eq 2
        # Кириллица
        set -l transliterated (_disk_transliterate "$label")
        echo ""
        _disk_warning "Кириллица обнаружена!"
        echo "Транслитерировать в '$transliterated'? [Y/n]"
        read -l trans_choice

        if test "$trans_choice" != "n" -a "$trans_choice" != "N"
            set label $transliterated
        else
            _disk_error "Используй латиницу для метки"
            return 1
        end
    else if test $validate_result -eq 1
        _disk_error "Некорректная метка! Проверь ограничения."
        return 1
    end

    # Финальное подтверждение
    echo ""
    set_color red --bold
    echo "ПОСЛЕДНЕЕ ПРЕДУПРЕЖДЕНИЕ!"
    set_color normal
    echo ""
    echo "Будет выполнено:"
    echo "  Устройство: $device ($size)"
    echo "  Файловая система: $fstype"
    echo "  Метка: $label"
    echo ""
    echo "Для подтверждения введи слово DELETE:"
    read -l confirmation

    if test "$confirmation" != "DELETE"
        echo "Отменено"
        return 0
    end

    # Если пустой диск - сначала создаём раздел
    set -l target_device $device
    if test "$is_empty_disk" = "yes"
        echo ""
        echo "Это пустой диск. Создаю раздел на весь объём..."

        set target_device (_disk_create_partition $device)
        if test $status -ne 0
            _disk_error "Ошибка создания раздела!"
            return 1
        end

        echo "Создан раздел: $target_device"
        echo ""
    end

    # Форматируем
    echo "Форматирование началось..."

    switch $fstype
        case ext4
            sudo mkfs.ext4 -L "$label" $target_device
        case btrfs
            sudo mkfs.btrfs -L "$label" $target_device
        case xfs
            sudo mkfs.xfs -L "$label" $target_device
        case ntfs
            sudo mkfs.ntfs -L "$label" -f $target_device
        case exfat
            sudo mkfs.exfat -n "$label" $target_device
    end

    if test $status -ne 0
        _disk_error "Ошибка форматирования!"
        return 1
    end

    _disk_success "Диск отформатирован!"

    # Обновляем device на раздел для последующего монтирования
    set device $target_device

    # Предлагаем примонтировать
    echo ""
    echo "Примонтировать диск сейчас? [Y/n]"
    read -l mount_now

    if test "$mount_now" != "n" -a "$mount_now" != "N"
        _disk_cmd_mount $device

        # Предлагаем добавить в fstab
        if _disk_is_mounted $device
            echo ""
            echo "Добавить в fstab (автомонтирование при загрузке)? [Y/n]"
            read -l auto_mount

            if test "$auto_mount" != "n" -a "$auto_mount" != "N"
                _disk_cmd_auto $device
            end
        end
    end

    return 0
end

# ============================================
# ДИАГНОСТИКА И ИСПРАВЛЕНИЕ
# ============================================

# Команда: disk fix
function _disk_cmd_fix
    set -l target $argv[1]

    echo ""
    echo "Диагностика и исправление проблем"
    echo ""

    # Если не указано - выбор
    if test -z "$target"
        # Пробуем fzf
        set target (_disk_select_device mounted)
        set -l fzf_status $status

        if test $fzf_status -eq 1
            # fzf не установлен - fallback
            echo "Примонтированные диски:"
            echo ""

            set -l disks (_disk_list_all no)
            set -l mounted_disks

            for disk_info in $disks
                set -l parts (string split "|" $disk_info)
                set -l mountpoint $parts[5]

                if test "$mountpoint" = "-"
                    continue
                end

                set -a mounted_disks $disk_info
            end

            if test (count $mounted_disks) -eq 0
                _disk_warning "Нет примонтированных дисков"
                return 0
            end

            _disk_table_header
            for disk_info in $mounted_disks
                set -l parts (string split "|" $disk_info)
                _disk_table_row $parts[1] $parts[2] $parts[3] $parts[4] $parts[5] $parts[6] $parts[7] $parts[8]
            end
            echo ""

            echo "Введите устройство или точку монтирования:"
            read -l target

            if test -z "$target"
                echo "Отменено"
                return 0
            end
        else if test $fzf_status -eq 2
            _disk_warning "Нет примонтированных дисков"
            return 0
        else if test $fzf_status -eq 3
            echo "Отменено"
            return 0
        end
    end

    # Определяем устройство и точку
    set -l device ""
    set -l mountpoint ""

    if string match -q "/dev/*" $target
        set device $target
        set mountpoint (_disk_get_mountpoint $device)
    else if string match -q "/*" $target
        set mountpoint $target
        set device (findmnt -n -o SOURCE "$mountpoint" 2>/dev/null)
    else
        set device "/dev/$target"
        set mountpoint (_disk_get_mountpoint $device)
    end

    if test -z "$mountpoint"
        _disk_error "Диск не примонтирован"
        return 1
    end

    # Получаем информацию
    set -l fstype (_disk_get_fstype $device)
    set -l owner (stat -c %U:%G "$mountpoint" 2>/dev/null)
    set -l perms (stat -c %a "$mountpoint" 2>/dev/null)

    echo ""
    echo "Диагностика $mountpoint:"
    echo "  Устройство: $device"
    echo "  ФС: $fstype"
    echo "  Владелец: $owner"
    echo "  Права: $perms"
    echo ""

    # Проверяем права
    set -l needs_fix no

    if test "$owner" != "$USER:$USER"
        echo "Проблема: владелец должен быть $USER:$USER"
        set needs_fix yes
    end

    if test $needs_fix = no
        _disk_success "Проблем не обнаружено!"
        return 0
    end

    # Предлагаем исправить
    echo ""
    echo "Исправить права доступа? [Y/n]"
    read -l fix_choice

    if test "$fix_choice" = "n" -o "$fix_choice" = "N"
        echo "Отменено"
        return 0
    end

    # Исправляем
    echo "Исправляю права..."

    if string match -q -r "ext[234]|btrfs|xfs" $fstype
        sudo chown -R $USER:$USER "$mountpoint"
        sudo chmod 755 "$mountpoint"
    end

    _disk_success "Права исправлены!"

    return 0
end

# ============================================
# ГЛАВНАЯ ФУНКЦИЯ
# ============================================

function disk --description "Управление дисками - добавление, монтирование, форматирование"
    # Проверка зависимостей при первом запуске
    if not _disk_check_dependencies
        return 1
    end

    # Парсинг аргументов
    set -l command $argv[1]
    set -l args $argv[2..-1]

    # Если нет команды - показываем help
    if test -z "$command"
        _disk_show_help
        return 0
    end

    # Маршрутизация команд
    switch $command
        case list ls
            _disk_cmd_list $args
        case mount m
            _disk_cmd_mount $args
        case unmount umount eject
            _disk_cmd_unmount $args
        case auto
            _disk_cmd_auto $args
        case setup add format
            _disk_cmd_setup $args
        case fix repair
            _disk_cmd_fix $args
        case help -h --help
            _disk_show_help
        case version -v --version
            echo "fishDisk v0.1.0"
        case '*'
            _disk_error "Неизвестная команда: $command"
            echo ""
            _disk_show_help
            return 1
    end
end
