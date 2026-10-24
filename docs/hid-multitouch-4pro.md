# Тач и мультитач на Orange Pi 4 Pro (QDtech MPI5001)

Тач панели — отдельное USB-HID устройство `0484:5750`, по HDMI он не идёт.
В ядре `6.6.98-sun60iw2` **выключен** `CONFIG_HID_MULTITOUCH`, поэтому без
дополнительных действий касания работают неровно: контроллер отдаёт поток
`ABS_X/ABS_Y` (диапазон 800x480) с «сбросом в максимум» в каждом отчёте, libinput
принимает последнее значение как координату — в результате все касания приходятся
на правый нижний угол, курсор не двигается.

Проверка симптома по уровням:

| уровень | команда | что видно при поломке |
|---|---|---|
| контроллер | `evtest /dev/input/event6` | `BTN_TOUCH` есть, координаты меняются, но каждый отчёт заканчивается `800/480` |
| X | `xinput test-xi2 <id>` | `RawTouchBegin/End` с постоянными `65453 / 65539` (край диапазона) |
| X | `xinput list-props <id>` | `Device Enabled: 1`, `Send Events Mode Enabled: 0, 0` — то есть само устройство активно |

`xinput` в образе 4 Pro нет: `sudo apt install -y xinput`.
`evtest` **захватывает** устройство (`EVIOCGRAB`) — пока он работает, X событий
не получает, поэтому проверять уровни надо по очереди, а не одновременно.

## Что даёт модуль `hid-multitouch`

Драйвер разбирает HID-отчёты правильно и создаёт настоящий мультитач. Признак
успеха — изменившийся набор осей:

```
# было
cat /sys/class/input/event6/device/capabilities/abs
10000000003                      # ABS_X, ABS_Y, ABS_MISC

# стало
273800000000003                  # + ABS_MT_SLOT, ABS_MT_TOUCH_MAJOR/MINOR,
                                 #   ABS_MT_ORIENTATION, ABS_MT_POSITION_X/Y,
                                 #   ABS_MT_TRACKING_ID
```

После этого работают одиночные касания, два пальца и жесты прокрутки.

## Сборка (без заголовков ядра — их в Trixie нет)

Готовых `linux-headers-current-sun60iw2` в репозитории Debian 13 нет, поэтому
дерево сборки берётся из вендорной ветки — она ровно той же версии.

```bash
# 1. Исходники (≈2.3 ГБ)
mkdir -p /root/kbuild && cd /root/kbuild
git clone --depth 1 --branch orange-pi-6.6-sun60iw2 \
  https://github.com/orangepi-xunlong/linux-orangepi linux

# 2. Конфиг как у живого ядра + включаем модуль
cd /root/kbuild/linux
cp /boot/config-$(uname -r) .config
./scripts/config --file .config -m HID_MULTITOUCH
make ARCH=arm64 LOCALVERSION=-sun60iw2 olddefconfig

# 3. Подготовка дерева (несколько минут)
make ARCH=arm64 LOCALVERSION=-sun60iw2 -j4 modules_prepare
cat include/config/kernel.release      # 6.6.98-sun60iw2
```

### Обязательный шаг: Module.symvers

`modules_prepare` не создаёт `Module.symvers`, и modpost падает с
`"..." [hid-multitouch.ko] undefined!`. В этом ядре `CONFIG_MODVERSIONS` и
`CONFIG_MODULE_SIG` выключены, поэтому CRC не проверяются — достаточно списка
имён символов из живого ядра. Формат 6.6 — **пять полей, последнее (namespace)
пустое, с завершающим табом**:

```bash
awk '{ if (NF >= 3 && $3 ~ /^[A-Za-z_][A-Za-z0-9_]*$/) printf "0x00000000\t%s\tvmlinux\tEXPORT_SYMBOL\t\n", $3 }' \
  /proc/kallsyms | sort -u > /root/kbuild/linux/Module.symvers
```

Без завершающего таба modpost отвечает `FATAL: modpost: parse error in symbol dump file`.

### Обязательный шаг: VID:PID панели в драйвере

В таблице `mt_devices[]` пары `0484:5750` нет. Модуль соберётся и загрузится, но
к панели не привяжется. Нужная строка:

```c
	{ HID_USB_DEVICE(0x0484, 0x5750), .driver_data = MT_CLS_DEFAULT },
```

Готовый патч — `patches/hid-multitouch-add-qdtech-mpi5001.patch`:

```bash
cd /root/kbuild/linux
patch -p1 < /path/to/patches/hid-multitouch-add-qdtech-mpi5001.patch
```

Таблица заканчивается строкой `\t{ }` **без комментария** `/* Terminating entry */`,
поэтому вставка через `sed` по комментарию молча ничего не делает.

### Сборка и установка

```bash
mkdir -p /root/kbuild/mt && cd /root/kbuild/linux
cp drivers/hid/hid-multitouch.c drivers/hid/hid-ids.h /root/kbuild/mt/
printf 'obj-m := hid-multitouch.o\nccflags-y += -I$(src)\n' > /root/kbuild/mt/Makefile
make -C /root/kbuild/linux M=/root/kbuild/mt ARCH=arm64 LOCALVERSION=-sun60iw2 modules -j4
modinfo /root/kbuild/mt/hid-multitouch.ko | grep vermagic
# vermagic: 6.6.98-sun60iw2 SMP preempt mod_unload aarch64

sudo mkdir -p /lib/modules/$(uname -r)/kernel/drivers/hid
sudo cp /root/kbuild/mt/hid-multitouch.ko /lib/modules/$(uname -r)/kernel/drivers/hid/
sudo depmod -a
echo hid-multitouch | sudo tee /etc/modules-load.d/hid-multitouch.conf
sudo modprobe hid-multitouch
```

Загрузка модуля при работающей панели перепривязывает устройство сама: в `dmesg`
появляется `input: QDtech MPI5001 as ...`, в
`/sys/bus/hid/drivers/hid-multitouch/` — `0003:0484:5750.0003`.

Права на устройство (на случай запуска X не от root):

```
ACTION=="add", KERNEL=="event*", SUBSYSTEM=="input", \
  ATTRS{idVendor}=="0484", ATTRS{idProduct}=="5750", MODE="0666"
```

## После обновления ядра

Модуль привязан к `vermagic`; после смены версии ядра его нужно пересобрать тем же
рецептом (дерево `/root/kbuild` можно оставить, но ветку придётся обновить).
Проверка: `modinfo hid_multitouch | grep vermagic` и `lsmod | grep hid_multitouch`.
