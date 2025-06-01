#!/bin/bash

#==============================================#
#     Direct Linux Mint Boot Fix              #
#     Manual GRUB entry replacement           #
#==============================================#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}     Direct Linux Mint Boot Fix           ${NC}"
echo -e "${BLUE}============================================${NC}"
echo

# Get UUIDs
ESP_UUID=$(sudo blkid -s UUID -o value /dev/sda1)
DATA_UUID=$(sudo blkid -s UUID -o value /dev/sda2)

print_info "ESP UUID: $ESP_UUID"
print_info "Data UUID: $DATA_UUID"

# Mount ESP
ESP_MOUNT="/mnt/esp_direct_fix"
sudo mkdir -p "$ESP_MOUNT"
sudo mount /dev/sda1 "$ESP_MOUNT"

# Find ISO name
DATA_MOUNT="/mnt/data_direct_fix"
sudo mkdir -p "$DATA_MOUNT"
sudo mount /dev/sda2 "$DATA_MOUNT"

ISO_NAME=$(basename $(ls "$DATA_MOUNT"/linuxmint*.iso 2>/dev/null | head -1))
print_success "Found ISO: $ISO_NAME"

sudo umount "$DATA_MOUNT"
sudo rmdir "$DATA_MOUNT"

# Create backup
BACKUP_FILE="grub.cfg.backup.direct.$(date +%Y%m%d_%H%M%S)"
sudo cp "$ESP_MOUNT/boot/grub/grub.cfg" "$ESP_MOUNT/boot/grub/$BACKUP_FILE"
print_success "Backup created: $BACKUP_FILE"

# Create the working Linux Mint entries directly
print_info "Adding direct Linux Mint boot entries..."

# Remove old Linux Mint template entries
sudo sed -i '/^# Linuxmint$/,/^}$/d' "$ESP_MOUNT/boot/grub/grub.cfg"
sudo sed -i '/^!menuentry "Linux Mint Live ISO"/,/^!}$/d' "$ESP_MOUNT/boot/grub/grub.cfg"

# Add new working entries before the reboot entry
sudo sed -i '/menuentry .Reboot Computer./i\
#==============================================#\
# WORKING LINUX MINT ENTRIES - DIRECT FIX     #\
#==============================================#\
\
# Linux Mint 22.1 - Enhanced Boot (TORAM for USB stability)\
menuentry "Linux Mint 22.1 - Enhanced Boot (Recommended)" --class mint --class linux {\
    # Load required modules\
    insmod part_gpt\
    insmod exfat\
    insmod iso9660\
    insmod loopback\
    insmod search\
    insmod search_fs_uuid\
    \
    # Search for data partition by UUID with enhanced fallbacks\
    if [ x$feature_platform_search_hint = xy ]; then\
        search --no-floppy --fs-uuid --set=root --hint-bios=hd0,gpt2 --hint-efi=hd0,gpt2 --hint-baremetal=ahci0,gpt2 '"$DATA_UUID"'\
    else\
        search --no-floppy --fs-uuid --set=root '"$DATA_UUID"'\
    fi\
    \
    # Fallback to direct device reference if UUID search fails\
    if [ -z "$root" ]; then\
        set root=hd0,gpt2\
    fi\
    \
    # Set ISO file and create loopback\
    set isofile="/'"$ISO_NAME"'"\
    \
    # Enhanced loopback with error checking\
    if loopback loop $isofile; then\
        if [ -f (loop)/casper/vmlinuz ]; then\
            # TORAM boot - loads everything to RAM, bypassing USB issues\
            linux (loop)/casper/vmlinuz boot=casper findiso=${isofile} toram noeject cdrom-detect/try-usb=true quiet splash plymouth.ignore-serial-consoles ---\
            initrd (loop)/casper/initrd.lz\
        else\
            echo "Error: Cannot find kernel in ISO"\
            echo "Press any key to return to menu..."\
            read\
        fi\
    else\
        echo "Error: Cannot mount ISO as loopback device"\
        echo "This indicates USB or filesystem issues"\
        echo "Press any key to return to menu..."\
        read\
    fi\
}\
\
# Linux Mint 22.1 - Maximum Compatibility (for older hardware)\
menuentry "Linux Mint 22.1 - Maximum Compatibility" --class mint --class linux {\
    insmod part_gpt\
    insmod exfat\
    insmod iso9660\
    insmod loopback\
    \
    # Direct device reference for maximum compatibility\
    set root=hd0,gpt2\
    set isofile="/'"$ISO_NAME"'"\
    \
    # Simple loopback without advanced features\
    loopback loop $isofile\
    linux (loop)/casper/vmlinuz boot=casper findiso=${isofile} noeject ---\
    initrd (loop)/casper/initrd.lz\
}\
\
# Linux Mint 22.1 - Alternative Boot Method\
menuentry "Linux Mint 22.1 - Alternative Boot" --class mint --class linux {\
    insmod part_gpt\
    insmod exfat\
    insmod iso9660\
    insmod loopback\
    \
    search --no-floppy --fs-uuid --set=root '"$DATA_UUID"'\
    set isofile="/'"$ISO_NAME"'"\
    loopback loop $isofile\
    \
    # Use iso-scan method instead of findiso\
    linux (loop)/casper/vmlinuz boot=casper iso-scan/filename=${isofile} noeject quiet splash ---\
    initrd (loop)/casper/initrd.lz\
}\
\
# Linux Mint 22.1 - Debug Mode (verbose output)\
menuentry "Linux Mint 22.1 - Debug Mode" --class mint --class linux {\
    insmod part_gpt\
    insmod exfat\
    insmod iso9660\
    insmod loopback\
    \
    search --no-floppy --fs-uuid --set=root '"$DATA_UUID"'\
    set isofile="/'"$ISO_NAME"'"\
    loopback loop $isofile\
    \
    # Verbose boot for troubleshooting\
    linux (loop)/casper/vmlinuz boot=casper findiso=${isofile} debug systemd.log_level=debug systemd.log_target=console console=tty0 ---\
    initrd (loop)/casper/initrd.lz\
}\
\
' "$ESP_MOUNT/boot/grub/grub.cfg"

print_success "Working Linux Mint entries added"

# Verify syntax
if sudo grub-script-check "$ESP_MOUNT/boot/grub/grub.cfg"; then
    print_success "GRUB configuration syntax is valid"
else
    print_error "GRUB syntax error - restoring backup"
    sudo cp "$ESP_MOUNT/boot/grub/$BACKUP_FILE" "$ESP_MOUNT/boot/grub/grub.cfg"
fi

# Sync and unmount
sync
sudo umount "$ESP_MOUNT"
sudo rmdir "$ESP_MOUNT"

echo
print_success "Direct Linux Mint boot fix completed!"
echo
print_info "🚀 Available Linux Mint Boot Options:"
echo "  1. Linux Mint 22.1 - Enhanced Boot (Recommended) ⭐"
echo "     └─ TORAM boot - loads to RAM, best for USB issues"
echo "  2. Linux Mint 22.1 - Maximum Compatibility"
echo "     └─ Simple boot for older hardware"
echo "  3. Linux Mint 22.1 - Alternative Boot" 
echo "     └─ Uses iso-scan method instead of findiso"
echo "  4. Linux Mint 22.1 - Debug Mode"
echo "     └─ Verbose output for troubleshooting"
echo
print_warning "Try the Enhanced Boot (TORAM) option first!"
print_info "It loads the system to RAM and bypasses USB stability issues." 