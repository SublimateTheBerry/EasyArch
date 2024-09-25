#!/bin/bash

# Проверяем, запущен ли скрипт от root
if [ "$(id -u)" -ne 0 ]; then
    echo "Скрипт должен быть запущен от имени root."
    exit 1
fi

# Запрашиваем данные
read -p "Введите имя пользователя: " username
read -p "Введите имя хоста (например, archlinux): " hostname
read -p "Введите пароль для пользователя $username: " -s user_password
echo
read -p "Введите пароль для root: " -s root_password
echo
read -p "Выберите файловую систему для корня (ext4 или btrfs, по умолчанию ext4): " fs_type
fs_type=${fs_type:-ext4}
read -p "Введите имя устройства (например, /dev/sda): " device

# Запрашиваем тип системы (BIOS или EFI)
read -p "Введите тип системы (bios или efi): " system_type

# Запрашиваем размеры разделов
read -p "Введите размер корневого раздела (например, 20G): " root_size
read -p "Введите размер раздела для /home (например, 20G, введите 0, если не нужно): " home_size
read -p "Введите размер подкачки (например, 2G, введите 0, если не нужно): " swap_size

# Подготовка к установке
echo "Создаем разделы..."
parted $device mklabel gpt

if [[ "$system_type" == "efi" ]]; then
    parted -a opt $device mkpart primary fat32 1MiB 1025MiB # EFI раздел
fi

parted -a opt $device mkpart primary $fs_type 1025MiB $root_size # Корневой раздел
if [ "$home_size" -gt 0 ]; then
    parted -a opt $device mkpart primary $fs_type $((1025 + root_size))MiB $((1025 + root_size + home_size))MiB # /home
fi
if [ "$swap_size" -gt 0 ]; then
    parted -a opt $device mkpart primary linux-swap $((1025 + root_size + home_size))MiB $((1025 + root_size + home_size + swap_size))MiB # Подкачка
fi

echo "Форматируем и монтируем разделы..."
if [[ "$system_type" == "efi" ]]; then
    mkfs.fat -F32 "${device}1" # Форматируем EFI раздел
fi

mkfs."$fs_type" -F "${device}2" # Форматируем корневой раздел
mount "${device}2" /mnt

if [ "$home_size" -gt 0 ]; then
    mkfs."$fs_type" -F "${device}3" # Форматируем /home
    mkdir /mnt/home
    mount "${device}3" /mnt/home
fi

if [ "$swap_size" -gt 0 ]; then
    mkswap "${device}4" # Форматируем подкачку
    swapon "${device}4"
fi

# Установка базовой системы
echo "Устанавливаем базовую систему..."
pacstrap /mnt base linux linux-firmware

# Генерация fstab
echo "Генерируем fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Настройка системы
arch-chroot /mnt /bin/bash <<EOF
# Устанавливаем дополнительные пакеты
pacman -S --noconfirm networkmanager grub amd-ucode efibootmgr

# Настраиваем язык и локализацию
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "$hostname" > /etc/hostname

# Настройка сети
systemctl enable NetworkManager

# Настройка таймзоны
read -p "Введите вашу таймзону (например, Europe/Moscow): " timezone
ln -sf /usr/share/zoneinfo/\$timezone /etc/localtime
hwclock --systohc

# Установка GRUB
if [[ "$system_type" == "efi" ]]; then
    mkdir -p /boot/efi
    mount "${device}1" /boot/efi
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ArchLinux
else
    grub-install --target=i386-pc $device
fi

grub-mkconfig -o /boot/grub/grub.cfg

# Создаем пользователя
useradd -m -G "$username" "$username"
echo "$username:$user_password" | chpasswd
echo "root:$root_password" | chpasswd

# Настройка sudo
echo "$username ALL=(ALL) ALL" >> /etc/sudoers

# Установка рабочего окружения (например, XFCE)
read -p "Выберите рабочее окружение (например, xfce, gnome, kde): " desktop_env
if [[ "$desktop_env" == "xfce" ]]; then
    pacman -S --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
    systemctl enable lightdm
elif [[ "$desktop_env" == "gnome" ]]; then
    pacman -S --noconfirm gnome gnome-extra
    systemctl enable gdm
elif [[ "$desktop_env" == "kde" ]]; then
    pacman -S --noconfirm plasma sddm
    systemctl enable sddm
else
    echo "Неизвестное рабочее окружение. Установка не выполнена."
    exit 1
fi

EOF

# Завершение установки
echo "Установка завершена. Перезагрузите систему."
