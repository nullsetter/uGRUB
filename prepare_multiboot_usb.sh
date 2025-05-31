#!/bin/bash

#==============================================#
#     Multiboot USB Preparation Script        #
#     Based on uGRUB by Aditya Shakya         #
#==============================================#

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRUB_CONFIG_DIR="$SCRIPT_DIR/grub"
ISOS_DIR="$SCRIPT_DIR/isos"

# Functions
print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}    Multiboot USB Preparation Script      ${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root initially."
        print_info "The script will ask for sudo privileges when needed."
        exit 1
    fi
}

check_dependencies() {
    print_info "Checking dependencies..."
    
    local deps=("fdisk" "mkfs.exfat" "grub-install" "lsblk" "blkid" "mount" "umount")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_info "Please install the missing packages and try again."
        print_info ""
        print_info "For Ubuntu/Debian: sudo apt install fdisk exfatprogs grub2-common grub-pc-bin grub-efi-amd64-bin util-linux"
        print_info "For Arch Linux: sudo pacman -S util-linux exfatprogs grub"
        print_info "For Fedora/CentOS: sudo dnf install util-linux exfatprogs grub2-tools grub2-efi-x64"
        exit 1
    fi
    
    print_success "All dependencies found"
}

detect_usb_devices() {
    print_info "Detecting USB devices..."
    
    # Get detailed information about USB devices
    local usb_devices=()
    local device_info=()
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local name=$(echo "$line" | awk '{print $1}')
            local size=$(echo "$line" | awk '{print $2}')
            local type=$(echo "$line" | awk '{print $3}')
            local tran=$(echo "$line" | awk '{print $4}')
            local model=$(echo "$line" | awk '{$1=$2=$3=$4=""; print $0}' | sed 's/^ *//')
            
            # Only include actual disks (not rom/optical drives)
            if [[ "$type" == "disk" && "$tran" == "usb" ]]; then
                usb_devices+=("/dev/$name ($size)")
                device_info+=("$name|$size|$type|$tran|$model")
            fi
        fi
    done < <(lsblk -dno NAME,SIZE,TYPE,TRAN,MODEL | grep usb)
    
    if [[ ${#usb_devices[@]} -eq 0 ]]; then
        print_error "No USB flash drives found!"
        print_info "Found these USB devices (not suitable for multiboot):"
        
        # Show all USB devices for reference
        echo
        printf "%-12s %-8s %-6s %-8s %s\n" "DEVICE" "SIZE" "TYPE" "TRANSPORT" "MODEL"
        printf "%-12s %-8s %-6s %-8s %s\n" "------" "----" "----" "---------" "-----"
        
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local name=$(echo "$line" | awk '{print $1}')
                local size=$(echo "$line" | awk '{print $2}')
                local type=$(echo "$line" | awk '{print $3}')
                local tran=$(echo "$line" | awk '{print $4}')
                local model=$(echo "$line" | awk '{$1=$2=$3=$4=""; print $0}' | sed 's/^ *//')
                
                printf "%-12s %-8s %-6s %-8s %s\n" "/dev/$name" "$size" "$type" "$tran" "$model"
                
                if [[ "$type" == "rom" ]]; then
                    echo "  └─ This is an optical drive (CD/DVD) - cannot be used"
                fi
            fi
        done < <(lsblk -dno NAME,SIZE,TYPE,TRAN,MODEL | grep usb)
        
        echo
        print_info "Please insert a USB flash drive and try again."
        exit 1
    fi
    
    echo
    print_success "Found ${#usb_devices[@]} USB flash drive(s):"
    echo
    printf "%-4s %-15s %-8s %-6s %-8s %s\n" "NUM" "DEVICE" "SIZE" "TYPE" "TRANSPORT" "MODEL"
    printf "%-4s %-15s %-8s %-6s %-8s %s\n" "---" "------" "----" "----" "---------" "-----"
    
    for i in "${!usb_devices[@]}"; do
        local info="${device_info[i]}"
        local name=$(echo "$info" | cut -d'|' -f1)
        local size=$(echo "$info" | cut -d'|' -f2)
        local type=$(echo "$info" | cut -d'|' -f3)
        local tran=$(echo "$info" | cut -d'|' -f4)
        local model=$(echo "$info" | cut -d'|' -f5)
        
        printf "%-4s %-15s %-8s %-6s %-8s %s\n" "$((i+1))." "/dev/$name" "$size" "$type" "$tran" "$model"
    done
    
    echo
    print_info "💡 How to identify your USB flash drive:"
    print_info "   • TYPE should be 'disk' (not 'rom' for CD/DVD)"
    print_info "   • TRANSPORT should be 'usb'"
    print_info "   • SIZE should match your USB drive capacity"
    print_info "   • MODEL might show your USB brand/model"
    echo
    
    local choice
    while true; do
        read -p "Select USB flash drive (1-${#usb_devices[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#usb_devices[@]} )); then
            local selected_info="${device_info[$((choice-1))]}"
            USB_DEVICE="/dev/$(echo "$selected_info" | cut -d'|' -f1)"
            USB_SIZE=$(echo "$selected_info" | cut -d'|' -f2)
            local usb_model=$(echo "$selected_info" | cut -d'|' -f5)
            
            print_success "Selected: $USB_DEVICE ($USB_SIZE) - $usb_model"
            break
        else
            print_error "Invalid choice. Please enter a number between 1 and ${#usb_devices[@]}."
        fi
    done
}

check_usb_ready() {
    print_info "Checking if USB device is ready..."
    
    # Check if device exists
    if [[ ! -e "$USB_DEVICE" ]]; then
        print_error "USB device $USB_DEVICE not found"
        exit 1
    fi
    
    # Check if device is accessible
    if ! sudo fdisk -l "$USB_DEVICE" > /dev/null 2>&1; then
        print_error "Cannot access USB device $USB_DEVICE"
        print_info "Try unplugging and reconnecting the USB drive"
        exit 1
    fi
    
    # Check for any processes using the device
    local using_processes=$(sudo fuser "$USB_DEVICE"* 2>/dev/null || true)
    if [[ -n "$using_processes" ]]; then
        print_warning "Found processes using the USB device:"
        sudo fuser -v "$USB_DEVICE"* 2>/dev/null || true
        echo
        read -p "Kill these processes and continue? (y/n): " kill_procs
        if [[ "$kill_procs" == "y" || "$kill_procs" == "Y" ]]; then
            sudo fuser -k "$USB_DEVICE"* 2>/dev/null || true
            sleep 2
        else
            print_info "Please close any applications using the USB device and try again"
            exit 1
        fi
    fi
    
    print_success "USB device is ready"
}

confirm_usb_format() {
    echo
    print_warning "WARNING: All data on $USB_DEVICE will be PERMANENTLY LOST!"
    print_warning "Make sure you have selected the correct device."
    echo
    
    local confirm
    while true; do
        read -p "Are you sure you want to format $USB_DEVICE? (yes/no): " confirm
        case "$confirm" in
            yes|YES|y|Y)
                break
                ;;
            no|NO|n|N)
                print_info "Operation cancelled by user."
                exit 0
                ;;
            *)
                print_error "Please answer 'yes' or 'no'."
                ;;
        esac
    done
}

partition_usb() {
    print_info "Partitioning USB device $USB_DEVICE..."
    
    # More thorough device cleanup
    print_info "Cleaning up device before partitioning..."
    
    # Kill any processes using the device
    sudo fuser -k "$USB_DEVICE"* 2>/dev/null || true
    sleep 1
    
    # Unmount all partitions on the device
    for partition in "${USB_DEVICE}"*; do
        if [[ "$partition" != "$USB_DEVICE" ]]; then
            sudo umount "$partition" 2>/dev/null || true
        fi
    done
    
    # Wait a bit for cleanup
    sleep 2
    
    # Check current partition table
    print_info "Checking current partition table..."
    sudo fdisk -l "$USB_DEVICE" | grep "^${USB_DEVICE}" || true
    
    # Detect if UEFI system and create appropriate partition table
    if [[ -d "/sys/firmware/efi" ]]; then
        print_info "Creating GPT partition table for UEFI compatibility..."
        
        # Use GPT for better UEFI compatibility
        cat << 'EOF' | sudo sfdisk --force "$USB_DEVICE"
label: gpt
type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, bootable
EOF
    else
        print_info "Creating MBR partition table for BIOS compatibility..."
        
        # Use MBR for BIOS systems
        cat << 'EOF' | sudo sfdisk --force "$USB_DEVICE"
label: dos
type=c, bootable
EOF
    fi
    
    if [[ $? -ne 0 ]]; then
        print_warning "sfdisk failed, trying with fdisk..."
        
        if [[ -d "/sys/firmware/efi" ]]; then
            # UEFI system - use GPT with fdisk
            (timeout 30 sudo fdisk "$USB_DEVICE" << 'EOF'
g
n
1


t
1
w
EOF
) || {
                print_error "Partitioning failed - device may be in use"
                print_info "Try unplugging and reconnecting the USB drive"
                exit 1
            }
        else
            # BIOS system - use MBR with fdisk
            (timeout 30 sudo fdisk "$USB_DEVICE" << 'EOF'
o
n
p
1


a
t
c
w
EOF
) || {
                print_error "Partitioning failed - device may be in use"
                print_info "Try unplugging and reconnecting the USB drive"
                exit 1
            }
        fi
    fi
    
    # Force kernel to re-read partition table
    sudo partprobe "$USB_DEVICE" 2>/dev/null || true
    
    # Wait longer for partition to be recognized
    print_info "Waiting for partition to be recognized..."
    sleep 5
    
    # Check if partition was created
    if [[ ! -e "${USB_DEVICE}1" ]]; then
        print_error "Partition ${USB_DEVICE}1 was not created"
        print_info "Available partitions:"
        ls -la "${USB_DEVICE}"* || true
        exit 1
    fi
    
    print_success "USB device partitioned successfully"
}

format_usb() {
    print_info "Formatting USB partition..."
    
    local partition="${USB_DEVICE}1"
    
    # Wait for partition to be available
    local count=0
    while [[ ! -e "$partition" && $count -lt 10 ]]; do
        sleep 1
        ((count++))
        print_info "Waiting for partition to be available... ($count/10)"
    done
    
    if [[ ! -e "$partition" ]]; then
        print_error "Partition $partition not found after partitioning"
        exit 1
    fi
    
    # Format as FAT32
    sudo mkfs.exfat -n "Multiboot" "$partition"
    
    print_success "USB partition formatted as exFAT"
}

install_grub() {
    print_info "Installing GRUB bootloader..."
    
    local mount_point="/mnt/multiboot_usb"
    local partition="${USB_DEVICE}1"
    
    # Create mount point and mount
    sudo mkdir -p "$mount_point"
    sudo mount "$partition" "$mount_point"
    
    # Detect boot mode (UEFI or BIOS)
    local grub_target
    if [[ -d "/sys/firmware/efi" ]]; then
        print_info "UEFI system detected"
        if [[ "$(uname -m)" == "x86_64" ]]; then
            grub_target="x86_64-efi"
        else
            grub_target="i386-efi"
        fi
        
        # Install GRUB for UEFI
        sudo grub-install --force --removable --target="$grub_target" \
                         --boot-directory="$mount_point/boot" \
                         --efi-directory="$mount_point" "$USB_DEVICE"
    else
        print_info "BIOS system detected"
        grub_target="i386-pc"
        
        # Install GRUB for BIOS
        sudo grub-install --force --removable --target="$grub_target" \
                         --boot-directory="$mount_point/boot" "$USB_DEVICE"
    fi
    
    if [[ $? -eq 0 ]]; then
        print_success "GRUB installed successfully"
    else
        print_error "GRUB installation failed"
        sudo umount "$mount_point"
        exit 1
    fi
    
    # Unmount
    sudo umount "$mount_point"
    sudo rmdir "$mount_point"
}

copy_grub_config() {
    print_info "Copying GRUB configuration files..."
    
    local mount_point="/mnt/multiboot_usb"
    local partition="${USB_DEVICE}1"
    
    # Mount the USB
    sudo mkdir -p "$mount_point"
    sudo mount "$partition" "$mount_point"
    
    # Copy GRUB configuration
    if [[ -d "$GRUB_CONFIG_DIR" ]]; then
        sudo cp -rf "$GRUB_CONFIG_DIR"/* "$mount_point/boot/grub/"
        print_success "GRUB configuration files copied"
    else
        print_error "GRUB configuration directory not found: $GRUB_CONFIG_DIR"
        sudo umount "$mount_point"
        exit 1
    fi
    
    # Unmount
    sudo umount "$mount_point"
    sudo rmdir "$mount_point"
}

get_usb_uuid() {
    print_info "Getting USB UUID..."
    
    local partition="${USB_DEVICE}1"
    USB_UUID=$(sudo blkid -s UUID -o value "$partition")
    
    if [[ -n "$USB_UUID" ]]; then
        print_success "USB UUID: $USB_UUID"
    else
        print_error "Failed to get USB UUID"
        exit 1
    fi
}

update_grub_config() {
    print_info "Updating GRUB configuration with USB UUID..."
    
    local mount_point="/mnt/multiboot_usb"
    local partition="${USB_DEVICE}1"
    
    # Mount the USB
    sudo mkdir -p "$mount_point"
    sudo mount "$partition" "$mount_point"
    
    # Update grub.cfg with the actual UUID
    sudo sed -i "s/YOUR_UUID/$USB_UUID/g" "$mount_point/boot/grub/grub.cfg"
    
    print_success "GRUB configuration updated with UUID"
    
    # Unmount
    sudo umount "$mount_point"
    sudo rmdir "$mount_point"
}

copy_iso_files() {
    print_info "Copying ISO files..."
    
    if [[ ! -d "$ISOS_DIR" ]]; then
        print_warning "ISOs directory not found: $ISOS_DIR"
        print_info "Creating ISOs directory..."
        mkdir -p "$ISOS_DIR"
        print_info "Please place your ISO files in: $ISOS_DIR"
        return
    fi
    
    local iso_files=($(find "$ISOS_DIR" -name "*.iso" -type f))
    
    if [[ ${#iso_files[@]} -eq 0 ]]; then
        print_warning "No ISO files found in $ISOS_DIR"
        print_info "You can add ISO files later to the root of the USB drive"
        return
    fi
    
    local mount_point="/mnt/multiboot_usb"
    local partition="${USB_DEVICE}1"
    
    # Mount the USB
    sudo mkdir -p "$mount_point"
    sudo mount "$partition" "$mount_point"
    
    # Check available space
    local available_space_kb=$(df "$mount_point" | tail -1 | awk '{print $4}')
    local available_space_gb=$((available_space_kb / 1024 / 1024))
    
    print_info "Available space on USB: ${available_space_gb}GB"
    
    # Calculate total ISO size
    local total_size_kb=0
    print_info "Found ${#iso_files[@]} ISO file(s):"
    
    for iso in "${iso_files[@]}"; do
        local iso_name=$(basename "$iso")
        local iso_size_kb=$(du -k "$iso" | cut -f1)
        local iso_size_gb=$((iso_size_kb / 1024 / 1024))
        total_size_kb=$((total_size_kb + iso_size_kb))
        printf "  - %-50s (%dGB)\n" "$iso_name" "$iso_size_gb"
    done
    
    local total_size_gb=$((total_size_kb / 1024 / 1024))
    print_info "Total ISO size: ${total_size_gb}GB"
    
    # Check if there's enough space (with 1GB buffer)
    local required_space_gb=$((total_size_gb + 1))
    if [[ $available_space_gb -lt $required_space_gb ]]; then
        print_error "Insufficient space! Need ${required_space_gb}GB, have ${available_space_gb}GB"
        print_info "Consider using a larger USB drive or removing some ISO files"
        sudo umount "$mount_point"
        sudo rmdir "$mount_point"
        return
    fi
    
    echo
    local copy_isos
    read -p "Copy ${#iso_files[@]} ISO file(s) to USB? (y/n): " copy_isos
    
    if [[ "$copy_isos" == "y" || "$copy_isos" == "Y" ]]; then
        for iso in "${iso_files[@]}"; do
            local iso_name=$(basename "$iso")
            local iso_size_kb=$(du -k "$iso" | cut -f1)
            local iso_size_gb=$((iso_size_kb / 1024 / 1024))
            
            print_info "Copying $iso_name (${iso_size_gb}GB)..."
            print_info "This may take several minutes for large files..."
            
            # Copy with progress using pv if available, otherwise use cp with periodic updates
            if command -v pv &> /dev/null; then
                sudo pv "$iso" > "$mount_point/$iso_name"
            else
                # Use rsync for better progress feedback if available
                if command -v rsync &> /dev/null; then
                    sudo rsync --progress --partial "$iso" "$mount_point/"
                else
                    # Fallback to cp with simple progress indication
                    print_info "Copying without progress indication (this may take several minutes)..."
                    sudo cp "$iso" "$mount_point/" && print_success "Copy completed"
                fi
            fi
        done
    fi
    
    # Unmount
    sudo umount "$mount_point"
    sudo rmdir "$mount_point"
}

generate_menu_entries() {
    print_info "Analyzing ISO files and generating menu entries..."
    
    local mount_point="/mnt/multiboot_usb"
    local partition="${USB_DEVICE}1"
    
    # Mount the USB with error handling
    sudo mkdir -p "$mount_point"
    if ! sudo mount "$partition" "$mount_point"; then
        print_error "Failed to mount USB for menu generation"
        return 1
    fi
    
    # Find ISO files on the USB
    local iso_files=($(find "$mount_point" -maxdepth 1 -name "*.iso" -type f 2>/dev/null))
    
    if [[ ${#iso_files[@]} -eq 0 ]]; then
        print_info "No ISO files found on USB. Menu entries can be configured manually later."
        sudo umount "$mount_point" 2>/dev/null || true
        sudo rmdir "$mount_point" 2>/dev/null || true
        return 0
    fi
    
    print_info "Found ${#iso_files[@]} ISO file(s) on USB, updating menu entries..."
    
    # Create a backup of the original config
    if [[ -f "$mount_point/boot/grub/grub.cfg" ]]; then
        sudo cp "$mount_point/boot/grub/grub.cfg" "$mount_point/boot/grub/grub.cfg.backup" 2>/dev/null || true
        
        # Auto-enable menu entries based on found ISO files
        for iso_path in "${iso_files[@]}"; do
            local iso_name=$(basename "$iso_path")
            local iso_lower=$(echo "$iso_name" | tr '[:upper:]' '[:lower:]')
            
            print_info "Processing menu entry for $iso_name..."
            
            # Update the grub.cfg to uncomment relevant entries and update paths (with error handling)
            if [[ "$iso_lower" == *"ubuntu"* ]]; then
                sudo sed -i "s|!menuentry \"Ubuntu.*|menuentry \"$iso_name\" --class ubuntu --class linux {|g" "$mount_point/boot/grub/grub.cfg" 2>/dev/null || true
                sudo sed -i "s|/ubuntu-.*\.iso|/$iso_name|g" "$mount_point/boot/grub/grub.cfg" 2>/dev/null || true
            elif [[ "$iso_lower" == *"kubuntu"* ]]; then
                sudo sed -i "s|!menuentry \".*Kubuntu.*|menuentry \"$iso_name\" --class kubuntu --class linux {|g" "$mount_point/boot/grub/grub.cfg" 2>/dev/null || true
                sudo sed -i "s|/kubuntu-.*\.iso|/$iso_name|g" "$mount_point/boot/grub/grub.cfg" 2>/dev/null || true
            elif [[ "$iso_lower" == *"mint"* ]]; then
                sudo sed -i "s|!menuentry \".*Mint.*|menuentry \"$iso_name\" --class mint --class linux {|g" "$mount_point/boot/grub/grub.cfg" 2>/dev/null || true
                sudo sed -i "s|/linuxmint-.*\.iso|/$iso_name|g" "$mount_point/boot/grub/grub.cfg" 2>/dev/null || true
            elif [[ "$iso_lower" == *"arch"* ]]; then
                sudo sed -i "s|!menuentry \"Arch Linux.*|menuentry \"$iso_name\" --class arch --class linux {|g" "$mount_point/boot/grub/grub.cfg" 2>/dev/null || true
                sudo sed -i "s|/archlinux-.*\.iso|/$iso_name|g" "$mount_point/boot/grub/grub.cfg" 2>/dev/null || true
            fi
            
            print_success "Processed menu entry for $iso_name"
        done
    else
        print_warning "GRUB config file not found, skipping menu generation"
    fi
    
    # Unmount with error handling
    sudo umount "$mount_point" 2>/dev/null || true
    sudo rmdir "$mount_point" 2>/dev/null || true
    
    print_success "Menu entry generation completed"
}

show_completion_info() {
    echo
    print_success "Multiboot USB creation completed successfully!"
    echo
    print_info "Next steps:"
    echo "  1. Reboot your computer"
    echo "  2. Enter BIOS/UEFI boot menu (usually F12, F10, or ESC during startup)"
    echo "  3. Select your USB device as the boot option"
    echo "  4. Choose your desired ISO from the GRUB menu"
    echo
    print_info "USB Details:"
    echo "  Device: $USB_DEVICE"
    echo "  Size: $USB_SIZE"
    echo "  Filesystem: exFAT (supports files > 4GB)"
    echo "  UUID: $USB_UUID"
    echo
    print_info "To add more ISOs later:"
    echo "  1. Mount the USB drive"
    echo "  2. Copy ISO files to the root directory (any size supported)"
    echo "  3. Edit /boot/grub/grub.cfg to add menu entries"
    echo
    print_info "ISO storage location: Root of USB drive"
    print_info "Configuration backup: /boot/grub/grub.cfg.backup"
}

# Main execution
main() {
    print_header
    
    check_root
    check_dependencies
    detect_usb_devices
    check_usb_ready
    confirm_usb_format
    
    print_info "Starting multiboot USB preparation..."
    
    partition_usb
    format_usb
    install_grub
    copy_grub_config
    get_usb_uuid
    update_grub_config
    copy_iso_files
    generate_menu_entries
    
    show_completion_info
}

# Run main function
main "$@" 