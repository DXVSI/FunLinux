function bios --description 'Перезагрузка сразу в BIOS/UEFI Setup'
    if systemctl reboot --firmware-setup
        echo "Перезагружаюсь в BIOS..."
    else
        echo "❌ Ошибка: не удалось вызвать BIOS/UEFI Setup."
    end
end
