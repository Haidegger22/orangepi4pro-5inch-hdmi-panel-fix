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
