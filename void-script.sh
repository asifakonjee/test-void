#!/bin/bash

set -e

# Set variables
DISK="/dev/nvme0n1"
EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"
HOME_PART="${DISK}p3"
HOSTNAME="Linux"
USERNAME="asifakonjee"
SWAPFILE_SIZE=16G

# Prompt for user password
echo "Enter password for user $USERNAME:"
read -s USER_PASSWORD
echo "Confirm password:"
read -s USER_PASSWORD_CONFIRM

# Check if passwords match
if [ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]; then
  echo "Passwords do not match. Exiting."
  exit 1
fi

# Partition and Format
mkfs.fat -F32 $EFI_PART  # Format EFI partition
mkfs.btrfs -L root $ROOT_PART  # Format Btrfs root partition
# DO NOT format $HOME_PART as it contains existing data

# Mount the Btrfs root partition
mount -o subvol=@,rw,noatime,compress=zstd,ssd,space_cache=v2 $ROOT_PART /mnt

# Create Btrfs subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@log

# Remount the root subvolume
umount /mnt
mount -o subvol=@,rw,noatime,compress=zstd,ssd,space_cache=v2 $ROOT_PART /mnt

# Mount the other subvolumes and partitions
mkdir -p /mnt/home /mnt/var/log /mnt/boot/efi
mount $HOME_PART /mnt/home  # Mount existing /home partition
mount -o subvol=@log $ROOT_PART /mnt/var/log
mount $EFI_PART /mnt/boot/efi  # Mount EFI partition

# Create and Enable Swapfile
truncate -s 0 /mnt/swapfile
chattr +C /mnt/swapfile  # Disable CoW
dd if=/dev/zero of=/mnt/swapfile bs=1M count=$((16 * 1024))  # 16 GB size
chmod 600 /mnt/swapfile
mkswap /mnt/swapfile
swapon /mnt/swapfile

# Install Void Linux base system and required packages
XBPS_ARCH=x86_64 xbps-install -Sy -R https://alpha.de.repo.voidlinux.org/current -r /mnt base-system btrfs-progs void-repo-nonfree intel-ucode

# Generate Fstab
genfstab -U -p /mnt > /mnt/etc/fstab

# Chroot into the New System
cat << EOF | chroot /mnt /bin/bash
# Set variables inside chroot
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
USER_PASSWORD="$USER_PASSWORD"

# Configure Grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=void
grub-mkconfig -o /boot/grub/grub.cfg

# Set Hostname
echo "$HOSTNAME" > /etc/hostname

# Create User Account
useradd -m -g users -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Calculate Resume Offset
resume_offset=\$(filefrag -v /swapfile | awk '/ 0:/ {print \$4}' | sed 's/\..*//')

# Get the UUID of the Btrfs root partition
uuid=\$(blkid -s UUID -o value /dev/nvme0n1p2)

# Update GRUB configuration
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"resume=UUID=\$uuid resume_offset=\$resume_offset loglevel=3\"|" /etc/default/grub

# Regenerate the GRUB configuration
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# Ensure fstab is correctly configured
cat << EOF >> /mnt/etc/fstab
/dev/nvme0n1p1    /boot/efi    vfat    defaults        0       2
/dev/nvme0n1p2    /             btrfs   subvol=@,rw,noatime,compress=zstd,ssd,space_cache=v2  0 1
/dev/nvme0n1p2    /var/log      btrfs   subvol=@log,rw,noatime,compress=zstd,ssd,space_cache=v2  0 2
/dev/nvme0n1p3    /home         btrfs   rw,noatime,compress=zstd,ssd,space_cache=v2  0 2
/swapfile         none          swap    sw              0       0
EOF

# Unmount and Reboot
umount -R /mnt
reboot
