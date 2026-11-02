# Установка — Orange Pi 4 Pro, 5" HDMI-панель 1024×600

Пошагово, блоками для копирования в терминал. Проверено на Debian 13 Trixie,
ядро `6.6.98-sun60iw2`, Xorg + X11.

Главное отличие от старой версии: режим задаётся **в DTB** штатными свойствами
драйвера `sunxi-hdmi`, а не сторожем HPD. Ядро пересобирать не нужно.

---

## Шаг 0. Проверить плату и панель

```bash
uname -r
ls /sys/class/drm/
cat /sys/class/drm/card0-HDMI-A-1/status
od -An -tx1 /sys/class/drm/card0-HDMI-A-1/edid | head -4
```

Ожидается: ядро `6.6.98-sun60iw2`, разъём `card0-HDMI-A-1`, статус `connected`,
EDID начинается с `00 ff ff ff ff ff ff 00`.

Если статус `disconnected` — сначала проверьте кабель и питание панели.

---

## Шаг 1. Зависимости

```bash
sudo apt update
sudo apt install -y x11-xserver-utils x11-utils git device-tree-compiler
```

`xrandr` входит в `x11-xserver-utils`, `fdtput`/`fdtget` — в
`device-tree-compiler`.

---

## Шаг 2. Забрать репозиторий

```bash
git clone https://github.com/Haidegger22/orangepi4pro-5inch-hdmi-panel-fix.git
cd orangepi4pro-5inch-hdmi-panel-fix
```

---

## Шаг 3. Добавить режим в DTB

Сначала бэкап. Имя с датой, чтобы потом было понятно, что откатывать:

```bash
sudo cp -a /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb \
           /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb.bak-force-$(date +%Y%m%d-%H%M)
```

Добавить два свойства в узел HDMI:

```bash
sudo fdtput -t i /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb \
    /soc@3000000/hdmi0@5520000 force-output 1

sudo fdtput -t s /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb \
    /soc@3000000/hdmi0@5520000 force-output-timing \
    "50000-1024-1032-1042-1204-600-603-609-625"

sync
```

То же самое одной командой (создаёт бэкап и проверяет запись):

```bash
sudo tools/apply-dtb-force-output.sh
```

Проверить, что записалось:

```bash
sudo fdtget -t i /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb \
    /soc@3000000/hdmi0@5520000 force-output
sudo fdtget -t s /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb \
    /soc@3000000/hdmi0@5520000 force-output-timing
```

Должно быть `1` и `50000-1024-1032-1042-1204-600-603-609-625`.

> `force-output-timing` — формат
> `clock-hdisplay-hsync_start-hsync_end-htotal-vdisplay-vsync_start-vsync_end-vtotal`,
> clock в кГц. Это паспортный режим панели из EDID: 50.000 МГц, 1024×600,
> 66.45 Гц.

---

## Шаг 4. Конфиг Xorg

Xorg получает тот же режим через modeline — это страховка для X-сессии.

```bash
sudo cp -a /etc/X11/xorg.conf.d/20-modesetting.conf \
           /etc/X11/xorg.conf.d/20-modesetting.conf.bak-$(date +%Y%m%d-%H%M)

sudo install -m 0664 files/20-modesetting.conf \
    /etc/X11/xorg.conf.d/20-modesetting.conf
```

Если в вашем файле уже есть свои правки, не заменяйте его целиком: добавьте в
секцию `Monitor "Default Monitor"` только две строки:

```text
    Modeline "panel_1024x600" 50.00 1024 1032 1042 1204 600 603 609 625 -HSync +VSync
    Option   "PreferredMode" "panel_1024x600"
```

Проверить синтаксис:

```bash
Xorg -config /etc/X11/xorg.conf.d/20-modesetting.conf -showopts 2>&1 | tail -5
```

`Server is already active` — нормально, конфиг прочитан. Ошибок `Parse error`
быть не должно.

---

## Шаг 5. Необязательный скрипт режима

Он нужен только как ручная страховка, если X почему-то стартовал не в 1024×600.
Для штатной работы достаточно DTB и Xorg-конфига.

```bash
install -d ~/.local/bin ~/.config/autostart
install -m 0755 files/set-display-1024x600.sh ~/.local/bin/
install -m 0644 autostart/display-1024x600.desktop ~/.config/autostart/
```

Проверить имя выхода:

```bash
grep -n 'HDMI-1' ~/.local/bin/set-display-1024x600.sh
```

На 4 Pro выход называется `HDMI-1`.

---

## Шаг 6. Убрать старые обходные пути

Если раньше ставили сторож или разовую побудку — отключить и удалить. С
DTB-режимом они не нужны и могут сами вызвать `off → mode`.

```bash
sudo systemctl disable --now hdmi-panel-watch panel-wake-once 2>/dev/null || true

sudo rm -f /usr/local/bin/hdmi-panel-watch.sh \
           /usr/local/bin/panel-wake-once.sh \
           /etc/systemd/system/hdmi-panel-watch.service \
           /etc/systemd/system/panel-wake-once.service

sudo systemctl daemon-reload
```

Если остался автозапуск старого сторожа в сеансе:

```bash
rm -f ~/.config/autostart/hdmi-panel-watch.desktop
pkill -f "$HOME/.local/bin/hdmi-panel-watch.sh" 2>/dev/null || true
```

---

## Шаг 7. Перезагрузка

```bash
sudo reboot
```

Именно полная перезагрузка, а не только `systemctl restart lightdm`: DTB
читается при старте ядра.

---

## Шаг 8. Проверка

```bash
sudo fdtget -t i /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb \
    /soc@3000000/hdmi0@5520000 force-output
sudo fdtget -t s /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb \
    /soc@3000000/hdmi0@5520000 force-output-timing

sudo dmesg | grep -E 'Configuration mode|mode set:|hpd (dis)?connect'
DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority xrandr --query | head -3
```

Что должно быть:

- `force-output` = `1`;
- тайминг `50000-1024-1032-1042-1204-600-603-609-625`;
- `Configuration mode 1024x600@66Hz`;
- **ни одного `hpd disconnect`** после загрузки;
- `HDMI-1 connected primary 1024x600+0+0`;
- `panel_1024x600 50.000MHz ... 66.45*+`.

Полная диагностика одной командой:

```bash
bash tools/panel-diag.sh
```

---

## Шаг 9 (по желанию). Мультитач тачскрина

В ядре выключен `CONFIG_HID_MULTITOUCH`, поэтому без модуля касания работают
неправильно. Модуль собран и проверен; полный рецепт —
**[docs/hid-multitouch-4pro.md](docs/hid-multitouch-4pro.md)**, готовый патч —
`patches/hid-multitouch-add-qdtech-mpi5001.patch`.

Коротко: собрать `hid-multitouch.ko` из вендорной ветки
`orange-pi-6.6-sun60iw2`, положить в `/lib/modules/$(uname -r)/kernel/drivers/hid/`,
выполнить `depmod -a` и прописать `hid-multitouch` в
`/etc/modules-load.d/hid-multitouch.conf`.

Проверка:

```bash
lsmod | grep hid_multitouch
ls /sys/bus/hid/drivers/hid-multitouch/
cat /sys/class/input/event6/device/capabilities/abs   # ожидается 273800000000003
```

---

## Откат

Вернуть DTB и Xorg-конфиг из бэкапов:

```bash
sudo cp -a $(ls -t /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb.bak-force-* | head -1) \
           /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb

sudo cp -a $(ls -t /etc/X11/xorg.conf.d/20-modesetting.conf.bak-* | head -1) \
           /etc/X11/xorg.conf.d/20-modesetting.conf

rm -f ~/.local/bin/set-display-1024x600.sh \
      ~/.config/autostart/display-1024x600.desktop

sync
sudo reboot
```

---

## Важно

- **Ядро не пересобирается.** Меняется только DTB.
- **Обновление системы может заменить DTB.** После обновления ядра/DTB
  проверьте `force-output` и при необходимости добавьте свойства снова.
- **Не используйте `cvt` 49.00 МГц / 60 Гц.** Панель держит только 50.000 МГц,
  66.45 Гц.
- **Не включайте `off → mode` профилактически.** Если панель жива, это само
  вызывает обрыв HPD.
- **Только X11 (Xorg).** На Wayland KMS-коммит на `sun60iw2` может не проходить;
  это отдельная задача.
- `stat -c %s` на sysfs-EDID всегда даёт 0 — читайте сам файл через `od`.
