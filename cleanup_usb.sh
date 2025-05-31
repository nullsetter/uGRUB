#!/bin/bash

#==============================================#
#     USB Cleanup and Recovery Script         #
#     For interrupted multiboot USB prep      #
#==============================================#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${BLUE}    USB Cleanup and Recovery Script       ${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
}

cleanup_mount_points() {
    print_info "Cleaning up mount points..."
    
    # List of common mount points used by the script
    local mount_points=(
        "/mnt/multiboot_usb"
        "/mnt/multiboot_manage_*"
        "/mnt/multiboot_list_*"
        "/mnt/multiboot_remove_*"
        "/mnt/iso_examine"
    )
    
    for mount_pattern in "${mount_points[@]}"; do
        # Handle wildcard patterns
        for mount_point in $mount_pattern; do
            if mountpoint -q "$mount_point" 2>/dev/null; then
                print_info "Unmounting $mount_point..."
                sudo umount "$mount_point"
                print_success "Unmounted $mount_point"
            fi
            
            if [[ -d "$mount_point" ]]; then
                print_info "Removing directory $mount_point..."
                sudo rmdir "$mount_point" 2>/dev/null || sudo rm -rf "$mount_point"
                print_success "Removed $mount_point"
            fi
        done
    done
}

kill_stuck_processes() {
    print_info "Looking for stuck copy processes..."
    
    # Find any cp processes copying to mount points
    local stuck_processes=$(ps aux | grep -E "(cp|rsync|pv).*(/mnt/|multiboot)" | grep -v grep | awk '{print $2}')
    
    if [[ -n "$stuck_processes" ]]; then
        print_warning "Found potentially stuck processes:"
        ps aux | grep -E "(cp|rsync|pv).*(/mnt/|multiboot)" | grep -v grep
        echo
        
        read -p "Kill these processes? (y/n): " kill_choice
        if [[ "$kill_choice" == "y" || "$kill_choice" == "Y" ]]; then
            for pid in $stuck_processes; do
                print_info "Killing process $pid..."
                sudo kill -TERM "$pid" 2>/dev/null || sudo kill -KILL "$pid" 2>/dev/null
                print_success "Process $pid terminated"
            done
        fi
    else
        print_success "No stuck processes found"
    fi
}

check_usb_status() {
    print_info "Checking USB device status..."
    
    # List all USB devices
    local usb_devices=($(lsblk -dno NAME,SIZE,TYPE,TRAN | grep usb | awk '{print "/dev/"$1}'))
    
    if [[ ${#usb_devices[@]} -eq 0 ]]; then
        print_warning "No USB devices found"
        return
    fi
    
    for device in "${usb_devices[@]}"; do
        local size=$(lsblk -dno SIZE "$device")
        print_info "USB Device: $device ($size)"
        
        # Check if device has partitions
        local partitions=($(lsblk -lno NAME "$device" | tail -n +2))
        
        for partition in "${partitions[@]}"; do
            local part_path="/dev/$partition"
            local mount_point=$(lsblk -no MOUNTPOINT "$part_path" 2>/dev/null)
            
            if [[ -n "$mount_point" ]]; then
                print_info "  Partition $part_path mounted at: $mount_point"
                
                # Check if it looks like our multiboot USB
                if [[ -d "$mount_point/boot/grub" ]]; then
                    print_success "  Looks like multiboot USB!"
                fi
            else
                print_info "  Partition $part_path not mounted"
            fi
        done
        echo
    done
}

fix_permissions() {
    print_info "Fixing potential permission issues..."
    
    # Fix permissions on script directory
    if [[ -d "$(pwd)/isos" ]]; then
        chmod 755 "$(pwd)/isos"
        print_success "Fixed isos directory permissions"
    fi
    
    # Fix script permissions
    if [[ -f "$(pwd)/prepare_multiboot_usb.sh" ]]; then
        chmod +x "$(pwd)/prepare_multiboot_usb.sh"
        print_success "Fixed prepare_multiboot_usb.sh permissions"
    fi
    
    if [[ -f "$(pwd)/manage_isos.sh" ]]; then
        chmod +x "$(pwd)/manage_isos.sh"
        print_success "Fixed manage_isos.sh permissions"
    fi
}

show_menu() {
    while true; do
        echo
        print_info "What would you like to do?"
        echo "  1. Clean up mount points"
        echo "  2. Kill stuck processes"
        echo "  3. Check USB device status"
        echo "  4. Fix file permissions"
        echo "  5. Full cleanup (all of the above)"
        echo "  6. Exit"
        echo
        
        read -p "Select option (1-6): " choice
        
        case "$choice" in
            1)
                cleanup_mount_points
                ;;
            2)
                kill_stuck_processes
                ;;
            3)
                check_usb_status
                ;;
            4)
                fix_permissions
                ;;
            5)
                kill_stuck_processes
                cleanup_mount_points
                fix_permissions
                check_usb_status
                ;;
            6)
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please select 1-6."
                ;;
        esac
    done
}

# Main execution
main() {
    print_header
    
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. Some checks may not work as expected."
    fi
    
    show_menu
}

# Run main function
main "$@" 