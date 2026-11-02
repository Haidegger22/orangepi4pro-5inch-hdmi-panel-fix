#!/bin/sh
# Добавляет в DTB штатный режим HDMI для 5" панели 1024x600 (Orange Pi 4 Pro).
# Ядро не пересобирается. После успешного запуска нужна перезагрузка.
#
# Использование:
#   sudo tools/apply-dtb-force-output.sh [путь-к-dtb]
#
# По умолчанию:
#   /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb

set -eu

DTB="${1:-/boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb}"
NODE="/soc@3000000/hdmi0@5520000"
TIMING="50000-1024-1032-1042-1204-600-603-609-625"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запускать от root: sudo $0" >&2
    exit 1
fi

if [ ! -f "$DTB" ]; then
    echo "Не найден DTB: $DTB" >&2
    exit 1
fi

if ! command -v fdtput >/dev/null 2>&1; then
    echo "Нет fdtput. Установите: sudo apt install device-tree-compiler" >&2
    exit 1
fi

backup="${DTB}.bak-force-$(date +%Y%m%d-%H%M%S)"
cp -a "$DTB" "$backup"
echo "Бэкап: $backup"

fdtput -t i "$DTB" "$NODE" force-output 1
fdtput -t s "$DTB" "$NODE" force-output-timing "$TIMING"

got_force=$(fdtget -t i "$DTB" "$NODE" force-output 2>/dev/null || true)
got_timing=$(fdtget -t s "$DTB" "$NODE" force-output-timing 2>/dev/null || true)

if [ "$got_force" != "1" ] || [ "$got_timing" != "$TIMING" ]; then
    echo "Ошибка: свойства не записались (force-output='$got_force', timing='$got_timing')" >&2
    echo "Восстановите DTB: cp -a '$backup' '$DTB'" >&2
    exit 1
fi

sync
printf 'Готово: force-output=%s, timing=%s\n' "$got_force" "$got_timing"
echo "Теперь перезагрузите плату: sudo reboot"
