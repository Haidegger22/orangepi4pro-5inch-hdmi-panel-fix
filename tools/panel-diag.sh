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
echo "== DTB: принудительный режим HDMI =="
DTB=/boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb
if command -v fdtget >/dev/null 2>&1 && [ -r "$DTB" ]; then
    printf 'force-output: '
    fdtget -t i "$DTB" /soc@3000000/hdmi0@5520000 force-output 2>/dev/null || echo "нет"
    printf 'force-output-timing: '
    fdtget -t s "$DTB" /soc@3000000/hdmi0@5520000 force-output-timing 2>/dev/null || echo "нет"
else
    echo "fdtget или $DTB недоступны"
fi

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
echo "== журнал ядра: режим и HPD =="
dmesg 2>/dev/null | grep -iE 'Configuration mode|mode set:|hpd (dis)?connect|phy state' | tail -16

echo
echo "== старые обходные пути (должны быть выключены) =="
for s in hdmi-panel-watch panel-wake-once; do
    state=$(systemctl is-enabled "$s" 2>/dev/null || true)
    printf '%s: %s\n' "$s" "${state:-нет}"
done

echo
echo "== тачскрин (USB) =="
lsusb 2>/dev/null | grep -i 0484 || echo "QDtech (0484:xxxx) не найден"
