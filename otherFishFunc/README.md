# otherFishFunc

Различные полезные функции для Fish Shell, которые не вошли в другие категории.

## Функции

### bios

Быстрая перезагрузка в BIOS/UEFI Setup.

**Использование:**
```bash
bios
```

**Что делает:**
- Использует `systemctl reboot --firmware-setup`
- Перезагружает систему напрямую в настройки BIOS/UEFI
- Работает на системах с UEFI

### upd

Короткий алиас для обновления системы через dnf5.

**Использование:**
```bash
# Обновить все пакеты
upd

# Обновить конкретные пакеты
upd firefox chromium
```

**Эквивалентно:**
```bash
sudo dnf5 update -y [пакеты]
```

## Установка

```bash
# Скопировать функции в директорию Fish
cp otherFishFunc/*.fish ~/.config/fish/functions/

# Перезагрузить Fish
exec fish
```

## Примеры

```bash
# Быстрая перезагрузка в BIOS
bios

# Обновить систему
upd

# Обновить конкретный пакет
upd kernel
```

## Совместимость

- **bios**: Требует systemd и UEFI
- **upd**: Требует dnf5 (Fedora 41+)

## Лицензия

Open source. Используй свободно.

## Автор

DXVSI
