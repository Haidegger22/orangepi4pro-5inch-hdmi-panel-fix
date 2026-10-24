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
