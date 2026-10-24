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
