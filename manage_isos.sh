#!/bin/bash

#==============================================#
#     Multiboot USB ISO Management Script     #
#     Companion to uGRUB preparation script   #
#==============================================#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISOS_DIR="$SCRIPT_DIR/isos"

# Functions
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

print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}    Multiboot USB ISO Management         ${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
}

list_available_isos() {
    print_info "Available ISO files in $ISOS_DIR:"
    echo
    
    if [[ ! -d "$ISOS_DIR" ]]; then
        print_warning "ISOs directory doesn't exist: $ISOS_DIR"
        return 1
    fi
    
    local iso_files=($(find "$ISOS_DIR" -name "*.iso" -type f))
    
    if [[ ${#iso_files[@]} -eq 0 ]]; then
        print_warning "No ISO files found in $ISOS_DIR"
        echo "Place your ISO files in the isos/ directory"
        return 1
    fi
    
    for i in "${!iso_files[@]}"; do
        local iso_name=$(basename "${iso_files[i]}")
        local iso_size=$(du -h "${iso_files[i]}" | cut -f1)
        printf "  %2d. %-50s (%s)\n" $((i+1)) "$iso_name" "$iso_size"
    done
    echo
    
    return 0
}

detect_usb_multiboot() {
    print_info "Detecting multiboot USB drives..."
    
    local usb_devices=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local device=$(echo "$line" | awk '{print $1}')
            local size=$(echo "$line" | awk '{print $2}')
            
            # Check if device has grub directory
            local mount_point=$(lsblk -no MOUNTPOINT "/dev/${device}1" 2>/dev/null | head -1)
            if [[ -z "$mount_point" ]]; then
                # Try to mount temporarily
                local temp_mount="/tmp/check_multiboot_$$"
                mkdir -p "$temp_mount"
                if mount "/dev/${device}1" "$temp_mount" 2>/dev/null; then
                    if [[ -d "$temp_mount/boot/grub" ]]; then
                        usb_devices+=("/dev/$device ($size)")
                    fi
                    umount "$temp_mount"
                fi
                rmdir "$temp_mount"
            else
                if [[ -d "$mount_point/boot/grub" ]]; then
                    usb_devices+=("/dev/$device ($size)")
                fi
            fi
        fi
    done < <(lsblk -dno NAME,SIZE,TYPE,TRAN | grep usb | awk '{print $1" "$2}')
    
    if [[ ${#usb_devices[@]} -eq 0 ]]; then
        print_error "No multiboot USB drives found!"
        print_info "Make sure your multiboot USB is connected and properly configured."
        return 1
    fi
    
    echo
    print_info "Available multiboot USB devices:"
    for i in "${!usb_devices[@]}"; do
        echo "  $((i+1)). ${usb_devices[i]}"
    done
    echo
    
    local choice
    while true; do
        read -p "Select multiboot USB device (1-${#usb_devices[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#usb_devices[@]} )); then
            USB_DEVICE=$(echo "${usb_devices[$((choice-1))]}" | cut -d' ' -f1)
            USB_SIZE=$(echo "${usb_devices[$((choice-1))]}" | cut -d'(' -f2 | cut -d')' -f1)
            break
        else
            print_error "Invalid choice. Please enter a number between 1 and ${#usb_devices[@]}."
        fi
    done
    
    print_success "Selected: $USB_DEVICE ($USB_SIZE)"
    return 0
}

copy_isos_to_usb() {
    if ! list_available_isos; then
        return 1
    fi
    
    if ! detect_usb_multiboot; then
        return 1
    fi
    
    local partition="${USB_DEVICE}1"
    local mount_point="/mnt/multiboot_manage_$$"
    
    # Mount the USB
    sudo mkdir -p "$mount_point"
    if ! sudo mount "$partition" "$mount_point"; then
        print_error "Failed to mount USB device"
        sudo rmdir "$mount_point"
        return 1
    fi
    
    local iso_files=($(find "$ISOS_DIR" -name "*.iso" -type f))
    
    echo "Select ISO files to copy (space-separated numbers, 'all' for all, or 'none'):"
    read -p "> " selection
    
    local files_to_copy=()
    
    if [[ "$selection" == "all" ]]; then
        files_to_copy=("${iso_files[@]}")
    elif [[ "$selection" == "none" ]]; then
        print_info "No files selected for copying."
        sudo umount "$mount_point"
        sudo rmdir "$mount_point"
        return 0
    else
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#iso_files[@]} )); then
                files_to_copy+=("${iso_files[$((num-1))]}")
            fi
        done
    fi
    
    if [[ ${#files_to_copy[@]} -eq 0 ]]; then
        print_warning "No valid files selected."
        sudo umount "$mount_point"
        sudo rmdir "$mount_point"
        return 0
    fi
    
    print_info "Copying ${#files_to_copy[@]} ISO file(s) to USB..."
    
    for iso in "${files_to_copy[@]}"; do
        local iso_name=$(basename "$iso")
        
        # Check if file already exists
        if [[ -f "$mount_point/$iso_name" ]]; then
            print_warning "$iso_name already exists on USB"
            read -p "Overwrite? (y/n): " overwrite
            if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
                print_info "Skipping $iso_name"
                continue
            fi
        fi
        
        print_info "Copying $iso_name..."
        if sudo cp "$iso" "$mount_point/"; then
            print_success "Copied $iso_name"
        else
            print_error "Failed to copy $iso_name"
        fi
    done
    
    # Unmount
    sudo umount "$mount_point"
    sudo rmdir "$mount_point"
    
    print_success "ISO copying completed!"
    print_info "Don't forget to update GRUB menu entries if needed."
}

list_usb_isos() {
    if ! detect_usb_multiboot; then
        return 1
    fi
    
    local partition="${USB_DEVICE}1"
    local mount_point="/mnt/multiboot_list_$$"
    
    # Mount the USB
    sudo mkdir -p "$mount_point"
    if ! sudo mount "$partition" "$mount_point"; then
        print_error "Failed to mount USB device"
        sudo rmdir "$mount_point"
        return 1
    fi
    
    print_info "ISO files on multiboot USB:"
    echo
    
    local iso_files=($(find "$mount_point" -maxdepth 1 -name "*.iso" -type f))
    
    if [[ ${#iso_files[@]} -eq 0 ]]; then
        print_warning "No ISO files found on USB"
    else
        for iso in "${iso_files[@]}"; do
            local iso_name=$(basename "$iso")
            local iso_size=$(du -h "$iso" | cut -f1)
            printf "  %-50s (%s)\n" "$iso_name" "$iso_size"
        done
    fi
    
    echo
    
    # Show available space
    local available_space=$(df -h "$mount_point" | tail -1 | awk '{print $4}')
    print_info "Available space: $available_space"
    
    # Unmount
    sudo umount "$mount_point"
    sudo rmdir "$mount_point"
}

remove_usb_isos() {
    if ! detect_usb_multiboot; then
        return 1
    fi
    
    local partition="${USB_DEVICE}1"
    local mount_point="/mnt/multiboot_remove_$$"
    
    # Mount the USB
    sudo mkdir -p "$mount_point"
    if ! sudo mount "$partition" "$mount_point"; then
        print_error "Failed to mount USB device"
        sudo rmdir "$mount_point"
        return 1
    fi
    
    local iso_files=($(find "$mount_point" -maxdepth 1 -name "*.iso" -type f))
    
    if [[ ${#iso_files[@]} -eq 0 ]]; then
        print_warning "No ISO files found on USB to remove"
        sudo umount "$mount_point"
        sudo rmdir "$mount_point"
        return 0
    fi
    
    print_info "ISO files on USB:"
    echo
    
    for i in "${!iso_files[@]}"; do
        local iso_name=$(basename "${iso_files[i]}")
        local iso_size=$(du -h "${iso_files[i]}" | cut -f1)
        printf "  %2d. %-50s (%s)\n" $((i+1)) "$iso_name" "$iso_size"
    done
    echo
    
    read -p "Select ISO files to remove (space-separated numbers): " selection
    
    local files_to_remove=()
    for num in $selection; do
        if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#iso_files[@]} )); then
            files_to_remove+=("${iso_files[$((num-1))]}")
        fi
    done
    
    if [[ ${#files_to_remove[@]} -eq 0 ]]; then
        print_warning "No valid files selected."
        sudo umount "$mount_point"
        sudo rmdir "$mount_point"
        return 0
    fi
    
    print_warning "About to remove ${#files_to_remove[@]} file(s):"
    for iso in "${files_to_remove[@]}"; do
        echo "  - $(basename "$iso")"
    done
    
    read -p "Are you sure? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_info "Operation cancelled."
        sudo umount "$mount_point"
        sudo rmdir "$mount_point"
        return 0
    fi
    
    for iso in "${files_to_remove[@]}"; do
        local iso_name=$(basename "$iso")
        if sudo rm "$iso"; then
            print_success "Removed $iso_name"
        else
            print_error "Failed to remove $iso_name"
        fi
    done
    
    # Unmount
    sudo umount "$mount_point"
    sudo rmdir "$mount_point"
    
    print_success "ISO removal completed!"
    print_warning "Remember to update GRUB menu entries accordingly."
}

show_menu() {
    while true; do
        echo
        print_info "What would you like to do?"
        echo "  1. List available ISO files in isos/ directory"
        echo "  2. Copy ISO files from isos/ to multiboot USB"
        echo "  3. List ISO files on multiboot USB"
        echo "  4. Remove ISO files from multiboot USB"
        echo "  5. Exit"
        echo
        
        read -p "Select option (1-5): " choice
        
        case "$choice" in
            1)
                list_available_isos
                ;;
            2)
                copy_isos_to_usb
                ;;
            3)
                list_usb_isos
                ;;
            4)
                remove_usb_isos
                ;;
            5)
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please select 1-5."
                ;;
        esac
    done
}

# Main execution
main() {
    print_header
    
    # Create isos directory if it doesn't exist
    if [[ ! -d "$ISOS_DIR" ]]; then
        print_info "Creating ISOs directory: $ISOS_DIR"
        mkdir -p "$ISOS_DIR"
    fi
    
    show_menu
}

# Run main function
main "$@" 