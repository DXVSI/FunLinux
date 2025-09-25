# ✂️ sel2clip

Автоматическое копирование выделенного текста в буфер обмена для Wayland (KDE Plasma).

## Что это?

sel2clip — утилита для автоматического копирования выделенного мышкой текста в системный буфер обмена. Работает в Wayland окружении с KDE Plasma, используя `wl-paste` и `wl-copy`.

## Особенности

- ⏱️ **Дебаунсинг** — пауза после выделения перед копированием (по умолчанию 300мс)
- 🔒 **Защита от дублей** — минимальный интервал между копиями (900мс)
- 📏 **Лимит размера** — максимум 256КБ текста
- 🎯 **Только текст** — работает только с текстовым содержимым
- 📝 **Логирование** — опциональное логирование операций

## Параметры

```bash
./sel2clip [DELAY_MS] [MIN_INTERVAL_MS] [MAX_BYTES]
```

- `DELAY_MS` — пауза после выделения (по умолчанию 300мс)
- `MIN_INTERVAL_MS` — минимальный интервал между копиями (по умолчанию 900мс)
- `MAX_BYTES` — максимальный размер текста (по умолчанию 262144 байт)

## Автозапуск через systemd

Создайте пользовательский сервис:

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/sel2clip.service <<'UNIT'
[Unit]
Description=Debounced selection → clipboard (plain text only)

[Service]
ExecStart=%h/.local/bin/sel2clip 300
Restart=always

[Install]
WantedBy=default.target
UNIT

systemctl --user daemon-reload
systemctl --user enable --now sel2clip.service
```

## Установка

1. Скопируйте `sel2clip` в `~/.local/bin/`
2. Сделайте исполняемым: `chmod +x ~/.local/bin/sel2clip`
3. Настройте автозапуск через systemd (см. выше)

## Требования

- Wayland с KDE Plasma
- `wl-paste` и `wl-copy` (пакет `wl-clipboard`)
- bash