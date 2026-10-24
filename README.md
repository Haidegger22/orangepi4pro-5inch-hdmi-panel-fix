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
1.8-6.1 с  ядро ставит 1920x1080 (первый режим из EDID)
9.7 с      X переключается на 1024x600
10.4 с     панель перестраивается и на ~0.3 с роняет линию HPD
           (hpd disconnect -> hpd connect)
после возврата линии драйвер режим не переставляет — экран остаётся чёрным
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
3. **`files/hdmi-panel-watch.sh`** — сторож линии HPD. Опрашивает
   `/sys/class/drm/card0-HDMI-A-1/status` каждые 0.3 с (обрыв длится ~0.3 с, редкий
   опрос его не видит) и один раз переустанавливает режим после старта сеанса.
   **Ровно один раз:** два переключения подряд панель не переживает — после второго
   она снова роняет линию и больше не поднимается. Это и есть тот самый симптом
   «стол появился и снова исчез».
4. **`autostart/*.desktop`** — автозапуск обоих скриптов в сессии XFCE.
5. **`tools/panel-diag.sh`** — диагностика «что видит система»: разъёмы, режимы,
   EDID, журнал HPD, процессы, тач. Ничего не меняет.

## Установка

Полная пошаговая инструкция с готовыми блоками для копирования (включая полный код
каждого файла, если git недоступен): **[INSTALL.md](INSTALL.md)**.

Короткий путь:

```bash
git clone https://github.com/Haidegger22/orangepi4pro-5inch-hdmi-panel-fix.git
cd orangepi4pro-5inch-hdmi-panel-fix
sudo cp -a /etc/X11/xorg.conf.d/20-modesetting.conf /etc/X11/xorg.conf.d/20-modesetting.conf.bak-$(date +%Y%m%d)
sudo install -m 0664 files/20-modesetting.conf /etc/X11/xorg.conf.d/20-modesetting.conf
install -d ~/.local/bin ~/.config/autostart
install -m 0755 files/set-display-1024x600.sh files/hdmi-panel-watch.sh ~/.local/bin/
cp autostart/*.desktop ~/.config/autostart/
sudo systemctl restart lightdm
```

## Проверка

```bash
bash tools/panel-diag.sh
```

Что должно быть видно:

- `HDMI-1 connected 1024x600+0+0`;
- `panel_1024x600 66.45*+` в списке режимов;
- в журнале ядра `pixel clock 50000KHz` и `snps phy state: lock`;
- после 20-й секунды загрузки — ни одного `hpd disconnect`;
- процессы `hdmi-panel-watch` и `set-display-1024x600` живы.

## Ограничения

- **Сенсор.** Тач определяется как USB-HID, но в ядре `6.6.98-sun60iw2` выключен
  `CONFIG_HID_MULTITOUCH`, поэтому мультитач не работает. Сборка модуля —
  отдельный репозиторий: [opi-zero3w-hid-multitouch-fix](https://github.com/Haidegger22/opi-zero3w-hid-multitouch-fix)
  (тот же тач `0484:5750`, то же ядро).
- **Кабель и питание тут ни при чём.** Проверено: с исправным кабелем EDID читается
  полностью, перестановка USB-C с порта USB 2.0 на USB 3.0 картину не меняет.
  Не доверяйте `stat -c %s /sys/class/drm/card0-HDMI-A-1/edid` — для sysfs-атрибута
  он всегда равен 0; читайте сам файл (`od -An -tx1`).
- **Другой экран — другие цифры.** Возьмите моделайн из EDID своей панели:
  `DISPLAY=:0 xrandr --verbose | grep -A2 EDID` либо `/var/log/Xorg.0.log`
  (`Modeline "..."x0.0 ... (DDC gathered)`).
- **Только X11.** При Wayland (Weston/labwc) на `sun60iw2` KMS-коммит не работает,
  `xrandr` не применяется — способ не подойдёт.

## Откат

```bash
sudo cp -a /etc/X11/xorg.conf.d/20-modesetting.conf.bak-* /etc/X11/xorg.conf.d/20-modesetting.conf
rm -f ~/.local/bin/set-display-1024x600.sh ~/.local/bin/hdmi-panel-watch.sh \
      ~/.config/autostart/display-1024x600.desktop ~/.config/autostart/hdmi-panel-watch.desktop
sudo systemctl restart lightdm
```

## Лицензия

MIT — см. [LICENSE](LICENSE).
