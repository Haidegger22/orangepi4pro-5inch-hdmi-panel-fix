# Orange Pi 4 Pro — фикс 5" HDMI-панели 1024x600

Готовая настройка для Orange Pi 4 Pro, чтобы маленький HDMI-экран **не гас после
загрузки** и всегда стартовал в своём родном разрешении.

Проверено на реальной плате и реальной панели, не теория.

## Железо и система

| Что | Значение |
|---|---|
| Плата | Orange Pi 4 Pro, SoC Allwinner A733 (`sun60iw2`), 12 ГБ |
| ОС | Debian 13 Trixie, образ Orange Pi 1.1.0 |
| Ядро | `6.6.98-sun60iw2` |
| Графика | Xorg (modesetting) + XFCE, сессия X11 |
| Экран | 5" IPS 1024x600, HDMI, ёмкостный тач |
| Идентификация | USB `0484:5750` QDtech MPI5001; EDID — MPI5006 |
| Питание экрана | USB Type-C, 5 В |

Панель подключается **только по HDMI** — разъёма DSI у 4 Pro в системе нет вообще
(`/sys/class/drm` содержит лишь `card0-HDMI-A-1`). Тач приходит отдельным USB-HID.
Своей регулировки яркости в sysfs нет (`/sys/class/backlight` пуст) — яркость живёт
в самой панели.

## Симптом

После загрузки рабочий стол появляется на несколько секунд и экран гаснет. Дальше
не будится ни мышью, ни клавиатурой — при этом плата жива, по SSH отвечает, X
считает выход исправным. Если вручную переключить выход — картинка возвращается
до следующей перезагрузки.

Часто этому предшествует «лечение» разрешения через `cvt`:

```bash
xrandr --newmode "1024x600_60.00" 49.00 1024 1064 1168 1312 600 601 604 622 -HSync +VSync
```

Такой режим **неверный**: у панели паспортная частота пикселей 50.000 МГц, а не 49.00.

## Причина (по журналу ядра)

Панель сама сообщает свои параметры в EDID:

```
50.00 1024 1032 1042 1204 600 603 609 625 -hsync +vsync
```

Это 1024x600 при частоте пикселей 50.000 МГц, строчной 41.5 кГц и кадровой 66.45 Гц.
Режим из `cvt` даёт 49.00 МГц и строчную 37.3 кГц — не совпадает, поэтому картинка
«ловится» и срывается. В журнале ядра это видно прямой строкой:

```
sunxi-hdmi: [warn] snps phy check clk: 49000Hz is match in [44900Hz-49500Hz] and change use: 49500Hz
```

Дальше работает вторая проблема — порядок режимов при загрузке:

```
1.9 с      ядро ставит 1920x1080 (первый режим из EDID)
3.3 с      после переподключения линии — снова 1920x1080
9.5 с      X переключается на 1024x600
10.2 с     панель перестраивается и на ~0.3 с роняет линию HPD
           (hpd disconnect -> hpd connect)
после возврата линии драйвер режим НЕ переставляет — экран остаётся чёрным
```

То есть панель получает чужой режим, потом правильный, на смене дёргает линию —
и остаётся ни с чем.

## Что делает этот репозиторий

1. **`files/20-modesetting.conf`** — в секцию `Monitor "Default Monitor"` добавлены
   `Modeline` с паспортным режимом и `Option "PreferredMode"`. Теперь X стартует
   сразу в 1024x600, не показывая панели 1920x1080. Признак в `/var/log/Xorg.0.log`:
   `Using user preference for initial modes` и
   `Output HDMI-1 using initial mode panel_1024x600`.
2. **`files/set-display-1024x600.sh`** — страховка на случай, если режим всё же
   сбился: ставит паспортный режим, убирает ошибочный `1024x600_60.00` из списка
   и выключает гашение (`xset s off`, `-dpms`, `s noblank`).
3. **`files/hdmi-panel-watch.sh` + `systemd/hdmi-panel-watch.service`** — сторож
   линии HPD, работает **системной службой от root**. Логика:
   - при старте читает **журнал ядра** и смотрит, был ли `hpd disconnect` после
     последнего `mode set: 1024*600`. Если был — панель уже потеряла линию, сторож
     один раз будит её переключением `--off` → `--mode`;
   - если обрыва не было — выход **не трогает вообще** (профилактическое
     переключение при живой панели само вызывает обрыв и гасит экран);
   - дальше опрашивает `/sys/class/drm/card0-HDMI-A-1/status` каждые 0.3 с (обрыв
     длится ~0.3 с, редкий опрос его не видит) и реагирует только на реальную
     потерю линии, не чаще раза в минуту.

   Почему служба, а не автозапуск в сеансе: у пользователя `kernel.dmesg_restrict=1`
   (журнал ядра закрыт), а автозапуск сеанса поднимается **позже** обрыва — обрыв на
   10-й секунде, сеанс стартует около 11-й, и событие пропускается.
4. **`autostart/display-1024x600.desktop`** — автозапуск скрипта режима в сессии XFCE.
5. **`tools/panel-diag.sh`** — диагностика «что видит система»: разъёмы, режимы,
   EDID, журнал HPD, служба, тач. Ничего не меняет.

### Почему не задать режим параметром ядра

Пробовали, на этой плате не работает:

- `video=HDMI-A-1:D` ядро понимает не как «взять режим из EDID», а как тип выхода:
  в журнале появляется `mode set: 1024*768`, потом снова 1920x1080;
- режим `1024x600@66` из командной строки не выбрать: родной режим панели
  **отсутствует в списке режимов ядра** — вендорный разбор EDID в `sunxi-hdmi`
  отбрасывает этот DTD (`unsupport parser desc type`). В
  `/sys/class/drm/card0-HDMI-A-1/modes` только 1920x1080, 1280x1024, 1440x900
  и 1280x720.

Xorg разбирает тот же EDID сам и видит правильный режим — поэтому настройка живёт
на уровне X, а не в командной строке ядра.

## Тач и мультитач

Тач панели — отдельное USB-HID устройство `0484:5750`. В ядре `6.6.98-sun60iw2`
выключен `CONFIG_HID_MULTITOUCH`, поэтому без модуля касания отдают мусорные
координаты (все — в правый нижний угол, курсор не двигается), хотя в журнале
устройство выглядит исправным.

Модуль собран и проверен на этой плате; полный рецепт без заголовков ядра —
**[docs/hid-multitouch-4pro.md](docs/hid-multitouch-4pro.md)**. Кратко: клонировать
вендорную ветку `orange-pi-6.6-sun60iw2`, сгенерировать `Module.symvers` из
`/proc/kallsyms` (формат 6.6 — пять полей с завершающим табом), добавить в
`mt_devices[]` строку `HID_USB_DEVICE(0x0484, 0x5750)` (готовый патч лежит в
`patches/`), собрать `hid-multitouch.ko` и прописать автозагрузку.

Признак успеха — в возможностях устройства появляются `ABS_MT_POSITION_X/Y`,
`ABS_MT_SLOT` и `ABS_MT_TRACKING_ID`: `cat /sys/class/input/event6/device/capabilities/abs`
показывает `273800000000003` вместо `10000000003`.


## Установка

Полная пошаговая инструкция с готовыми блоками для копирования (включая полный код
каждого файла, если git недоступен): **[INSTALL.md](INSTALL.md)**.

Короткий путь:

```bash
git clone https://github.com/Haidegger22/orangepi4pro-5inch-hdmi-panel-fix.git
cd orangepi4pro-5inch-hdmi-panel-fix

sudo cp -a /etc/X11/xorg.conf.d/20-modesetting.conf \
           /etc/X11/xorg.conf.d/20-modesetting.conf.bak-$(date +%Y%m%d)
sudo install -m 0664 files/20-modesetting.conf /etc/X11/xorg.conf.d/20-modesetting.conf

install -d ~/.local/bin ~/.config/autostart
install -m 0755 files/set-display-1024x600.sh ~/.local/bin/
install -m 0644 autostart/display-1024x600.desktop ~/.config/autostart/

sudo install -m 0755 files/hdmi-panel-watch.sh /usr/local/bin/hdmi-panel-watch.sh
sudo install -m 0644 systemd/hdmi-panel-watch.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hdmi-panel-watch

sudo systemctl restart lightdm
```

## Проверка

```bash
bash tools/panel-diag.sh
systemctl is-enabled hdmi-panel-watch; systemctl is-active hdmi-panel-watch
```

Что должно быть видно:

- `HDMI-1 connected 1024x600+0+0`;
- `panel_1024x600 66.45*+` в списке режимов;
- в журнале ядра `pixel clock 50000KHz` и `snps phy state: lock`;
- после 13-й секунды загрузки — ни одного нового `hpd disconnect`;
- служба `hdmi-panel-watch` в состоянии `enabled` / `active`.

## Ограничения

- **Сенсор.** Мультитач требует модуля `hid-multitouch`, которого нет в ядре
  (`CONFIG_HID_MULTITOUCH is not set`). Для этой панели модуль уже собран и проверен,
  рецепт — [docs/hid-multitouch-4pro.md](docs/hid-multitouch-4pro.md).
- **Кабель и питание тут ни при чём.** Проверено: с исправным кабелем EDID читается
  полностью, перестановка USB-C с порта USB 2.0 на USB 3.0 картину не меняет.
  Не доверяйте `stat -c %s /sys/class/drm/card0-HDMI-A-1/edid` — для sysfs-атрибута
  он всегда равен 0; читайте сам файл (`od -An -tx1`).
- **Другой экран — другие цифры.** Возьмите моделайн из EDID своей панели:
  `DISPLAY=:0 xrandr --verbose` (раздел EDID) либо `/var/log/Xorg.0.log`
  (`Modeline "..."x0.0 ... (DDC gathered)`).
- **Только X11.** При Wayland (Weston/labwc) на `sun60iw2` KMS-коммит не работает,
  `xrandr` не применяется — способ не подойдёт.

## Откат

```bash
sudo cp -a $(ls -t /etc/X11/xorg.conf.d/20-modesetting.conf.bak-* | head -1) \
           /etc/X11/xorg.conf.d/20-modesetting.conf
sudo systemctl disable --now hdmi-panel-watch
sudo rm -f /usr/local/bin/hdmi-panel-watch.sh /etc/systemd/system/hdmi-panel-watch.service
sudo systemctl daemon-reload
rm -f ~/.local/bin/set-display-1024x600.sh ~/.config/autostart/display-1024x600.desktop
sudo systemctl restart lightdm
```

## Лицензия

MIT — см. [LICENSE](LICENSE).
