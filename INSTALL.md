# Установка — Orange Pi 4 Pro, 5" HDMI-панель 1024x600

Пошагово, блоками для копирования в терминал. Проверено на Debian 13 Trixie,
ядро `6.6.98-sun60iw2`, Xorg + XFCE.

Две дороги: **А** — через git, **Б** — создать файлы руками (если git или GitHub
недоступны). Обе дают одинаковый результат; код всех файлов есть в конце документа.

---

## Шаг 0. Проверить, что это та плата и та панель

```bash
uname -r
ls /sys/class/drm/
cat /sys/class/drm/card0-HDMI-A-1/status
od -An -tx1 /sys/class/drm/card0-HDMI-A-1/edid | head -4
```

Ожидается: ядро `6.6.98-sun60iw2`, один разъём `card0-HDMI-A-1` (плюс `card1` —
это GPU), статус `connected`, в EDID первая строка начинается с `00 ff ff ff ff ff ff 00`.

Если разъёмов несколько или статус `disconnected` — дальше идти нет смысла, дело не в режиме.

---

## Шаг 1. Зависимости

```bash
sudo apt update
sudo apt install -y x11-xserver-utils x11-utils git
```

`xrandr` входит в `x11-xserver-utils`, `xwininfo` — в `x11-utils`.

---

## Шаг 2. Забрать файлы

### Дорога А — через git

```bash
git clone https://github.com/Haidegger22/orangepi4pro-5inch-hdmi-panel-fix.git
cd orangepi4pro-5inch-hdmi-panel-fix
```

### Дорога Б — без git

Создайте файлы блоками из раздела «Полный код файлов» в конце этого документа:

- `files/20-modesetting.conf`
- `files/set-display-1024x600.sh`
- `files/hdmi-panel-watch.sh`
- `autostart/display-1024x600.desktop`
- `autostart/hdmi-panel-watch.desktop`
- `tools/panel-diag.sh`

Каталоги создавать не нужно — команды в блоках делают это сами. Дальше выполняйте
шаги 3–6, подставляя пути к созданным файлам.

---

## Шаг 3. Конфиг Xorg: старт сразу в 1024x600

Сначала копия текущего файла — без неё откат будет неприятным:

```bash
sudo cp -a /etc/X11/xorg.conf.d/20-modesetting.conf \
           /etc/X11/xorg.conf.d/20-modesetting.conf.bak-$(date +%Y%m%d-%H%M)
```

Вариант 1 — заменить файл целиком (подходит, если он у вас не правился):

```bash
sudo install -m 0664 files/20-modesetting.conf /etc/X11/xorg.conf.d/20-modesetting.conf
```

Вариант 2 — **аккуратный**: добавить в уже существующую секцию
`Monitor "Default Monitor"` две строки (если в вашем файле есть свои правки):

```
    Modeline "panel_1024x600" 50.00 1024 1032 1042 1204 600 603 609 625 -HSync +VSync
    Option	"PreferredMode" "panel_1024x600"
```

Проверить синтаксис, не перезапуская графику:

```bash
Xorg -config /etc/X11/xorg.conf.d/20-modesetting.conf -showopts 2>&1 | tail -5
```

Сообщение о занятом дисплее (`Server is already active`) — нормально, оно означает,
что конфиг прочитан. Ошибок разбора (`Parse error`) быть не должно.

---

## Шаг 4. Скрипты в домашний каталог

```bash
install -d ~/.local/bin
install -m 0755 files/set-display-1024x600.sh ~/.local/bin/set-display-1024x600.sh
install -m 0755 files/hdmi-panel-watch.sh     ~/.local/bin/hdmi-panel-watch.sh
```

Проверить, что пути внутри скриптов совпадают с вашей машиной (у 4 Pro режим
называется `HDMI-1`):

```bash
grep -n 'HDMI-1' ~/.local/bin/set-display-1024x600.sh ~/.local/bin/hdmi-panel-watch.sh
```

---

## Шаг 5. Автозапуск в сессии XFCE

```bash
install -d ~/.config/autostart
install -m 0644 autostart/display-1024x600.desktop ~/.config/autostart/
install -m 0644 autostart/hdmi-panel-watch.desktop ~/.config/autostart/
```

В `.desktop` путь записан как `$HOME/.local/bin/...` — он раскрывается оболочкой,
поэтому подойдёт любому пользователю.

---

## Шаг 6. Перезапустить графику и проверить

```bash
sudo systemctl restart lightdm
```

Через 20–25 секунд:

```bash
DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority xrandr --query | head -3
grep -E 'Using user preference|using initial mode' /var/log/Xorg.0.log | tail -2
pgrep -af 'hdmi-panel-watch|set-display-1024x600'
dmesg | grep -iE 'hpd|mode set|phy state' | tail -10
```

Что должно быть:

- `HDMI-1 connected 1024x600+0+0`;
- в списке режимов `panel_1024x600  66.45*+`;
- в логе X: `Using user preference for initial modes` и
  `Output HDMI-1 using initial mode panel_1024x600`;
- после 20-й секунды загрузки — ни одного нового `hpd disconnect`;
- оба процесса живы.

Полная диагностика одной командой:

```bash
bash tools/panel-diag.sh
```

---

## Шаг 7. Перезагрузка

```bash
sudo reboot
```

После возврата рабочий стол должен появиться и **не пропасть**. Панель коротко
мигнёт на 10-й секунде (внутренняя перестройка на смене режима) — это нормально.

---

## Полный код файлов (установка без git)

### 1. Конфиг Xorg — /etc/X11/xorg.conf.d/20-modesetting.conf

```bash
sudo mkdir -p $(dirname /etc/X11/xorg.conf.d/20-modesetting.conf)
sudo tee /etc/X11/xorg.conf.d/20-modesetting.conf > /dev/null << 'CONFIG_EOF'
Section "Device"
    Identifier  "Allwinner Graphics"
    Driver      "modesetting"
    Option      "kmsdev"        "/dev/dri/card0"

    #Option      "AccelMethod"    "exa"

### Use GPU HW accel
    Option      "AccelMethod"    "glamor"

    Option      "DRI"            "2"

### Set to "always" to avoid tearing, could lead to up 50% performance loss
    #Option      "FlipFB"         "always"

### Limit flip rate and drop frames for "FlipFB" to reduce performance lost
#    Option      "MaxFlipRate"    "60"

#    Option      "NoEDID"         "true"
#    Option	"UseGammaLUT"	 "true"
EndSection

Section	"Screen"
    Identifier	"Default Screen"
    Device	"Allwinner Graphics"
    Monitor	"Default Monitor"
EndSection

### Valid values for rotation are "normal", "left", "right"
### Панель 5" (EDID MPI5006): паспортный режим — 1024x600 при 50.000 МГц
### (строчная 41.5 кГц, кадровая 66.45 Гц). Без PreferredMode X берёт первым
### 1920x1080 из EDID, панель его не держит и гаснет.
### Если в вашем 20-modesetting.conf уже есть секция Monitor "Default Monitor" —
### добавьте в неё только две последние строки (Modeline и PreferredMode).
Section	"Monitor"
    Identifier	"Default Monitor"
    Option	"Rotate" "normal"
    Modeline "panel_1024x600" 50.00 1024 1032 1042 1204 600 603 609 625 -HSync +VSync
    Option	"PreferredMode" "panel_1024x600"
EndSection
CONFIG_EOF
```

### 2. Скрипт установки режима

```bash
mkdir -p $(dirname $HOME/.local/bin/set-display-1024x600.sh)
cat > $HOME/.local/bin/set-display-1024x600.sh << 'SCRIPT_EOF'
#!/bin/sh
# Ставит паспортный режим 1024x600 на HDMI-1 (5" панель MPI5006).
#
# Режим взят из EDID самой панели: частота пикселей 50.000 МГц,
# 1024x600, строчная 41.5 кГц, кадровая 66.45 Гц.
# Прежний вариант (cvt на 60 Гц: 49.00 МГц, строчная 37.3 кГц) панель
# не держала — ловила сигнал и через несколько минут гасла.
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

# ждём, пока X и HDMI поднимутся
for i in $(seq 1 15); do
    xrandr --query >/dev/null 2>&1 && break
    sleep 1
done

# паспортный режим панели
xrandr --newmode panel_1024x600 50.00 1024 1032 1042 1204 600 603 609 625 -HSync +VSync 2>/dev/null || true
xrandr --addmode HDMI-1 panel_1024x600 2>/dev/null || true
xrandr --output HDMI-1 --mode panel_1024x600 2>/dev/null || true

# убираем ошибочный режим из списка, чтобы случайно не выбрать его снова
xrandr --delmode HDMI-1 1024x600_60.00 2>/dev/null || true
xrandr --rmmode 1024x600_60.00 2>/dev/null || true

# без ввода на панели будить экран нечем — гашение выключаем совсем
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true
SCRIPT_EOF
chmod +x $HOME/.local/bin/set-display-1024x600.sh 2>/dev/null || true
```

### 3. Сторож линии HDMI

```bash
mkdir -p $(dirname $HOME/.local/bin/hdmi-panel-watch.sh)
cat > $HOME/.local/bin/hdmi-panel-watch.sh << 'SCRIPT_EOF'
#!/bin/sh
# Сторож HDMI-панели 5" (QDtech MPI5001) на Orange Pi 4 Pro.
#
# Цепочка, из-за которой экран гаснет (проверено по журналу ядра):
#   1.8-6.1 с  ядро ставит 1920x1080 из EDID;
#   9.7 с      X переключается на паспортный 1024x600;
#  10.4 с      панель перестраивается и на ~0.3 с роняет линию HPD
#              (disconnect -> connect);
#              после возврата линии драйвер режим не переставляет — экран чёрный.
# Восстанавливает картинку принудительное переключение выхода (off/on).
#
# ВАЖНО: два переключения подряд вредят — панель после второго сама роняет
# линию и больше не поднимается. Поэтому переключаем ровно один раз после
# старта сеанса и далее только по факту обрыва линии, с ограничением частоты.
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

MODE=panel_1024x600
STATUS=/sys/class/drm/card0-HDMI-A-1/status

reenable() {
    xrandr --output HDMI-1 --off >/dev/null 2>&1
    sleep 1
    xrandr --output HDMI-1 --mode "$MODE" >/dev/null 2>&1
}

# Один раз после старта сеанса: X к этому моменту уже поставил режим,
# панель уже успела дёрнуть линию.
sleep 6
reenable
LAST=$(date +%s)

# Даём панели успокоиться: сразу после переключения линия может дрогнуть,
# и повторное переключение только испортит картину.
sleep 20

prev=$(cat "$STATUS" 2>/dev/null)

while true; do
    st=$(cat "$STATUS" 2>/dev/null)
    if [ "$st" != "$prev" ]; then
        if [ "$st" = "connected" ]; then
            now=$(date +%s)
            if [ $((now - LAST)) -gt 60 ]; then
                sleep 1
                reenable
                LAST=$(date +%s)
                sleep 10
            fi
        fi
        prev=$st
    fi
    sleep 0.3
done
SCRIPT_EOF
chmod +x $HOME/.local/bin/hdmi-panel-watch.sh 2>/dev/null || true
```

### 4. Автозапуск установки режима

```bash
mkdir -p $(dirname $HOME/.config/autostart/display-1024x600.desktop)
cat > $HOME/.config/autostart/display-1024x600.desktop << 'SCRIPT_EOF'
[Desktop Entry]
Type=Application
Name=Display 1024x600
Comment=Set 5-inch HDMI panel to 1024x600 after login
Exec=sh -c "sleep 3; $HOME/.local/bin/set-display-1024x600.sh"
Terminal=false
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
SCRIPT_EOF
```

### 5. Автозапуск сторожа

```bash
mkdir -p $(dirname $HOME/.config/autostart/hdmi-panel-watch.desktop)
cat > $HOME/.config/autostart/hdmi-panel-watch.desktop << 'SCRIPT_EOF'
[Desktop Entry]
Type=Application
Name=HDMI panel watchdog
Comment=Re-enable the 5-inch panel after an HDMI hot-plug drop
Exec=sh -c "$HOME/.local/bin/hdmi-panel-watch.sh"
Terminal=false
StartupNotify=false
NoDisplay=true
SCRIPT_EOF
```

### 6. Диагностика (по желанию)

```bash
mkdir -p $(dirname $HOME/panel-diag.sh)
cat > $HOME/panel-diag.sh << 'SCRIPT_EOF'
#!/bin/sh
# Диагностика HDMI-панели на Orange Pi 4 Pro: что видит система.
# Ничего не меняет — только читает. Запускать в графической сессии,
# чтобы xrandr видел дисплей (DISPLAY=:0 и XAUTHORITY подставит сам).
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

STATUS=/sys/class/drm/card0-HDMI-A-1/status
EDID=/sys/class/drm/card0-HDMI-A-1/edid

echo "== ядро и дата =="
uname -r
date

echo
echo "== разъёмы DRM =="
for d in /sys/class/drm/card*-*; do
    [ -e "$d/status" ] || continue
    printf '%s: %s\n' "$(basename "$d")" "$(cat "$d/status")"
done

echo
echo "== статус линии и режимы ядра =="
cat "$STATUS" 2>/dev/null
cat /sys/class/drm/card0-HDMI-A-1/modes 2>/dev/null

echo
echo "== EDID (первые 4 строки) =="
od -An -tx1 "$EDID" 2>/dev/null | head -4
echo "(stat -c %s на этом файле всегда даёт 0 — это нормально для sysfs)"

echo
echo "== X: активный режим =="
xrandr --query 2>&1 | grep -m1 '^HDMI-1'

echo
echo "== журнал ядра: HDMI/HPD =="
dmesg 2>/dev/null | grep -iE 'sunxi-hdmi|hpd|phy state' | tail -12

echo
echo "== процессы-помощники =="
pgrep -af 'hdmi-panel-watch|temp-widget' | grep -v 'grep'

echo
echo "== тачскрин (USB) =="
lsusb 2>/dev/null | grep -i 0484 || echo "QDtech (0484:xxxx) не найден"
SCRIPT_EOF
chmod +x $HOME/panel-diag.sh 2>/dev/null || true
```

---

## После создания файлов

```bash
# если конфиг Xorg копировали своим путём — просто перезапустить графику
sudo systemctl restart lightdm
sleep 20
DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority xrandr --query | head -3
```

---

## Важно

- **Только X11 (Xorg).** На Wayland-композиторе (Weston/labwc) на `sun60iw2`
  KMS-коммит не проходит, `xrandr` не работает — способ не подойдёт.
- **Ровно одно переключение выхода при старте.** Сторож это соблюдает. Если
  переключать вручную несколько раз подряд, панель после второго переключения
  роняет линию и больше не поднимается.
- **`stat -c %s` на EDID всегда даёт 0** — это особенность sysfs, а не признак
  битого кабеля. Читайте сам файл через `od -An -tx1`.
- **Тач** работает как обычный HID; мультитач требует модуля `hid-multitouch`
  (в ядре `6.6.98-sun60iw2` он выключен) — см. репозиторий
  `opi-zero3w-hid-multitouch-fix`.
- **Свой экран — свои цифры.** Моделайн берите из EDID своей панели:
  `DISPLAY=:0 xrandr --verbose` (раздел EDID) или `/var/log/Xorg.0.log`.

---

## Откат

```bash
sudo cp -a $(ls -t /etc/X11/xorg.conf.d/20-modesetting.conf.bak-* | head -1) \
           /etc/X11/xorg.conf.d/20-modesetting.conf
rm -f $HOME/.local/bin/set-display-1024x600.sh \
      $HOME/.local/bin/hdmi-panel-watch.sh \
      $HOME/.config/autostart/display-1024x600.desktop \
      $HOME/.config/autostart/hdmi-panel-watch.desktop
sudo systemctl restart lightdm
```
