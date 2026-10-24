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
