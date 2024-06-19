Void Linux UEFI install on NVME with Intel or AMD graphics 2021-11
This guide will refer to the OS disk as /dev/nvme0n1.
I encourage you to peruse the Void Linux Handbook at https://docs.voidlinux.org/about/index.html



INITIAL SETUP

Connect to ethernet and boot the live installer.
Log in as root with password voidlinux.

The default shell is dash. Launch bash.
# bash



IF INSTALLING OVER WI-FI

# cp /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant-<wlan-interface>.conf
# wpa_passphrase <ssid> <passphrase> >> /etc/wpa_supplicant/wpa_supplicant-<wlan-interface>.conf
# sv restart dhcpcd
# ip link set up <interface>



INITIAL SETUP CONTINUED

Check network/internet connection
# ip -c addr show

Sync XBPS' remote repository index
# xbps-install -S

Install nano
# xbps-install -y nano

Edit the SSHD config to allow root login over SSH
# nano /etc/ssh/sshd_config
change "#PermitRootLogin prohibit-password" to "PermitRootLogin yes"
save and exit (ctrl+o, enter, ctrl+x)

Restart the SSH server
# sv restart sshd

Use mRemoteNG (or your prefered SSH client) to connect via SSH



PARTITION THE DISK

List block devices
# lsblk

Wipe the target disk
# wipefs -a /dev/nvme0n1

Launch fdisk
# fdisk /dev/nvme0n1

Create GPT partition table
Command (m for help): g

Create EFI System Partition (ESP)
Command (m for help): n
Partition number (1-128, default 1): (enter for default)
First sector (2048-500118158, default 2048): (enter for default)
Last sector, +/-sectors or +/-size{K,M,G,T,P}...): +128M (choose 128M to 1G)
Do you want to remove the signature? [Y]es/[N]o: y
Command (m for help): t
Partition type or alias (type L to list all): 1

Create the root partition
Command (m for help): n
Partition number (2-128, default 2): (enter for default)
First sector (2099200-500118158, default 2099200): (enter for default)
Last sector, +/-sectors or +/-size{K,M,G,T,P}...): (enter for default)

Write changes to the disk
Command (m for help): w



SET UP ENCRYPTED ROOT VOLUME

Encrypt root partition with LUKS1 since grub-mkconfig doesn't work with LUKS2.
# cryptsetup luksFormat --type luks1 -y /dev/nvme0n1p2

Open the newly formatted LUKS partition:
# cryptsetup open /dev/nvme0n1p2 cryptroot



FORMAT THE PARTITIONS

Format the EFI System Partition
# mkfs.vfat -F32 -n EFI /dev/nvme0n1p1

Format the root Partition
# mkfs.btrfs -L Void_Linux /dev/mapper/cryptroot

Verify file systems
# lsblk -f



CREATE BTRFS SUBVOLUMES

Create shell variable for mount options
# BTRFS_OPTS="rw,noatime,compress=zstd,space_cache=v2,discard=async"

Mount the top level subvolume
# mount -o $BTRFS_OPTS /dev/mapper/cryptroot /mnt

Create root subvolume
# btrfs su cr /mnt/@

Create home subvolume
# btrfs su cr /mnt/@home

Create subvolume to house snapshots
# btrfs su cr /mnt/@snapshots

Unmount cryptroot from /mnt
# umount /mnt



MOUNT BTRFS SUBVOLUMES AND EFI SYSTEM PARTITION

Mount the root subvolume
# mount -o $BTRFS_OPTS,subvol=@ /dev/mapper/cryptroot /mnt

Create mount point for the ESP, the @home subvolume, and the @snapshots subvolume
# mkdir /mnt/{efi,home,.snapshots}

Mount the @home subvolume
# mount -o $BTRFS_OPTS,subvol=@home /dev/mapper/cryptroot /mnt/home

Mount the @snapshots subvolume
# mount -o $BTRFS_OPTS,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots

Create nested subvolumes for directories we don't want included in snapshots
# mkdir -p /mnt/var/cache
# btrfs su cr /mnt/var/cache/xbps
# btrfs su cr /mnt/var/tmp
# btrfs su cr /mnt/srv

Create a nested subvolume for containing the swapfile
# btrfs subvolume create /mnt/var/swap

Mount the EFI System Partition
# mount -o rw,noatime /dev/nvme0n1p1 /mnt/efi

Verify mount points
# df -h
 or
#lsblk



BASE INSTALLATION

Choose a mirror from the list at https://docs.voidlinux.org/xbps/repositories/mirrors/index.html
I'm opting to use USA: Chicago (https://mirrors.servercentral.com/voidlinux/)

Choose which C library you want to use (I'm going to use glibc in this guide)
glibc: /current
musl: /current/musl

Create a shell variable for the mirror with your chosen C library
# REPO=https://mirrors.servercentral.com/voidlinux/current/

XBPS also needs to know what architecture is being installed.
Available options are x86_64, x86_64-musl, i686.

Create a shell variable for your chosen architecture
# ARCH=x86_64

Use xbps-install to bootstrap the installation by installing the base-system metapackage
# XBPS_ARCH=$ARCH xbps-install -S -R "$REPO" -r /mnt base-system linux-mainline btrfs-progs cryptsetup nano bash-completion



ENTERING THE CHROOT

Mount the pseudo-filesystems needed for a chroot
# for dir in dev proc sys run; do mount --rbind /$dir /mnt/$dir; mount --make-rslave /mnt/$dir; done

Copy the DNS config into the new root so that XBPS can still download new packages inside of it
# cp /etc/resolv.conf /mnt/etc/

Chroot into the new installation (and launch bash inside of it)
# BTRFS_OPTS=$BTRFS_OPTS PS1='(chroot) # ' chroot /mnt/ /bin/bash



INSTALLATION CONFIGURATION

Go through the options in /etc/rc.conf. See:
https://docs.voidlinux.org/config/rc-files.html for details
NOTE: I personally don't make any changes
(chroot) # nano /etc/rc.conf

Set the time
# ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime

If installing a glibc distribution, uncomment desired locales
(chroot) # nano /etc/default/libc-locales
en_US.UTF-8 UTF-8

For glibc builds, generate locale files
(chroot) # xbps-reconfigure -f glibc-locales



USER MANAGEMENT

Set the root password
(chroot) # passwd

Change root's default shell to bash
# chsh -s /bin/bash root

Enable users in the wheel group to use sudo.
# EDITOR=nano visudo
Uncomment %wheel ALL=(ALL) ALL

Add your local user
# useradd -m -G wheel,floppy,audio,video,cdrom,optical,network,kvm,xbuilder username

Assign a password to your user
# passwd username



CONFIGURE SUBREPOS AND MIRRORS

Sync XBPS with the remote repository
(chroot) # xbps-install -S

Install the nonfree subrepo to enable installing proprietary firmware
(chroot) # xbps-install void-repo-nonfree
(chroot) # xbps-install -S

(Optional) Install multilib repository if gaming
(chroot) # xbps-install void-repo-multilib
(chroot) # xbps-install -S

Change default mirrors from Finland to Chicago
(chroot) # mkdir -p /etc/xbps.d
(chroot) # cp /usr/share/xbps.d/*-repository-*.conf /etc/xbps.d/
(chroot) # sed -i 's|https://alpha.de.repo.voidlinux.org|https://mirrors.servercentral.com/voidlinux|g' /etc/xbps.d/*-repository-*.conf

Synchronize XBPS with the new mirros
(chroot) # xbps-install -S

Verify the new mirrors
(chroot) # xbps-query -L



CONFIGURING FSTAB

Create shell variables for the partitions (LUKS_UUID will be used later)
(chroot) # EFI_UUID=$(blkid -s UUID -o value /dev/nvme0n1p1)
(chroot) # ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/cryptroot)
(chroot) # LUKS_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2)

Add lines to fstab
(chroot) # cat <<EOF > /etc/fstab
#
# See fstab(5).
#
# <file system> <dir>   <type>  <options>               <dump>  <pass>
UUID=$ROOT_UUID / btrfs $BTRFS_OPTS,subvol=@ 0 1
UUID=$ROOT_UUID /home btrfs $BTRFS_OPTS,subvol=@home 0 2
UUID=$ROOT_UUID /.snapshots btrfs $BTRFS_OPTS,subvol=@snapshots 0 2
UUID=$EFI_UUID /efi vfat defaults,noatime 0 2
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
EOF



SET UP SWAP

Create a zero length file that will serve as the swapfile
(chroot) # truncate -s 0 /var/swap/swapfile

Set the No_COW attribute on the swapfile to disable Copy-on-Write for it.
(chroot) # chattr +C /var/swap/swapfile

Disable compression of the swapfile
(chroot) # btrfs property set /var/swap/swapfile compression none

Set permissions for the swap file
(chroot) # chmod 600 /var/swap/swapfile

Create the swap file (For Hibernation, count= RAM size + square root of RAM size)
(chroot) # dd if=/dev/zero of=/var/swap/swapfile bs=1G count=20 status=progress conv=fdatasync

Format the swap file
(chroot) # mkswap /var/swap/swapfile

Activate the swap file
(chroot) # swapon /var/swap/swapfile

Back up the /etc/fstab file
(chroot) # cp /etc/fstab /etc/fstab.bak

Add the swap file to the /etc/fstab file
(chroot) # echo '/var/swap/swapfile none swap sw 0 0' >> /etc/fstab



CALCULATE THE SWAPFILE OFFSET FOR THE BOOTLOADER

Install the needed packages
(chroot) # xbps-install wget gcc

CD to the root user's home directory
(chroot) # cd /root

Download the source code for a script called btrfs_map_physical.c
(chroot) # wget https://raw.githubusercontent.com/osandov/osandov-linux/master/scripts/btrfs_map_physical.c

Comiple the source code
(chroot) # gcc -O2 -o btrfs_map_physical btrfs_map_physical.c

Run the script (PHYSICAL OFFSET should be the last value in the first row, example:  921780224)
(chroot) # ./btrfs_map_physical /var/swap/swapfile

Determine pagesize (for me, it was 4096 at the time of writing this)
(chroot) # getconf PAGESIZE

To compute the resume_offset value, divide the physical offset by the pagesize.
In this example, it is 930557952 / 4096 = 227187.
We'll need this value when we configure the bootloader.

Create variable
(chroot) # RESUME_OFFSET=227187



INSTALLING GRUB

Install the grub package
(chroot) # xbps-install grub-x86_64-efi

Enable encryption support
(chroot) # echo GRUB_ENABLE_CRYPTODISK=y >> /etc/default/grub

Add needed UUIDs to /etc/default/grub
(chroot) # cat <<EOF >> /etc/default/grub
GRUB_CMDLINE_LINUX="resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET "
EOF

Add Options To The Default Command Line
Add "page_poison=1" to mitigate use-after-free vulnerabilities.
Add "rd.auto=1" to autodetect LUKS.
Add "rd.luks.allow-discards" to allow SSD TRIM support for LUKS volumes.
(chroot) # nano /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 page_poison=1 rd.auto=1 rd.luks.allow-discards"

Install grub as the bootloader
(chroot) # grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id="Void"

(Optional) If you have made changes to /etc/default/grub and just need to update
grub's config, don't run grub-install again. Just regenerate the config:
(chroot) # grub-mkconfig -o /boot/grub/grub.cfg



CREATE KEYFILE TO AVOID HAVING TO ENTER THE PASSPHRES TWICE ON BOOTUP

Create the keyfile out of random data
(chroot) # dd bs=515 count=4 if=/dev/urandom of=/boot/keyfile.bin

Add a 2nd key slot to the LUKS encrypted volume with keyfile.bin as the key
(chroot) # cryptsetup -v luksAddKey /dev/nvme0n1p2 /boot/keyfile.bin

Secure the keyfile by setting appropriate permissions
(chroot) # chmod 000 /boot/keyfile.bin

Allow only root to access /boot
(chroot) # chmod -R g-rwx,o-rwx /boot

Set up crypttab
(chroot) # cat <<EOF >> /etc/crypttab
cryptroot UUID=$LUKS_UUID /boot/keyfile.bin luks
EOF

Cofigure dracut to include the keyfile and crypttab in the initial RAM disk
(chroot) # echo 'install_items+=" /boot/keyfile.bin /etc/crypttab "' > /etc/dracut.conf.d/10-crypt.conf



D-BUS AND ELOGIND

D-Bus is an IPC (inter-process communication) mechanism used by userspace software.
elogind(8) manages user logins and system power, as a standalone version of systemd-logind. elogind provides necessary features for most desktop environments and Wayland compositors.

Install elogind and version of dbus with support for elogind features
(chroot) # xbps-install dbus-elogind dbus-elogind-libs dbus-elogind-x11 elogind



NETWORK CONFIGURATION

Specify the hostname in /etc/hostname
(chroot) # echo "hostname" > /etc/hostname

Create hosts file
# cat <<EOF > /etc/hosts
#
# /etc/hosts: static lookup table for host names
#
127.0.0.1        localhost
::1              localhost
127.0.1.1        myhostname.localdomain myhostname
EOF

Install NetworkManager and iNet Wireless Daemon
(chroot) # xbps-install NetworkManager iwd

Create config file to make NetworkManager use iwd as the Wi-Fi backend instead of wpa_supplicant
# mkdir -p /etc/NetworkManager/conf.d/
# cat <<EOF >> /etc/NetworkManager/conf.d/wifi_backend.conf
[device]
wifi.backend=iwd
wifi.iwd.autoconnect=yes
EOF



INSTALL RELEVANT FIRMWARE

(Optional) If target PC has an Intel CPU, install Intel CPU microcode
(chroot) # xbps-install intel-ucode

(Optional) If target PC has an AMD CPU, install AMD CPU microcode and AMD GPU firmware
(chroot) # xbps-install linux-firmware-amd



VIDEO DRIVERS & DISPALY SERVER

Install the OpenGL driver for both Intel and AMD
(chroot) #  xbps-install mesa-dri

Install the Khronos Vulkan Loader for both Intel and AMD
(chroot) #  xbps-install vulkan-loader

Install Xorg and Wayland
(chroot) # xbps-install xorg xorg-server-xwayland

INTEL

Install the mesa vulkan driver
(chroot) # xbps-install mesa-vulkan-intel

Install the video acceleration driver
(chroot) # xbps-install intel-video-accel

Remove the Intel DDX driver to ensure xorg uses modesetting
(chroot) # echo 'ignorepkg=xf86-video-intel' >> /etc/xbps.d/00-repository-main.conf
(chroot) # xbps-remove xf86-video-intel

AMD RADEON

Install the mesa vulkan driver
(chroot) # xbps-install mesa-vulkan-radeon

Install the xorg driver
(chroot) # xbps-install xf86-video-amdgpu

Install the video acceleration driver
(chroot) # xbps-install mesa-vaapi mesa-vdpau

(Optional) Install the OpenCL compute driver
(chroot) # xbps-install mesa-opencl clinfo



DESKTOP ENVIRONMENT: KDE PLASMA

KDE Plasma and KDE apps
(chroot) # xbps-install kde5 kde5-baseapps xdg-user-dirs

Add user to the bluetooth group
(chroot) # usermod -a -G bluetooth username



PIPEWIRE

Note: there is a bug with the currnet versions of bluez
and pipewire that prevents bluetooth audio from working.

Install PipeWire
# xbps-install rtkit pipewire alsa-pipewire libjack-pipewire

Set up pipewire autostart
# cat <<EOF >> /etc/xdg/autostart/pipewire.desktop
[Desktop Entry]
Type=Application
Name=Pipewire
Exec=pipewire
EOF

Set up pipewire-pulse autostart
# cat <<EOF >> /etc/xdg/autostart/pipewire-pulse.desktop
[Desktop Entry]
Type=Application
Name=Pipewire-Pulse
Exec=pipewire-pulse
EOF



INSTALL PACKAGES FOR SYSTEM LOGGING AND NTP

Install additional services
(chroot) # xbps-install chrony socklog-void

Add user to the socklog group
# usermod -a -G socklog username



ENABLE SERVICES

Enable socklog, a syslog implementation from the author of runit.
# ln -s /etc/sv/socklog-unix /var/service/
# ln -s /etc/sv/nanoklogd /var/service/

Enable D-Bus which is required by NetworkManager, KDE, GNOME, and Bluetooth
# ln -s /etc/sv/dbus /var/service/

Enable the iNet Wireless Daemon for Wi-Fi support
# ln -s /etc/sv/iwd /var/service/

Enable the NetworkManager service to get networking started.
# ln -s /etc/sv/NetworkManager /var/service/

Enable chrony for Network Time Protocol support
# ln -s /etc/sv/chronyd /var/service/

Set up PipeWire ALSA
# mkdir -p /etc/alsa/conf.d
# ln -s /usr/share/alsa/alsa.conf.d/50-pipewire.conf /etc/alsa/conf.d
# ln -s /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf /etc/alsa/conf.d

Enable Bluetooth
# ln -s /etc/sv/bluetoothd /var/service/

Enable Simple Desktop Display Manager
# ln -s /etc/sv/sddm/ /var/service/

Try rebooting if things are running slow after the first login.

If the default directories such as Documents, Downloads, and Pictures are missing, run:
$ xdg-user-dirs-update



USER APPLICATIONS

(Optional) Install user applications
(chroot) # xbps-install htop neofetch mpv firefox gwenview handbrake

(Optional) Install Krusader file manager and its optional dependencies
(chroot) # xbps-install krusader kdiff3 krename p7zip

(Optional) Install YouTube Downloader
(chroot) # yt-dlp ffmpeg

Install Flatpak (platform for distro-agnostic, sandboxed applications)
(chroot) # xbps-install flatpak

Add the Flathub repository to Flatpak
(chroot) # flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

(Optional) Install MakeMKV for ripping legally purchased DVD and Blu-ray discs
(chroot) # flatpak install flathub com.makemkv.MakeMKV

(Optional) Install ONLYOFFICE
(chroot) # flatpak install flathub org.onlyoffice.desktopeditors

(Optional) Install ungoogled-chromium (benefits of chromium with privacy drawbacks of Google)
(chroot) # flatpak install flathub com.github.Eloston.UngoogledChromium



FINALIZATION

Use xbps-reconfigure(1) to ensure all installed packages are configured properly
(chroot) # xbps-reconfigure -fa

Exit the chroot and reboot
(chroot) # exit
# reboot



POST INSTALL

Fix SDDM's ugliness
Open System Settings > Startup and Shutdown > Login Screen (SDDM), click "Apply Plasma Settings...",
click Apply, enter password, click Apply in the bottom-right corner, and reboot.



OTHER To Do

figure out reboot & poweroff from terminal without sudo
Set up autocpufreq if on laptop
