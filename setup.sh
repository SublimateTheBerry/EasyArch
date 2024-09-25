#!/bin/bash

# Проверка режима загрузки (EFI или BIOS)
if [ -d /sys/firmware/efi ]; then
    echo "Система загружена в режиме EFI."
    efi_mode=true
else
    echo "Система загружена в режиме BIOS."
    efi_mode=false
fi

# Вопрос о разметке диска
read -p "Укажите диск для разметки (например, /dev/sda): " disk

# Уточнение и подтверждение
echo "Будет произведена полная разметка диска $disk. Все данные будут удалены."
read -p "Вы уверены? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "Установка отменена."
    exit 1
fi

# Синхронизация времени
echo "Синхронизация времени..."
timedatectl set-ntp true

# Вопрос о размере EFI-раздела (если система EFI)
if $efi_mode; then
    read -p "Укажите размер EFI-раздела (например, 512MiB): " efi_size
fi

# Вопрос о создании раздела подкачки
read -p "Создать раздел подкачки (swap)? (y/n): " create_swap
if [ "$create_swap" == "y" ]; then
    read -p "Укажите размер раздела подкачки (например, 4GiB): " swap_size
else
    swap_size="0"
fi

# Вопрос о создании дополнительного раздела для данных
read -p "Создать отдельный раздел для данных? (y/n): " create_data_partition
if [ "$create_data_partition" == "y" ]; then
    read -p "Укажите размер раздела для данных (например, 50GiB): " data_size
else
    data_size="0"
fi

# Вопрос о размере корневого раздела
read -p "Укажите размер корневого раздела (например, 30GiB): " root_size

# Разметка диска
echo "Разметка диска..."
parted $disk --script mklabel gpt

if $efi_mode; then
    parted $disk --script mkpart primary fat32 1MiB $efi_size
    parted $disk --script set 1 esp on
    efi_partition="${disk}1"
fi

# Создание раздела подкачки (если нужно)
if [ "$swap_size" != "0" ]; then
    parted $disk --script mkpart primary linux-swap $efi_size $((efi_size + swap_size))
    swap_partition="${disk}2"
    echo "Раздел подкачки создан."
fi

# Создание корневого раздела
parted $disk --script mkpart primary ext4 $((efi_size + swap_size)) $((efi_size + swap_size + root_size))
root_partition="${disk}3"
echo "Корневой раздел создан."

# Создание раздела для данных (если нужно)
if [ "$data_size" != "0" ]; then
    parted $disk --script mkpart primary ext4 $((efi_size + swap_size + root_size)) $((efi_size + swap_size + root_size + data_size))
    data_partition="${disk}4"
    echo "Раздел для данных создан."
fi

# Форматирование разделов
echo "Форматирование разделов..."
mkfs.ext4 "${root_partition}"
if [ "$swap_size" != "0" ]; then
    mkswap "${swap_partition}"
    swapon "${swap_partition}"
fi

if $efi_mode; then
    mkfs.fat -F32 "${efi_partition}"
fi

if [ "$data_size" != "0" ]; then
    mkfs.ext4 "${data_partition}"
fi

# Монтирование разделов
echo "Монтирование разделов..."
mount "${root_partition}" /mnt

if $efi_mode; then
    mkdir /mnt/boot
    mount "${efi_partition}" /mnt/boot
fi

if [ "$data_size" != "0" ]; then
    mkdir /mnt/data
    mount "${data_partition}" /mnt/data
fi

# Установка базовых пакетов
echo "Установка базовой системы..."
pacstrap /mnt base linux linux-firmware

# Установка sudo
echo "Установка sudo..."
arch-chroot /mnt pacman -S sudo

# Создание пользователя
read -p "Введите имя пользователя: " username
arch-chroot /mnt useradd -m -G users -s /bin/bash "$username"

# Установка пароля для пользователя
echo "Установка пароля для пользователя $username:"
arch-chroot /mnt passwd "$username"

# Установка пароля для root
echo "Установка пароля для root:"
arch-chroot /mnt passwd root

# Вопрос о выборе окружения рабочего стола (DE)
echo "Выберите окружение рабочего стола (DE):"
echo "1) GNOME"
echo "2) KDE"
echo "3) Xfce"
read -p "Введите номер выбора (1/2/3): " de_choice

case $de_choice in
    1)
        echo "Установка GNOME..."
        arch-chroot /mnt pacman -S gnome gdm
        arch-chroot /mnt systemctl enable gdm
        ;;
    2)
        echo "Установка KDE..."
        arch-chroot /mnt pacman -S plasma sddm
        arch-chroot /mnt systemctl enable sddm
        ;;
    3)
        echo "Установка Xfce..."
        arch-chroot /mnt pacman -S xfce4 lightdm lightdm-gtk-greeter
        arch-chroot /mnt systemctl enable lightdm
        ;;
    *)
        echo "Некорректный выбор, установка DE пропущена."
        ;;
esac

# Завершение установки
echo "Установка завершена! Выход из chroot и перезагрузка."
umount -R /mnt
reboot
