#! /bin/sh

cd ./assets
wget https://raw.githubusercontent.com/raspberrypi/firmware/master/boot/bootcode.bin
wget https://raw.githubusercontent.com/raspberrypi/firmware/master/boot/start4.elf
wget https://raw.githubusercontent.com/raspberrypi/firmware/master/boot/fixup4.dat
# wget https://raw.githubusercontent.com/raspberrypi/firmware/master/boot/bcm2711-rpi-400.dtb
