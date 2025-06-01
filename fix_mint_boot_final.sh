#!/bin/bash

#==============================================#
#     Final Linux Mint Boot Fix Script        #
#     Comprehensive fix for all boot issues   #
#==============================================#

set -e

# Colors for output
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
echo -e "${BLUE}    Final Linux Mint Boot Fix Script      ${NC}"
echo -e "${BLUE}============================================${NC}"
echo

# Detect the USB device
print_info "Detecting USB device..."
USB_DEVICE=$(lsblk -no NAME,TRAN | grep usb | head -1 | awk '{print "/dev/" $1}')

if [[ -z "$USB_DEVICE" ]]; then
    print_error "No USB device found"
    exit 1
fi

print_success "Found USB device: $USB_DEVICE"

# Get UUIDs
ESP_UUID=$(sudo blkid -s UUID -o value "${USB_DEVICE}1" 2>/dev/null || true)
DATA_UUID=$(sudo blkid -s UUID -o value "${USB_DEVICE}2" 2>/dev/null || true)

print_info "ESP UUID: $ESP_UUID"
print_info "Data UUID: $DATA_UUID"

# Create comprehensive fix
print_info "Creating comprehensive Linux Mint boot fix..."

# Mount ESP
ESP_MOUNT="/mnt/usb_esp_fix"
sudo mkdir -p "$ESP_MOUNT"
sudo mount "${USB_DEVICE}1" "$ESP_MOUNT"

# Create backup
BACKUP_FILE="grub.cfg.backup.comprehensive.$(date +%Y%m%d_%H%M%S)"
sudo cp "$ESP_MOUNT/boot/grub/grub.cfg" "$ESP_MOUNT/boot/grub/$BACKUP_FILE"
print_success "Backup created: $BACKUP_FILE"

# Check for Linux Mint ISO
DATA_MOUNT="/mnt/usb_data_fix"
sudo mkdir -p "$DATA_MOUNT"
sudo mount "${USB_DEVICE}2" "$DATA_MOUNT"

MINT_ISO=$(ls "$DATA_MOUNT"/linuxmint*.iso 2>/dev/null | head -1)
if [[ -z "$MINT_ISO" ]]; then
    print_error "No Linux Mint ISO found on data partition"
    sudo umount "$DATA_MOUNT" "$ESP_MOUNT"
    sudo rmdir "$DATA_MOUNT" "$ESP_MOUNT"
    exit 1
fi

ISO_NAME=$(basename "$MINT_ISO")
print_success "Found Linux Mint ISO: $ISO_NAME"

# Remove all existing problematic Linux Mint entries
print_info "Removing problematic Linux Mint entries..."
sudo sed -i '/# Enhanced Linux Mint Entry/,/^}$/d' "$ESP_MOUNT/boot/grub/grub.cfg"
sudo sed -i '/# Linux Mint - Enhanced Boot/,/^}$/d' "$ESP_MOUNT/boot/grub/grub.cfg"
sudo sed -i '/# Linux Mint - Alternative Method/,/^}$/d' "$ESP_MOUNT/boot/grub/grub.cfg"
sudo sed -i '/# Linux Mint - Alternative Boot/,/^}$/d' "$ESP_MOUNT/boot/grub/grub.cfg"
sudo sed -i '/# mint - linuxmint.*\.iso/,/^}$/d' "$ESP_MOUNT/boot/grub/grub.cfg"

# Add the definitive working Linux Mint entries
print_info "Adding comprehensive Linux Mint boot entries..."

# Insert the new entries right before the Poweroff System entry
sudo sed -i '/# Poweroff System/i\
# =============================================================================\
# COMPREHENSIVE LINUX MINT BOOT ENTRIES (FIXED)\
# =============================================================================\
\
# Linux Mint 22.1 - Method 1: Standard Boot with findiso\
menuentry "Linux Mint 22.1 - Standard Boot" --class mint --class linux {\
    # Load all required modules\
    insmod part_gpt\
    insmod part_msdos\
    insmod exfat\
    insmod fat\
    insmod iso9660\
    insmod loopback\
    \
    # Set root to data partition using UUID search\
    if [ x$feature_platform_search_hint = xy ]; then\
        search --no-floppy --fs-uuid --set=root --hint-bios=hd0,gpt2 --hint-efi=hd0,gpt2 --hint-baremetal=ahci0,gpt2 '$DATA_UUID'\
    else\
        search --no-floppy --fs-uuid --set=root '$DATA_UUID'\
    fi\
    \
    # Set ISO file and load as loopback\
    set isofile="/'$ISO_NAME'"\
    loopback loop $isofile\
    \
    # Boot with comprehensive parameters\
    linux (loop)/casper/vmlinuz boot=casper findiso=${isofile} quiet splash ---\
    initrd (loop)/casper/initrd.lz\
}\
\
# Linux Mint 22.1 - Method 2: Boot with TORAM (loads everything to RAM)\
menuentry "Linux Mint 22.1 - TORAM Boot (Recommended)" --class mint --class linux {\
    insmod part_gpt\
    insmod part_msdos\
    insmod exfat\
    insmod fat\
    insmod iso9660\
    insmod loopback\
    \
    if [ x$feature_platform_search_hint = xy ]; then\
        search --no-floppy --fs-uuid --set=root --hint-bios=hd0,gpt2 --hint-efi=hd0,gpt2 --hint-baremetal=ahci0,gpt2 '$DATA_UUID'\
    else\
        search --no-floppy --fs-uuid --set=root '$DATA_UUID'\
    fi\
    \
    set isofile="/'$ISO_NAME'"\
    loopback loop $isofile\
    \
    # TORAM loads the entire system to RAM, freeing up the USB\
    linux (loop)/casper/vmlinuz boot=casper findiso=${isofile} toram quiet splash ---\
    initrd (loop)/casper/initrd.lz\
}\
\
# Linux Mint 22.1 - Method 3: Alternative boot with iso-scan\
menuentry "Linux Mint 22.1 - Alternative Boot" --class mint --class linux {\
    insmod part_gpt\
    insmod part_msdos\
    insmod exfat\
    insmod fat\
    insmod iso9660\
    insmod loopback\
    \
    if [ x$feature_platform_search_hint = xy ]; then\
        search --no-floppy --fs-uuid --set=root --hint-bios=hd0,gpt2 --hint-efi=hd0,gpt2 --hint-baremetal=ahci0,gpt2 '$DATA_UUID'\
    else\
        search --no-floppy --fs-uuid --set=root '$DATA_UUID'\
    fi\
    \
    set isofile="/'$ISO_NAME'"\
    loopback loop $isofile\
    \
    # Alternative method using iso-scan\
    linux (loop)/casper/vmlinuz boot=casper iso-scan/filename=${isofile} quiet splash ---\
    initrd (loop)/casper/initrd.lz\
}\
\
# Linux Mint 22.1 - Method 4: Troubleshooting mode (verbose)\
menuentry "Linux Mint 22.1 - Troubleshooting Mode" --class mint --class linux {\
    insmod part_gpt\
    insmod part_msdos\
    insmod exfat\
    insmod fat\
    insmod iso9660\
    insmod loopback\
    \
    if [ x$feature_platform_search_hint = xy ]; then\
        search --no-floppy --fs-uuid --set=root --hint-bios=hd0,gpt2 --hint-efi=hd0,gpt2 --hint-baremetal=ahci0,gpt2 '$DATA_UUID'\
    else\
        search --no-floppy --fs-uuid --set=root '$DATA_UUID'\
    fi\
    \
    set isofile="/'$ISO_NAME'"\
    loopback loop $isofile\
    \
    # Verbose boot for troubleshooting\
    linux (loop)/casper/vmlinuz boot=casper findiso=${isofile} debug\
    initrd (loop)/casper/initrd.lz\
}\
\
' "$ESP_MOUNT/boot/grub/grub.cfg"

print_success "Added 4 comprehensive Linux Mint boot entries"

# Verify GRUB configuration syntax
print_info "Verifying GRUB configuration syntax..."
if sudo grub-script-check "$ESP_MOUNT/boot/grub/grub.cfg"; then
    print_success "GRUB configuration syntax is valid"
else
    print_error "GRUB configuration has syntax errors"
    print_info "Restoring backup..."
    sudo cp "$ESP_MOUNT/boot/grub/$BACKUP_FILE" "$ESP_MOUNT/boot/grub/grub.cfg"
    sudo umount "$DATA_MOUNT" "$ESP_MOUNT"
    sudo rmdir "$DATA_MOUNT" "$ESP_MOUNT"
    exit 1
fi

# Cleanup
sudo umount "$DATA_MOUNT" "$ESP_MOUNT"
sudo rmdir "$DATA_MOUNT" "$ESP_MOUNT"

echo
print_success "Comprehensive Linux Mint boot fix completed!"
echo
print_info "Available boot options:"
echo "  1. Linux Mint 22.1 - Standard Boot"
echo "  2. Linux Mint 22.1 - TORAM Boot (Recommended) ⭐"
echo "  3. Linux Mint 22.1 - Alternative Boot"
echo "  4. Linux Mint 22.1 - Troubleshooting Mode"
echo
print_info "Recommended order to try:"
echo "  1. Try 'TORAM Boot' first (loads everything to RAM)"
echo "  2. If that fails, try 'Standard Boot'"
echo "  3. If still failing, try 'Alternative Boot'"
echo "  4. Use 'Troubleshooting Mode' to see detailed error messages"
echo
print_warning "Note: TORAM boot requires at least 4GB RAM but is most reliable"
print_success "Your USB is now ready for testing!" 