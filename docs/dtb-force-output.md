# DTB: принудительный режим HDMI для панели 1024×600

Почему панель гаснет и как это лечится штатными свойствами драйвера
`sunxi-hdmi`, без пересборки ядра.

## Дано

- Orange Pi 4 Pro, Allwinner A733 (`sun60iw2`), Debian 13.
- Ядро `6.6.98-sun60iw2`, драйвер `sunxi-hdmi` встроен в ядро.
- Панель QDtech MPI5001 (EDID MPI5006), 5", 1024×600, HDMI.
- EDID: DTD `50.00 1024 1032 1042 1204 600 603 609 625 -hsync +vsync`,
  то есть 50.000 МГц, 66.45 Гц.

## Что происходит

1. `_sunxi_drm_hdmi_mode_valid()` в `bsp/drivers/drm/sunxi_drm_hdmi.c`
   возвращает `MODE_BAD` для режимов с `rate > 60`. Родной режим 66.45 Гц
   отбрасывается, в `/sys/class/drm/card0-HDMI-A-1/modes` его нет.
2. Ядро при загрузке ставит первый доступный режим — обычно 1920×1080.
3. X стартует и ставит 1024×600 своим modeline. Панель на смене режима
   роняет HPD: `disconnect` → `connect` (~0.3 с).
4. На `hpd disconnect` драйвер вызывает `_sunxi_drv_hdmi_hpd_plugout()`:
   выключает HDMI и очищает `drm_mode_set`. На `hpd connect`
   `_sunxi_drv_hdmi_hpd_plugin()` только перечитывает EDID; режим не
   восстанавливает.
5. X продолжает считать выход активным, но физически он выключен. Отсюда
   чёрный экран при `xrandr` с активным режимом.

`sunxi_de_atomic_flush de 1 not enable, skip` — не причина. Это второй
display engine; основной CRTC работает через DE0.

## Решение

В DTB, в узел `hdmi0@5520000`, добавляются два свойства:

```dts
force-output = <1>;
force-output-timing = "50000-1024-1032-1042-1204-600-603-609-625";
```

Разбор строки:

| Поле | Значение |
|---|---|
| clock | 50000 кГц (50.000 МГц) |
| hdisplay | 1024 |
| hsync_start | 1032 |
| hsync_end | 1042 |
| htotal | 1204 |
| vdisplay | 600 |
| vsync_start | 603 |
| vsync_end | 609 |
| vtotal | 625 |

Драйвер в `sunxi_drm_hdmi.c` видит `force-output`, добавляет этот режим в
список и в `mode_valid` пропускает его без проверки `>60 Гц`. Ядро ставит
1024×600@66.45 на ~1.9 с, до старта X. Переключения с 1920×1080 и HPD-обрыва
после него нет.

## Команды

```bash
sudo cp -a /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb \
           /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb.bak-force-$(date +%Y%m%d-%H%M)

sudo fdtput -t i /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb \
    /soc@3000000/hdmi0@5520000 force-output 1

sudo fdtput -t s /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb \
    /soc@3000000/hdmi0@5520000 force-output-timing \
    "50000-1024-1032-1042-1204-600-603-609-625"

sync
sudo reboot
```

Проверка:

```bash
sudo fdtget -t i /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb \
    /soc@3000000/hdmi0@5520000 force-output
sudo fdtget -t s /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb \
    /soc@3000000/hdmi0@5520000 force-output-timing

sudo dmesg | grep -E 'Configuration mode|mode set:|hpd (dis)?connect'
DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority xrandr --query | head -3
```

Ожидается `Configuration mode 1024x600@66Hz`, отсутствие `hpd disconnect`
после загрузки и `HDMI-1 connected primary 1024x600+0+0`.

## Откат

```bash
sudo cp -a $(ls -t /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb.bak-force-* | head -1) \
           /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb
sync
sudo reboot
```

## Почему не другие способы

- **`video=HDMI-A-1:...`** — режим всё равно проходит через `mode_valid` и
  отбрасывается; кроме того, `video=HDMI-A-1:D` на этой плате трактуется как
  тип выхода и даёт 1024×768.
- **EDID override через debugfs** — подменяет EDID, но не отменяет фильтр
  `>60 Гц` и не восстанавливает режим после HPD.
- **`force HPD` через debugfs** — меняет только состояние detect; режим не
  переставляется.
- **`unbind/rebind sunxi-drm`** — может вернуть картинку, но рвёт X-сессию;
  не годится как штатное решение.
- **Сторож `hdmi-panel-watch`** — лечит следствие (`off → mode`) и зависит от
  гонки с коротким HPD-импульсом; с DTB-режимом не нужен.

## Ограничения

- Проверено на Xorg/X11; Wayland на `sun60iw2` — отдельная история.
- Обновление ядра/DTB может заменить файл; свойства нужно добавить снова.
- Панель держит только 50.000 МГц / 66.45 Гц. `cvt`-режим 49.00 МГц / 60 Гц
  не использовать.
