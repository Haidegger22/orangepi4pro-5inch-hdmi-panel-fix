# Orange Pi 4 Pro — фикс 5" HDMI-панели 1024×600

Готовая настройка для Orange Pi 4 Pro, чтобы маленький HDMI-экран **не гас после
загрузки** и всегда стартовал в родном разрешении 1024×600.

Проверено на реальной плате и панели QDtech MPI5001 (EDID сообщает MPI5006).

## Железо и система

| Что | Значение |
|---|---|
| Плата | Orange Pi 4 Pro, Allwinner A733 (`sun60iw2`) |
| ОС | Debian 13 Trixie, образ Orange Pi 1.1.0 |
| Ядро | `6.6.98-sun60iw2` |
| Графика | Xorg (modesetting), X11 |
| Экран | 5" IPS 1024×600, HDMI, ёмкостный тач |
| Тач | USB `0484:5750`, QDtech MPI5001 |
| EDID | MPI5006, 128 байт, DTD 1024×600, 50.000 МГц |

Панель подключена только по HDMI; тач приходит отдельным USB-HID. Своей
регулировки яркости в sysfs нет (`/sys/class/backlight` пуст) — яркость живёт
в самой панели.

## Симптом

После загрузки рабочий стол появляется на 1–2 секунды и экран гаснет. Плата жива,
SSH отвечает, `xrandr` показывает активный режим и `connected`, но физически
выход выключен. Иногда помогает ручное `xrandr --output HDMI-1 --off`, пауза и
`--mode panel_1024x600`, но не всегда.

## Причина

1. Панель отдаёт EDID с режимом **1024×600, 50.000 МГц, 66.45 Гц**
   (строчная 41.5 кГц, DTD `50.00 1024 1032 1042 1204 600 603 609 625`).
2. Вендорный драйвер `sunxi-hdmi` в `_sunxi_drm_hdmi_mode_valid()` отбрасывает
   режимы с частотой **выше 60 Гц** (`rate > 60 → MODE_BAD`). Поэтому в
   `/sys/class/drm/card0-HDMI-A-1/modes` нет 1024×600, и ядро при загрузке
   выбирает первый доступный режим — обычно **1920×1080**.
3. X позже ставит 1024×600 своим modeline. Панель в этот момент дёргает HPD:
   `disconnect` → `connect`.
4. На `hpd disconnect` драйвер вызывает `_sunxi_drv_hdmi_hpd_plugout()`:
   выключает HDMI и очищает `drm_mode_set`. На `hpd connect`
   `_sunxi_drv_hdmi_hpd_plugin()` только заново читает EDID — режим обратно не
   включает. X считает выход активным, но физически он уже выключен.
5. `off → mode` иногда помогает, потому что пересобирает CRTC. Но это гонка:
   если панель снова дёрнет HPD после mode set или сторож не поймал короткий
   обрыв, экран остаётся чёрным.

`de 1 not enable, skip` в журнале — не причина. Это второй DE-путь; основной
CRTC работает через DE0.

Режим из `cvt` (`49.00 МГц`, 60 Гц) тоже неверный: у панели 50.000 МГц и 66.45 Гц,
поэтому старые советы с `1024x600_60.00` из репозитория убраны.

## Решение: штатные DT-свойства драйвера

В узел `hdmi0@5520000` добавляются два свойства:

```dts
force-output = <1>;
force-output-timing = "50000-1024-1032-1042-1204-600-603-609-625";
```

`force-output-timing` задаёт режим в формате
`clock-hdisplay-hsync_start-hsync_end-htotal-vdisplay-vsync_start-vsync_end-vtotal`
(clock в кГц). Драйвер добавляет этот режим и обходит фильтр `>60 Гц`.

Ядро ставит **1024×600@66.45** ещё на ~1.9 с, до старта X. Переключения
1920×1080 → 1024×600 и HPD-обрыва после него больше нет.

Важно: **ядро пересобирать не нужно**, правится только DTB.

## Что в репозитории

- `files/20-modesetting.conf` — Xorg modeline и `PreferredMode` как страховка
  для X-сессии.
- `files/set-display-1024x600.sh` — необязательный скрипт ручной установки
  режима (если X всё же стартовал не в нём).
- `autostart/display-1024x600.desktop` — необязательный автозапуск скрипта.
- `tools/panel-diag.sh` — диагностика: DTB-свойства, режимы, HPD, X, тач.
- `tools/apply-dtb-force-output.sh` — повторно применить DTB-свойства после
  обновления системы (с бэкапом).
- `docs/dtb-force-output.md` — подробный разбор и команды.
- `docs/hid-multitouch-4pro.md` — модуль мультитача.
- `patches/` — патч `hid-multitouch` для QDtech MPI5001.

Сторож `hdmi-panel-watch` и разовая побудка `panel-wake-once` **удалены**:
это были обходные пути для старого поведения. Если они уже установлены на
плате — отключите и удалите их (команды в `INSTALL.md`).

## Установка

Кратко:

```bash
git clone https://github.com/Haidegger22/orangepi4pro-5inch-hdmi-panel-fix.git
cd orangepi4pro-5inch-hdmi-panel-fix
```

Затем:

1. Сделать бэкап DTB.
2. Добавить `force-output` и `force-output-timing`.
3. Установить `files/20-modesetting.conf`.
4. Перезагрузиться.

Полные команды — в **[INSTALL.md](INSTALL.md)**.

## Проверка

```bash
sudo fdtget -t i /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb \
    /soc@3000000/hdmi0@5520000 force-output
sudo fdtget -t s /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb \
    /soc@3000000/hdmi0@5520000 force-output-timing
sudo dmesg | grep -E 'Configuration mode|mode set:|hpd (dis)?connect'
DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority xrandr --query | head -3
```

Ожидается:

- `force-output` = `1`;
- тайминг `50000-1024-1032-1042-1204-600-603-609-625`;
- в журнале `Configuration mode 1024x600@66Hz` и **нет** `hpd disconnect`
  после загрузки;
- `HDMI-1 connected primary 1024x600+0+0`;
- `panel_1024x600 50.000MHz ... 66.45*+`.

## Откат

Вернуть DTB из бэкапа, созданного при установке:

```bash
sudo cp -a /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb.bak-force-* \
           /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb
sync
sudo reboot
```

## Ограничения

- Проверено на Xorg/X11. Для Wayland на `sun60iw2` KMS-коммит может не
  проходить; это отдельная история.
- Обновление ядра/DTB может заменить файл и потерять свойства. После такого
  обновления их нужно добавить снова (команды в `INSTALL.md`).
- Моделайн панели — **50.000 МГц, 66.45 Гц**. Не заменяйте его на `cvt`-режим
  49.00 МГц / 60 Гц: панель его не держит.
- `stat -c %s` на sysfs-EDID всегда даёт 0; читайте сам файл через `od`.

## Тач и мультитач

В ядре `6.6.98-sun60iw2` выключен `CONFIG_HID_MULTITOUCH`, поэтому без модуля
касания работают неправильно. Модуль собран и проверен; полный рецепт —
**[docs/hid-multitouch-4pro.md](docs/hid-multitouch-4pro.md)**, готовый патч —
`patches/hid-multitouch-add-qdtech-mpi5001.patch`.

## Лицензия

MIT — см. [LICENSE](LICENSE).
