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

- `/etc/X11/xorg.conf.d/20-modesetting.conf`
- `~/.local/bin/set-display-1024x600.sh`
- `~/.config/autostart/display-1024x600.desktop`
- `/usr/local/bin/hdmi-panel-watch.sh`
- `/etc/systemd/system/hdmi-panel-watch.service`
- `~/panel-diag.sh` (диагностика, по желанию)

Каталоги создавать не нужно — команды в блоках делают это сами. Дальше выполняйте
шаги 3–6.

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

## Шаг 4. Скрипт режима и его автозапуск

```bash
install -d ~/.local/bin ~/.config/autostart
install -m 0755 files/set-display-1024x600.sh ~/.local/bin/set-display-1024x600.sh
install -m 0644 autostart/display-1024x600.desktop ~/.config/autostart/
```

В `.desktop` путь записан как `$HOME/.local/bin/...` — он раскрывается оболочкой,
поэтому подойдёт любому пользователю.

Проверить, что имя выхода совпадает с вашей машиной (у 4 Pro режим называется `HDMI-1`):

```bash
grep -n 'HDMI-1' ~/.local/bin/set-display-1024x600.sh
```

---

## Шаг 5. Сторож линии — системной службой

Сторож должен работать **от root**: только root читает журнал ядра
(`kernel.dmesg_restrict=1`), а решение «будить панель или нет» принимается именно
по журналу. Автозапуск в сеансе для этого не годится ещё и по времени: обрыв линии
случается на 10-й секунде загрузки, а сеанс стартует около 11-й.

```bash
sudo install -m 0755 files/hdmi-panel-watch.sh /usr/local/bin/hdmi-panel-watch.sh
sudo install -m 0644 systemd/hdmi-panel-watch.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hdmi-panel-watch
```

Проверка:

```bash
systemctl is-enabled hdmi-panel-watch
systemctl is-active hdmi-panel-watch
```

Ожидается `enabled` и `active`.

Если раньше вы ставили сторож автозапуском в сеансе — уберите его, иначе будут
работать две копии:

```bash
rm -f ~/.config/autostart/hdmi-panel-watch.desktop
pkill -f "$HOME/.local/bin/hdmi-panel-watch.sh" 2>/dev/null || true
```

---

## Шаг 6. Перезапустить графику и проверить

```bash
sudo systemctl restart lightdm
```

Через 20–25 секунд:

```bash
DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority xrandr --query | head -3
grep -E 'Using user preference|using initial mode' /var/log/Xorg.0.log | tail -2
pgrep -af 'set-display-1024x600'
systemctl is-active hdmi-panel-watch
dmesg | grep -iE 'hpd|mode set|phy state' | tail -12
```

Что должно быть:

- `HDMI-1 connected 1024x600+0+0`;
- в списке режимов `panel_1024x600  66.45*+`;
- в логе X: `Using user preference for initial modes` и
  `Output HDMI-1 using initial mode panel_1024x600`;
- после 13-й секунды загрузки — ни одного нового `hpd disconnect`;
- служба `hdmi-panel-watch` — `active`.

Полная диагностика одной командой:

```bash
bash panel-diag.sh
```

---

## Шаг 7. Перезагрузка

```bash
sudo reboot
```

После возврата рабочий стол должен появиться и **не пропасть**. В журнале ядра
видно, как это выглядит, когда всё правильно:

```
9.5 с   mode set: 1024*600      ← X поставил паспортный режим
10.2 с  hpd disconnect          ← панель перестроилась
10.5 с  hpd connect             ← линия вернулась, картинки нет
11.6 с  mode set: 1024*600      ← сторож разбудил панель (off → mode)
12.7 с  mode set: 1024*600
дальше — тишина
```

---

## Полный код файлов (установка без git)

### 1. Конфиг Xorg

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

### 3. Автозапуск скрипта режима

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

### 4. Сторож линии (служба, root)

```bash
sudo mkdir -p $(dirname /usr/local/bin/hdmi-panel-watch.sh)
sudo tee /usr/local/bin/hdmi-panel-watch.sh > /dev/null << 'CONFIG_EOF'
#!/bin/sh
# Сторож HDMI-панели 5" (QDtech MPI5001) на Orange Pi 4 Pro — системная служба.
#
# Логика (выведена из журналов, проверена на живой плате):
#   * Панель гаснет, когда после установки паспортного режима 1024x600 она
#     роняет линию HPD (disconnect -> connect): драйвер режим не переставляет.
#   * Лечится принудительным переключением выхода (off -> mode), НО только
#     когда панель уже потеряла линию. Профилактическое переключение при
#     живой панели само вызывает обрыв, поэтому его нет.
#   * При старте решение принимается не по таймеру, а по журналу ядра:
#     был ли hpd disconnect ПОСЛЕ последнего mode set: 1024*600.
export DISPLAY=:0
export XAUTHORITY=/home/orangepi/.Xauthority

MODE=panel_1024x600
STATUS=/sys/class/drm/card0-HDMI-A-1/status

wake() {
    xrandr --output HDMI-1 --off >/dev/null 2>&1
    sleep 1
    xrandr --output HDMI-1 --mode "$MODE" >/dev/null 2>&1
}

# время (секунды от загрузки) последней строки с заданным текстом
ts_of() {
    dmesg 2>/dev/null | grep -F "$1" | tail -1 | sed -n 's/^\[ *\([0-9.]*\)\].*/\1/p'
}

# 1. ждём, пока X ответит
i=0
while [ $i -lt 120 ]; do
    xrandr --query >/dev/null 2>&1 && break
    i=$((i + 1))
    sleep 1
done

# 2. ждём, пока X поставит паспортный режим (признак в журнале ядра)
m=""
i=0
while [ $i -lt 90 ]; do
    m=$(ts_of 'mode set: 1024*600')
    [ -n "$m" ] && break
    i=$((i + 1))
    sleep 1
done

# 3. если после этого панель роняла линию — будим один раз
if [ -n "$m" ]; then
    f=$(ts_of 'hpd disconnect')
    if [ -n "$f" ] && awk -v f="$f" -v m="$m" 'BEGIN{exit !(f > m)}'; then
        sleep 1
        wake
        sleep 5
    fi
fi

# 4. дальше — реакция на реальные обрывы, не чаще раза в минуту
prev=$(cat "$STATUS" 2>/dev/null)
last=$(date +%s)

while true; do
    st=$(cat "$STATUS" 2>/dev/null)
    if [ "$st" != "$prev" ]; then
        if [ "$st" = "connected" ]; then
            now=$(date +%s)
            if [ $((now - last)) -gt 60 ]; then
                sleep 1
                wake
                last=$(date +%s)
                sleep 8
            fi
        fi
        prev=$st
    fi
    sleep 0.3
done
CONFIG_EOF
sudo chmod 0755 /usr/local/bin/hdmi-panel-watch.sh
```

### 5. Юнит systemd

```bash
sudo mkdir -p $(dirname /etc/systemd/system/hdmi-panel-watch.service)
sudo tee /etc/systemd/system/hdmi-panel-watch.service > /dev/null << 'CONFIG_EOF'
[Unit]
Description=HDMI panel watchdog (5-inch 1024x600 panel on Orange Pi 4 Pro)
After=display-manager.service
Wants=display-manager.service

[Service]
Type=simple
ExecStart=/usr/local/bin/hdmi-panel-watch.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
CONFIG_EOF
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
echo "== служба сторожа =="
systemctl is-enabled hdmi-panel-watch 2>/dev/null
systemctl is-active hdmi-panel-watch 2>/dev/null

echo
echo "== тачскрин (USB) =="
lsusb 2>/dev/null | grep -i 0484 || echo "QDtech (0484:xxxx) не найден"
SCRIPT_EOF
chmod +x $HOME/panel-diag.sh 2>/dev/null || true
```

---

## После создания файлов

```bash
# конфиг Xorg уже на месте; включаем службу и перезапускаем графику
sudo systemctl daemon-reload
sudo systemctl enable --now hdmi-panel-watch
sudo systemctl restart lightdm
sleep 22
DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority xrandr --query | head -3
systemctl is-active hdmi-panel-watch
```

---

## Важно

- **Сторож — только службой от root.** `kernel.dmesg_restrict=1`: пользователю журнал
  ядра закрыт, а решение принимается по журналу. Автозапуск в сеансе вдобавок
  стартует позже обрыва линии (обрыв на 10-й секунде, сеанс — около 11-й).
- **Не переключайте выход «профилактически».** Если панель жива, `--off` → `--mode`
  сам вызывает обрыв линии и гасит экран. Сторож будит только после реального обрыва.
- **Только X11 (Xorg).** На Wayland-композиторе (Weston/labwc) на `sun60iw2`
  KMS-коммит не проходит, `xrandr` не работает.
- **`stat -c %s` на EDID всегда даёт 0** — особенность sysfs, а не признак битого
  кабеля. Читайте сам файл через `od -An -tx1`.
- **Свой экран — свои цифры.** Моделайн берите из EDID своей панели
  (`DISPLAY=:0 xrandr --verbose`, раздел EDID, либо `/var/log/Xorg.0.log`).

---

## Откат

```bash
sudo systemctl disable --now hdmi-panel-watch
sudo rm -f /usr/local/bin/hdmi-panel-watch.sh /etc/systemd/system/hdmi-panel-watch.service
sudo systemctl daemon-reload
sudo cp -a $(ls -t /etc/X11/xorg.conf.d/20-modesetting.conf.bak-* | head -1) \
           /etc/X11/xorg.conf.d/20-modesetting.conf
rm -f $HOME/.local/bin/set-display-1024x600.sh \
      $HOME/.config/autostart/display-1024x600.desktop
sudo systemctl restart lightdm
```
