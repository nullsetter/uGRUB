#!/bin/bash

#==============================================#
#     Multiboot USB Preparation Script        #
#     Based on uGRUB by Aditya Shakya         #
#     Enhanced with automatic ISO detection    #
#     + Robust umount/cleanup handling         #
#==============================================#

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
AUTO_MODE=false
DEBUG_MODE=false

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRUB_CONFIG_DIR="$SCRIPT_DIR/grub"
ISOS_DIR="$SCRIPT_DIR/isos"

# Helper to run commands with or without output redirection
run_cmd() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_info "🐛 DEBUG: Running command: $*"
        "$@"
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            print_success "🐛 DEBUG: Command succeeded (exit code: $exit_code)"
        else
            print_error "🐛 DEBUG: Command failed (exit code: $exit_code)"
        fi
        return $exit_code
    else
        "$@" > /dev/null 2>&1
    fi
}

# Helper for commands that should always show some output but can be quieted
run_cmd_with_output() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_info "🐛 DEBUG: Running command with output: $*"
        "$@"
        local exit_code=$?
        print_info "🐛 DEBUG: Command completed (exit code: $exit_code)"
        return $exit_code
    else
        "$@"
    fi
}

# Spinner function for long-running operations
show_spinner_for_pid() {
    local pid="$1"
    local message="$2"
    local spin='-\|/'
    local i=0
    
    printf "%s " "$message"
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r%s [%c]" "$message" "${spin:$i:1}"
        sleep 0.1
    done
    printf "\r%s [✓]%*s\n" "$message" $((50 - ${#message})) ""  # Clear spinner line with spaces
}

# Enhanced sync function with spinner
sync_with_spinner() {
    local message="${1:-💾 Syncing filesystem data...}"
    local sync_start_time=$(date +%s)
    local sync_exit_code=0
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_info "🐛 DEBUG: Starting sync with spinner (spinner will be shown): $message"
    fi

    # Always run sync in background and show spinner
    sync & 
    local sync_pid=$!
    show_spinner_for_pid "$sync_pid" "$message"
    wait "$sync_pid"
    sync_exit_code=$?
    
    local sync_end_time=$(date +%s)
    local sync_duration=$((sync_end_time - sync_start_time))
    
    if [[ $sync_exit_code -eq 0 ]]; then
        print_success "Sync completed in ${sync_duration}s"
        return 0
    else
        print_error "Sync operation FAILED with exit code $sync_exit_code"
        return $sync_exit_code
    fi
}

# Functions
print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}    Multiboot USB Preparation Script      ${NC}"
    echo -e "${BLUE}    Enhanced with Auto ISO Detection      ${NC}"
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

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Creates a multiboot USB drive with GRUB2 bootloader"
    echo
    echo "Options:"
    echo "  --auto, -a     Auto mode - minimal user interaction"
    echo "  --debug, -d    Debug mode - show all command output"
    echo "  --help, -h     Show this help message"
    echo
    echo "Features:"
    echo "  • Automatic USB detection and selection"
    echo "  • UEFI/BIOS compatibility (GPT/MBR auto-detection)"
    echo "  • exFAT filesystem (supports files >4GB)"
    echo "  • Enhanced ISO analysis and menu generation"
    echo "  • Multiple themes and customization options"
    echo "  • Comprehensive error handling and diagnostics"
    echo "  • Visual progress indicators with spinners for long operations"
    echo
    echo "Examples:"
    echo "  $0              # Interactive mode"
    echo "  $0 --auto       # Minimal interaction mode"
    echo "  $0 --debug      # Show all command output for troubleshooting"
    echo "  $0 --auto --debug  # Auto mode with debug output"
    echo
    echo "Prerequisites:"
    echo "  • Place ISO files in the 'isos/' directory"
    echo "  • Run with sudo privileges when prompted"
    echo "  • USB drive with sufficient space (8GB+ recommended)"
    echo "  • Optional: Install 'pv' package for enhanced progress display"
    echo "    - Ubuntu/Debian: sudo apt install pv"
    echo "    - Arch Linux: sudo pacman -S pv"
    echo "    - Fedora/CentOS: sudo dnf install pv"
    echo
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root initially."
        print_info "The script will ask for sudo privileges when needed."
        exit 1
    fi
}

# Initialize ISO detection capability
init_iso_detection() {
    # Source ISO detection functions if available
    if [[ -f "$SCRIPT_DIR/iso_detection_functions.sh" ]]; then
        source "$SCRIPT_DIR/iso_detection_functions.sh"
        ISO_DETECTION_AVAILABLE=true
        print_info "Enhanced ISO detection enabled"
    else
        ISO_DETECTION_AVAILABLE=false
        print_warning "ISO detection functions not found - using basic detection"
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
        print_info "For Ubuntu/Debian: sudo apt install fdisk exfatprogs grub2-common grub-pc-bin grub-efi-amd64-bin util-linux pv"
        print_info "For Arch Linux: sudo pacman -S util-linux exfatprogs grub pv"
        print_info "For Fedora/CentOS: sudo dnf install util-linux exfatprogs grub2-tools grub2-efi-x64 pv"
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
    
    # Auto-select if only one USB device (in auto mode or user preference)
    if [[ ${#usb_devices[@]} -eq 1 ]]; then
        local selected_info="${device_info[0]}"
        USB_DEVICE="/dev/$(echo "$selected_info" | cut -d'|' -f1)"
        USB_SIZE=$(echo "$selected_info" | cut -d'|' -f2)
        local usb_model=$(echo "$selected_info" | cut -d'|' -f5)
        
        if [[ "$AUTO_MODE" == "true" ]]; then
            print_success "Auto-selected: $USB_DEVICE ($USB_SIZE) - $usb_model"
        else
            print_info "Only one USB device found."
            print_success "Selected: $USB_DEVICE ($USB_SIZE) - $usb_model"
        fi
        return
    fi
    
    # Multiple devices - show selection help
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
    if ! run_cmd sudo fdisk -l "$USB_DEVICE"; then
        print_error "Cannot access USB device $USB_DEVICE"
        print_info "Try unplugging and reconnecting the USB drive"
        exit 1
    fi
    
    # Check for any processes using the device
    local using_processes=$(run_cmd sudo fuser "$USB_DEVICE"* || true)
    if [[ -n "$using_processes" ]]; then
        print_warning "Found processes using the USB device:"
        run_cmd_with_output sudo fuser -v "$USB_DEVICE"* || true
        echo
        read -p "Kill these processes and continue? (y/n): " kill_procs
        if [[ "$kill_procs" == "y" || "$kill_procs" == "Y" ]]; then
            run_cmd sudo fuser -k "$USB_DEVICE"* || true
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
    print_warning "Device: $USB_DEVICE ($USB_SIZE)"
    
    # Show what's currently on the USB if possible
    if sudo fdisk -l "$USB_DEVICE" 2>/dev/null | grep -q "^${USB_DEVICE}"; then
        print_info "Current partitions on device:"
        sudo fdisk -l "$USB_DEVICE" 2>/dev/null | grep "^${USB_DEVICE}" | while read line; do
            echo "  $line"
        done
    fi
    
    echo
    print_warning "This will:"
    echo "  • Delete all existing data and partitions"
    echo "  • Create a new partition table (GPT for UEFI, MBR for BIOS)"
    echo "  • Format with exFAT filesystem"
    echo "  • Install GRUB bootloader"
    if [[ "$ISO_DETECTION_AVAILABLE" == "true" ]]; then
        echo "  • Auto-generate menu entries for detected ISOs"
    fi
    echo
    
    if [[ "$AUTO_MODE" == "true" ]]; then
        print_info "Auto mode: Proceeding with USB format in 3 seconds..."
        print_info "Press Ctrl+C to cancel"
        sleep 3
        print_success "Confirmed - proceeding with USB format"
        return
    fi
    
    local confirm
    while true; do
        read -p "Are you sure you want to format $USB_DEVICE? (yes/no): " confirm
        case "$confirm" in
            yes|YES|y|Y)
                print_success "Confirmed - proceeding with USB format"
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

# Specialized function to detect and cleanup USB-blocking processes
detect_and_cleanup_usb_processes() {
    local device="$1"
    print_info "Detecting processes that might block USB operations..."
    
    # Step 1: Check for processes directly using the device
    print_info "Checking processes using device files..."
    local device_processes=$(sudo fuser -v "$device"* 2>/dev/null | grep -v "USER\|^$" | awk '{print $2}' || true)
    
    # Step 2: Check for mount-related processes
    print_info "Checking for mount/umount processes..."
    local mount_processes=$(ps aux | grep -E "(mount|umount).*${device##*/}" | grep -v grep | awk '{print $2}' || true)
    
    # Step 3: Check for kernel threads that might be blocking
    print_info "Checking for blocking kernel threads..."
    local kernel_threads=$(ps aux | grep -E "\[.*${device##*/}.*\]" | awk '{print $2}' || true)
    
    # Step 4: Check for systemd automount services
    print_info "Checking systemd automount services..."
    local systemd_services=$(systemctl list-units --type=mount | grep "${device##*/}" | awk '{print $1}' || true)
    
    # Combine all found processes
    local all_processes="$device_processes $mount_processes $kernel_threads"
    local unique_processes=($(echo "$all_processes" | tr ' ' '\n' | sort -u | grep -E '^[0-9]+$' || true))
    
    if [[ ${#unique_processes[@]} -gt 0 ]]; then
        print_warning "Found ${#unique_processes[@]} potentially blocking process(es)"
        
        # Show process details
        for pid in "${unique_processes[@]}"; do
            if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]]; then
                local proc_info=$(ps -p "$pid" -o pid,ppid,cmd --no-headers 2>/dev/null || echo "Process $pid not found")
                print_info "  PID $pid: $proc_info"
            fi
        done
        
        # Kill processes with escalating force
        print_info "Attempting graceful termination (SIGTERM)..."
        for pid in "${unique_processes[@]}"; do
            if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]]; then
                sudo kill -TERM "$pid" 2>/dev/null || true
            fi
        done
        sleep 3
        
        # Check if any processes still exist
        local remaining_processes=()
        for pid in "${unique_processes[@]}"; do
            if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
                remaining_processes+=("$pid")
            fi
        done
        
        if [[ ${#remaining_processes[@]} -gt 0 ]]; then
            print_warning "Some processes still running, using SIGKILL..."
            for pid in "${remaining_processes[@]}"; do
                sudo kill -9 "$pid" 2>/dev/null || true
            done
            sleep 2
        fi
        
        print_success "Process cleanup completed"
    else
        print_success "No blocking processes found"
    fi
    
    # Handle systemd services
    if [[ -n "$systemd_services" ]]; then
        print_info "Stopping systemd mount services..."
        for service in $systemd_services; do
            print_info "Stopping $service..."
            sudo systemctl stop "$service" 2>/dev/null || true
        done
    fi
    
    return 0
}

# Enhanced cleanup function to handle stuck processes
force_cleanup_usb_device() {
    local device="$1"
    print_info "Performing enhanced USB device cleanup..."
    
    # Step 0: Specialized USB process detection and cleanup
    detect_and_cleanup_usb_processes "$device"
    
    # Step 1: Check for and kill stuck umount processes
    print_info "Checking for stuck umount processes..."
    local stuck_umount_pids=$(ps -elf | grep -E "umount.*${device##*/}" | grep -v grep | awk '{print $4}')
    if [[ -n "$stuck_umount_pids" ]]; then
        print_warning "Found stuck umount processes: $stuck_umount_pids"
        print_info "Force killing stuck umount processes..."
        
        # Try SIGTERM first
        for pid in $stuck_umount_pids; do
            sudo kill -TERM "$pid" 2>/dev/null || true
        done
        sleep 2
        
        # Check if still running, then use SIGKILL
        local still_running=$(ps -elf | grep -E "umount.*${device##*/}" | grep -v grep | awk '{print $4}')
        if [[ -n "$still_running" ]]; then
            print_warning "Processes still running, using SIGKILL..."
            for pid in $still_running; do
                sudo kill -9 "$pid" 2>/dev/null || true
            done
            sleep 1
        fi
        
        # Final check
        local final_check=$(ps -elf | grep -E "umount.*${device##*/}" | grep -v grep | awk '{print $4}')
        if [[ -n "$final_check" ]]; then
            print_error "Some umount processes are still stuck (PIDs: $final_check)"
            print_info "These processes are in uninterruptible state and may require a reboot"
        else
            print_success "All stuck umount processes have been cleaned up"
        fi
    else
        print_success "No stuck umount processes found"
    fi
    
    # Step 2: Kill any processes using the device with escalating force
    print_info "Checking for processes using the device..."
    local using_processes=$(sudo fuser "$device"* 2>/dev/null | tr -d ':' || true)
    if [[ -n "$using_processes" ]]; then
        print_warning "Found processes using the device: $using_processes"
        print_info "Attempting graceful termination..."
        sudo fuser -TERM "$device"* 2>/dev/null || true
        sleep 3
        
        # Check if still in use
        local still_using=$(sudo fuser "$device"* 2>/dev/null | tr -d ':' || true)
        if [[ -n "$still_using" ]]; then
            print_warning "Some processes still using device, force killing..."
            sudo fuser -KILL "$device"* 2>/dev/null || true
            sleep 2
        fi
        
        # Final check
        local final_using=$(sudo fuser "$device"* 2>/dev/null | tr -d ':' || true)
        if [[ -n "$final_using" ]]; then
            print_warning "Some processes are still using the device"
        else
            print_success "All processes using the device have been terminated"
        fi
    else
        print_success "No processes found using the device"
    fi
    
    # Step 3: Comprehensive unmounting with multiple strategies and timeouts
    print_info "Performing comprehensive unmount with advanced strategies..."
    local unmount_attempts=0
    local max_attempts=3
    
    while [[ $unmount_attempts -lt $max_attempts ]]; do
        ((unmount_attempts++))
        print_info "=== Unmount Strategy $unmount_attempts/$max_attempts ==="
        
        # Get all partitions on the device with better detection
        print_info "Detecting partitions on $device..."
        local partitions=()
        
        # Method 1: Use lsblk to find partitions
        while IFS= read -r partition_name; do
            if [[ -n "$partition_name" && "$partition_name" != "${device##*/}" ]]; then
                partitions+=("/dev/$partition_name")
            fi
        done < <(lsblk -rno NAME "$device" 2>/dev/null | grep -v "^${device##*/}$" || true)
        
        # Method 2: Also check direct partition naming
        for i in {1..4}; do
            if [[ -e "${device}${i}" ]]; then
                partitions+=("${device}${i}")
            fi
        done
        
        # Remove duplicates
        local unique_partitions=($(printf '%s\n' "${partitions[@]}" | sort -u))
        
        if [[ ${#unique_partitions[@]} -eq 0 ]]; then
            print_success "No partitions found to unmount"
            break
        fi
        
        print_info "Found ${#unique_partitions[@]} partition(s): ${unique_partitions[*]}"
        
        # Step 3a: Check which partitions are actually mounted
        local mounted_partitions=()
        for partition in "${unique_partitions[@]}"; do
            if mount | grep -q "^$partition "; then
                mounted_partitions+=("$partition")
                local mount_point=$(mount | grep "^$partition " | awk '{print $3}')
                print_info "  ✓ $partition is mounted at: $mount_point"
            else
                print_info "  - $partition is not mounted"
            fi
        done
        
        if [[ ${#mounted_partitions[@]} -eq 0 ]]; then
            print_success "No mounted partitions found - unmount complete"
            break
        fi
        
        print_info "Unmounting ${#mounted_partitions[@]} mounted partition(s)..."
        
        # Step 3b: Unmount each mounted partition with escalating strategies
        local unmount_failed=false
        for partition in "${mounted_partitions[@]}"; do
            local mount_point=$(mount | grep "^$partition " | awk '{print $3}')
            print_info "Processing $partition (mounted at $mount_point)..."
            
            # Strategy based on attempt number
            case $unmount_attempts in
                1)
                    print_info "Strategy 1: Normal umount with timeout"
                    if timeout 15 sudo umount "$partition" 2>/dev/null; then
                        print_success "Normal umount successful for $partition"
                    else
                        print_warning "Normal umount failed for $partition"
                        unmount_failed=true
                    fi
                    ;;
                2)
                    print_info "Strategy 2: Kill blocking processes + lazy umount"
                    # Kill processes using this specific partition
                    local part_processes=$(sudo fuser "$partition" 2>/dev/null | tr -d ':' || true)
                    if [[ -n "$part_processes" ]]; then
                        print_warning "Killing processes using $partition: $part_processes"
                        for pid in $part_processes; do
                            sudo kill -9 "$pid" 2>/dev/null || true
                        done
                        sleep 2
                    fi
                    
                    if timeout 10 sudo umount -l "$partition" 2>/dev/null; then
                        print_success "Lazy umount successful for $partition"
                    else
                        print_warning "Lazy umount failed for $partition"
                        unmount_failed=true
                    fi
                    ;;
                3)
                    print_info "Strategy 3: Force umount with detach"
                    # Try force umount
                    if timeout 10 sudo umount -f "$partition" 2>/dev/null; then
                        print_success "Force umount successful for $partition"
                    elif timeout 5 sudo umount --detach-loop "$partition" 2>/dev/null; then
                        print_success "Detach umount successful for $partition"
                    else
                        print_error "All umount methods failed for $partition"
                        unmount_failed=true
                    fi
                    ;;
            esac
        done
        
        # Step 3c: Check if unmounting was successful
        if [[ "$unmount_failed" == "false" ]]; then
            # Double-check that nothing is mounted
            local still_mounted=()
            for partition in "${mounted_partitions[@]}"; do
                if mount | grep -q "^$partition "; then
                    still_mounted+=("$partition")
                fi
            done
            
            if [[ ${#still_mounted[@]} -eq 0 ]]; then
                print_success "All partitions unmounted successfully"
                break
            else
                print_warning "Some partitions still mounted: ${still_mounted[*]}"
                unmount_failed=true
            fi
        fi
        
        # Step 3d: Handle failed attempts
        if [[ $unmount_attempts -lt $max_attempts ]]; then
            print_info "Unmount attempt $unmount_attempts failed, waiting before retry..."
            print_info "Performing additional cleanup before next attempt..."
            
            # Kill any remaining processes using the device
            sudo fuser -k "$device"* 2>/dev/null || true
            
            # Clear filesystem caches
            echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || true
            
            sleep 5
        else
            print_error "Failed to unmount all partitions after $max_attempts attempts"
            print_info "Remaining mounted partitions may require manual intervention"
            
            # Show current mount status for debugging
            print_info "Current mount status:"
            mount | grep "$device" || echo "No mounts found for $device"
        fi
    done
    
    # Step 4: Sync with timeout and better error handling
    print_info "Syncing filesystem and waiting for operations to complete..."
    
    # Multiple sync strategies with escalating approaches
    # Change: Make sync blocking here to ensure data is written before unmount attempts.
    local sync_successful=false

    # Use the new sync function with spinner
    if sync_with_spinner "💾 Syncing filesystem data to complete pending writes..."; then
        sync_successful=true
    else
        sync_successful=false
        print_warning "This may indicate issues with the storage device or filesystem state."
        # Even if sync fails, we might still be able to proceed, but with caution.
        # The script will attempt to unmount and repartition anyway.
    fi
    
    # Optional: Drop caches after sync, can sometimes help release resources.
    # However, the primary goal is that `sync` itself completes.
    if [[ "$sync_successful" == "true" ]]; then
        print_info "Optionally attempting to drop caches..."
        if echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1; then
            print_success "Caches dropped."
        else
            print_warning "Could not drop caches (this is often non-critical)."
        fi
    fi

    # Brief additional wait for USB device stability
    sleep 1
    
    # Step 5: Final verification
    print_info "Verifying device is ready for partitioning..."
    if sudo fdisk -l "$device" >/dev/null 2>&1; then
        print_success "Device is accessible and ready"
    else
        print_error "Device is not accessible - there may still be issues"
        print_info "You may need to unplug and reconnect the USB device"
        return 1
    fi
    
    print_success "Enhanced USB device cleanup completed"
    return 0
}

# Specialized function to detect and handle mount-related stuck processes
detect_and_handle_mount_deadlocks() {
    local mount_point="$1"
    print_info "Detecting and handling mount-related deadlocks for $mount_point..."
    
    # Step 1: Check for stuck umount processes
    print_info "Checking for stuck umount processes..."
    local stuck_umount_pids=$(ps -elf | grep -E "umount.*$(basename "$mount_point")" | grep -v grep | awk '{print $4}')
    if [[ -n "$stuck_umount_pids" ]]; then
        print_warning "Found stuck umount processes: $stuck_umount_pids"
        for pid in $stuck_umount_pids; do
            local proc_state=$(ps -o pid,stat,wchan:30,comm --no-headers -p "$pid" 2>/dev/null || echo "Process not found")
            print_info "  PID $pid: $proc_state"
            
            # Check if process is in uninterruptible sleep (D state)
            local state=$(ps -o stat --no-headers -p "$pid" 2>/dev/null | cut -c1)
            if [[ "$state" == "D" ]]; then
                print_warning "  PID $pid is in uninterruptible sleep (D state) - kernel deadlock detected"
            fi
        done
        
        # Force kill all stuck umount processes
        print_info "Force killing stuck umount processes..."
        for pid in $stuck_umount_pids; do
            sudo kill -9 "$pid" 2>/dev/null || true
        done
        sleep 2
    else
        print_success "No stuck umount processes found"
    fi
    
    # Step 2: Check for kernel mount threads
    print_info "Checking for kernel mount threads..."
    local kernel_mount_threads=$(ps aux | grep -E "\[.*mount.*\]" | grep -v grep | awk '{print $2}')
    if [[ -n "$kernel_mount_threads" ]]; then
        print_warning "Found kernel mount threads: $kernel_mount_threads"
        for pid in $kernel_mount_threads; do
            local thread_info=$(ps -o pid,comm,wchan:30 --no-headers -p "$pid" 2>/dev/null || echo "Thread not found")
            print_info "  Kernel thread: $thread_info"
        done
        print_info "Kernel threads cannot be killed but may resolve automatically"
    else
        print_success "No problematic kernel mount threads found"
    fi
    
    # Step 3: Check for I/O wait processes
    print_info "Checking for processes in I/O wait state..."
    local io_wait_processes=$(ps axo pid,stat,wchan:30,comm | grep -E "^[[:space:]]*[0-9]+[[:space:]]+D" | grep -v grep || true)
    if [[ -n "$io_wait_processes" ]]; then
        print_warning "Found processes in I/O wait (D state):"
        echo "$io_wait_processes"
        print_info "These processes may be causing mount deadlocks"
    else
        print_success "No processes in I/O wait state found"
    fi
    
    # Step 4: Check filesystem state
    print_info "Checking filesystem state..."
    local device_from_mount=$(mount | grep " $mount_point " | awk '{print $1}' | head -n1)
    if [[ -n "$device_from_mount" ]]; then
        print_info "Checking device $device_from_mount..."
        
        # Check if device is readable
        if sudo dd if="$device_from_mount" of=/dev/null bs=512 count=1 2>/dev/null; then
            print_success "Device is readable"
        else
            print_warning "Device read failed - possible hardware issue"
        fi
        
        # Check device buffer status
        print_info "Device buffer status:"
        cat /proc/meminfo | grep -E "(Dirty|Writeback)" || true
    fi
    
    # Step 5: Force filesystem sync for this specific mount
    print_info "Forcing filesystem sync for mount point..."
    
    # Try to sync just this mount point
    if command -v syncfs >/dev/null 2>&1; then
        print_info "Using syncfs for targeted sync..."
        timeout 5 syncfs "$mount_point" 2>/dev/null || print_warning "syncfs failed or timed out"
    fi
    
    # General sync with timeout
    print_info "Performing general sync with timeout..."
    timeout 3 sync 2>/dev/null || print_warning "General sync timed out"
    
    return 0
}

# Enhanced safe umount function with comprehensive timeout and detection
safe_umount() {
    local mount_point="$1"
    local max_attempts=4
    local attempt=1
    
    # Step 1: Check if actually mounted
    if ! mount | grep -q " $mount_point "; then
        print_success "Mount point $mount_point is not mounted"
        return 0
    fi
    
    print_info "Attempting to unmount $mount_point with comprehensive strategy..."
    
    # Step 2: Initial deadlock detection and handling
    detect_and_handle_mount_deadlocks "$mount_point"
    
    while [[ $attempt -le $max_attempts ]]; do
        print_info "=== UNMOUNT STRATEGY $attempt/$max_attempts for $mount_point ==="
        
        # Enhanced diagnostics before each attempt
        print_info "==== COMPREHENSIVE UNMOUNT DIAGNOSTICS (attempt $attempt) ===="
        
        # Check mount status
        print_info "Current mount status:"
        mount | grep "$mount_point" || echo "  No active mounts found for $mount_point"
        
        # Check processes using mount point with multiple methods
        print_info "Method 1 - lsof check for open files:"
        if command -v lsof >/dev/null 2>&1; then
            local open_files=$(lsof +D "$mount_point" 2>/dev/null || true)
            if [[ -n "$open_files" ]]; then
                echo "$open_files"
            else
                echo "  No open files detected by lsof"
            fi
        else
            echo "  lsof not available"
        fi
        
        print_info "Method 2 - fuser check for processes:"
        local fuser_output=$(sudo fuser -vm "$mount_point" 2>/dev/null || true)
        if [[ -n "$fuser_output" ]]; then
            echo "$fuser_output"
        else
            echo "  No processes detected by fuser"
        fi
        
        print_info "Method 3 - Process tree analysis:"
        local mount_processes=$(ps aux | grep -E "(mount|umount)" | grep "$mount_point" | grep -v grep || true)
        if [[ -n "$mount_processes" ]]; then
            echo "$mount_processes"
        else
            echo "  No mount/umount processes found"
        fi
        
        print_info "Method 4 - Kernel thread analysis:"
        local kernel_threads=$(ps aux | grep -E "\[.*$(basename "$mount_point").*\]" | grep -v grep || true)
        if [[ -n "$kernel_threads" ]]; then
            echo "Kernel threads related to mount point:"
            echo "$kernel_threads"
        else
            echo "  No related kernel threads found"
        fi
        
        print_info "Method 5 - Device usage analysis:"
        local device_from_mount=$(mount | grep " $mount_point " | awk '{print $1}' | head -n1)
        if [[ -n "$device_from_mount" ]]; then
            print_info "Device: $device_from_mount"
            local device_processes=$(sudo fuser -v "$device_from_mount" 2>/dev/null || true)
            if [[ -n "$device_processes" ]]; then
                echo "Processes using device $device_from_mount:"
                echo "$device_processes"
            else
                echo "  No processes using device $device_from_mount"
            fi
        fi
        
        print_info "============================="
        
        # Aggressive process cleanup before umount attempt
        print_info "Performing aggressive process cleanup..."
        
        # Kill processes using the mount point
        local blocking_pids=$(sudo fuser -m "$mount_point" 2>/dev/null | tr -d ':' | tr ' ' '\n' | grep -E '^[0-9]+$' || true)
        if [[ -n "$blocking_pids" ]]; then
            print_warning "Killing blocking processes: $blocking_pids"
            for pid in $blocking_pids; do
                if [[ -n "$pid" ]]; then
                    print_info "Killing PID $pid"
                    sudo kill -TERM "$pid" 2>/dev/null || true
                fi
            done
            sleep 2
            
            # Check if any are still running and force kill
            for pid in $blocking_pids; do
                if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                    print_warning "Force killing stubborn PID $pid"
                    sudo kill -9 "$pid" 2>/dev/null || true
                fi
            done
            sleep 1
        fi
        
        # Kill any mount/umount processes for this mount point
        local mount_pids=$(ps aux | grep -E "(mount|umount)" | grep "$mount_point" | grep -v grep | awk '{print $2}' || true)
        if [[ -n "$mount_pids" ]]; then
            print_warning "Killing mount/umount processes: $mount_pids"
            for pid in $mount_pids; do
                if [[ -n "$pid" ]]; then
                    sudo kill -9 "$pid" 2>/dev/null || true
                fi
            done
            sleep 2
        fi
        
        # Ensure script is not running in the mount directory
        if [[ "$PWD" == "$mount_point"* ]]; then
            print_warning "Script is running inside $mount_point, changing directory to /tmp"
            cd /tmp
        fi
        
        # Flush filesystem buffers
        print_info "Flushing filesystem buffers..."
        sync 2>/dev/null || true
        echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
        
        # Strategy-specific umount attempts with shorter timeouts
        local umount_success=false
        case $attempt in
            1)
                print_info "Strategy 1: Quick normal umount (5s timeout)"
                if timeout 5 sudo umount "$mount_point" 2>/dev/null; then
                    umount_success=true
                    print_success "Quick normal umount successful"
                else
                    print_warning "Quick normal umount failed/timed out"
                fi
                ;;
            2)
                print_info "Strategy 2: Lazy umount with force prep (3s timeout)"
                # Additional process cleanup
                sudo pkill -f "$mount_point" 2>/dev/null || true
                sleep 1
                if timeout 3 sudo umount -l "$mount_point" 2>/dev/null; then
                    umount_success=true
                    print_success "Lazy umount successful"
                else
                    print_warning "Lazy umount failed/timed out"
                fi
                ;;
            3)
                print_info "Strategy 3: Force umount with comprehensive cleanup (2s timeout)"
                # Aggressive cleanup
                sudo fuser -k "$mount_point" 2>/dev/null || true
                sleep 1
                if timeout 2 sudo umount -f "$mount_point" 2>/dev/null; then
                    umount_success=true
                    print_success "Force umount successful"
                else
                    print_warning "Force umount failed/timed out"
                    # Try detach as immediate fallback
                    print_info "Attempting detach-loop fallback..."
                    if timeout 2 sudo umount --detach-loop "$mount_point" 2>/dev/null; then
                        umount_success=true
                        print_success "Detach umount successful"
                    fi
                fi
                ;;
            4)
                print_info "Strategy 4: Nuclear option - device-level detachment"
                
                # Find the device
                local device_name=""
                if [[ -n "$device_from_mount" ]]; then
                    device_name="$device_from_mount"
                else
                    device_name=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null || true)
                fi
                
                if [[ -n "$device_name" ]]; then
                    print_warning "Attempting emergency device detachment for $device_name"
                    
                    # Method 1: Try emergency remount readonly first
                    print_info "Attempting emergency readonly remount..."
                    sudo mount -o remount,ro "$mount_point" 2>/dev/null || true
                    sleep 1
                    
                    # Method 2: Try one more force umount
                    if timeout 1 sudo umount -f "$mount_point" 2>/dev/null; then
                        umount_success=true
                        print_success "Emergency umount after readonly remount successful"
                    else
                        # Method 3: Device-level operations
                        print_warning "Attempting device-level detachment (THIS MAY DISCONNECT THE USB!)"
                        
                        # Get base device name (remove partition number)
                        local base_device=$(echo "$device_name" | sed 's/[0-9]*$//')
                        local device_basename=$(basename "$base_device")
                        
                        print_info "Base device: $base_device ($device_basename)"
                        
                        # Try to flush device buffers
                        if [[ -b "$base_device" ]]; then
                            print_info "Flushing device buffers..."
                            sudo blockdev --flushbufs "$base_device" 2>/dev/null || true
                        fi
                        
                        # Final umount attempt after device flush
                        if timeout 1 sudo umount -l "$mount_point" 2>/dev/null; then
                            umount_success=true
                            print_success "Final umount after device flush successful"
                        else
                            print_error "All umount strategies failed - this is likely a hardware/driver issue"
                            print_info "The USB creation process has completed, but manual umount may be required"
                            print_info "You can safely unplug the USB device or reboot the system"
                            # Don't fail completely - the USB is probably fine
                            umount_success=true  # Treat as success to continue
                        fi
                    fi
                else
                    print_error "Could not determine device name for emergency detachment"
                fi
                ;;
        esac
        
        # Check if unmounting was successful
        if [[ "$umount_success" == "true" ]]; then
            # Double-check that it's actually unmounted
            sleep 1
            if ! mount | grep -q " $mount_point "; then
                print_success "Unmount verification successful - $mount_point is no longer mounted"
                return 0
            else
                print_warning "Umount command succeeded but mount point still shows as mounted"
                # Continue to next strategy
            fi
        fi
        
        # Prepare for next attempt
        ((attempt++))
        if [[ $attempt -le $max_attempts ]]; then
            print_info "Waiting 2 seconds before next umount strategy..."
            sleep 2
        fi
    done
    
    # Final status check
    if ! mount | grep -q " $mount_point "; then
        print_success "Mount point $mount_point is now unmounted (delayed success)"
        return 0
    fi
    
    # If we get here, all strategies failed
    print_error "All $max_attempts umount strategies failed for $mount_point"
    print_warning "This may indicate a hardware issue or kernel bug"
    
    # Show final diagnostics
    print_info "==== FINAL DIAGNOSTICS ===="
    print_info "Mount status:"
    mount | grep "$mount_point" || echo "No mount found"
    print_info "Processes still using mount point:"
    sudo fuser -vm "$mount_point" 2>/dev/null || echo "No processes found"
    print_info "==========================="
    
    print_warning "RECOMMENDATION: The USB device should still be functional"
    print_warning "You can safely:"
    print_warning "1. Unplug the USB device (it will auto-unmount)"
    print_warning "2. Reboot the system"
    print_warning "3. Use 'sudo umount -f $mount_point' manually later"
    
    # Don't return error - let the script complete
    return 0
}

partition_usb() {
    print_info "Partitioning USB device $USB_DEVICE..."
    
    # Enhanced device cleanup
    if ! force_cleanup_usb_device "$USB_DEVICE"; then
        print_error "Device cleanup failed - cannot proceed with partitioning"
        print_info "Try unplugging and reconnecting the USB drive, then run the script again"
        exit 1
    fi
    
    # Additional wait after cleanup
    print_info "Waiting for device to stabilize after cleanup..."
    sleep 2
    
    # Verify device is accessible before partitioning
    if ! run_cmd sudo fdisk -l "$USB_DEVICE"; then
        print_error "USB device not accessible after cleanup"
        print_info "Try unplugging and reconnecting the USB drive"
        exit 1
    fi
    
    # Check current partition table
    print_info "Checking current partition table..."
    if [[ "$DEBUG_MODE" == "true" ]]; then
        run_cmd_with_output sudo fdisk -l "$USB_DEVICE"
    else
        run_cmd sudo fdisk -l "$USB_DEVICE"
    fi
    
    # Detect if UEFI system and create appropriate partition table
    if [[ -d "/sys/firmware/efi" ]]; then
        print_info "Creating GPT partition table for UEFI compatibility..."
        local sfdisk_result=0
        if [[ "$DEBUG_MODE" == "true" ]]; then
            print_info "🐛 DEBUG: Running sfdisk with GPT table..."
            cat << 'EOF' | sudo sfdisk --force "$USB_DEVICE" || sfdisk_result=$?
label: gpt
type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, bootable
EOF
        else
            cat << 'EOF' | run_cmd sudo sfdisk --force "$USB_DEVICE" || sfdisk_result=$?
label: gpt
type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, bootable
EOF
        fi
        
        if [[ $sfdisk_result -ne 0 ]]; then
            print_warning "sfdisk failed, trying with fdisk..."
            if [[ "$DEBUG_MODE" == "true" ]]; then
                print_info "🐛 DEBUG: Running fdisk with GPT commands..."
                (timeout 30 sudo fdisk "$USB_DEVICE" << 'EOF'
g
n
1


t
1
w
EOF
) || {
                    print_error "Partitioning failed - device may be problematic"
                    print_info "Try using a different USB drive or unplugging/reconnecting"
                    exit 1
                }
            else
                if ! (timeout 30 run_cmd sudo fdisk "$USB_DEVICE" << 'EOF'
g
n
1


t
1
w
EOF
); then
                    print_error "Partitioning failed - device may be problematic"
                    print_info "Try using a different USB drive or unplugging/reconnecting"
                    exit 1
                fi
            fi
        fi
    else
        print_info "Creating MBR partition table for BIOS compatibility..."
        local sfdisk_result=0
        if [[ "$DEBUG_MODE" == "true" ]]; then
            print_info "🐛 DEBUG: Running sfdisk with MBR table..."
            cat << 'EOF' | sudo sfdisk --force "$USB_DEVICE" || sfdisk_result=$?
label: dos
type=c, bootable
EOF
        else
            cat << 'EOF' | run_cmd sudo sfdisk --force "$USB_DEVICE" || sfdisk_result=$?
label: dos
type=c, bootable
EOF
        fi
        
        if [[ $sfdisk_result -ne 0 ]]; then
            print_warning "sfdisk failed, trying with fdisk..."
            if [[ "$DEBUG_MODE" == "true" ]]; then
                print_info "🐛 DEBUG: Running fdisk with MBR commands..."
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
                    print_error "Partitioning failed - device may be problematic"
                    print_info "Try using a different USB drive or unplugging/reconnecting"
                    exit 1
                }
            else
                if ! (timeout 30 run_cmd sudo fdisk "$USB_DEVICE" << 'EOF'
o
n
p
1


a
t
c
w
EOF
); then
                    print_error "Partitioning failed - device may be problematic"
                    print_info "Try using a different USB drive or unplugging/reconnecting"
                    exit 1
                fi
            fi
        fi
    fi
    
    # Force kernel to re-read partition table
    print_info "Forcing kernel to re-read partition table..."
    run_cmd sudo partprobe "$USB_DEVICE" || true
    run_cmd sudo udevadm settle || true
    
    # Robust wait for partition to appear
    print_info "Waiting for partition to be recognized (up to 60s)..."
    local partition="${USB_DEVICE}1"
    local wait_count=0
    while [[ ! -e "$partition" && $wait_count -lt 60 ]]; do
        sleep 1
        ((wait_count++))
        if (( wait_count % 5 == 0 )); then
            print_info "...still waiting for $partition ($wait_count/60)"
        fi
    done
    
    if [[ ! -e "$partition" ]]; then
        print_error "Partition $partition was not created after 60 seconds!"
        print_info "Diagnostics:"
        run_cmd_with_output lsblk "$USB_DEVICE" || true
        print_info "Recent kernel messages:"
        run_cmd_with_output dmesg | tail -30 || true
        print_info "Try unplugging and reconnecting the USB drive, then run the script again."
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
    
    # Format as exFAT
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_info "🐛 DEBUG: Formatting partition $partition as exFAT..."
        sudo mkfs.exfat -n "Multiboot" "$partition"
    else
        run_cmd sudo mkfs.exfat -n "Multiboot" "$partition"
    fi
    
    print_success "USB partition formatted as exFAT"
}

install_grub() {
    print_info "Installing GRUB bootloader..."
    
    local mount_point="/mnt/multiboot_usb"
    local partition="${USB_DEVICE}1"
    
    # Create mount point and mount
    run_cmd sudo mkdir -p "$mount_point"
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_info "🐛 DEBUG: Mounting $partition to $mount_point..."
        sudo mount "$partition" "$mount_point"
    else
        run_cmd sudo mount "$partition" "$mount_point"
    fi
    
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
        if [[ "$DEBUG_MODE" == "true" ]]; then
            print_info "🐛 DEBUG: Installing GRUB for UEFI (target: $grub_target)..."
            sudo grub-install --force --removable --target="$grub_target" \
                             --boot-directory="$mount_point/boot" \
                             --efi-directory="$mount_point" "$USB_DEVICE"
        else
            run_cmd sudo grub-install --force --removable --target="$grub_target" \
                                     --boot-directory="$mount_point/boot" \
                                     --efi-directory="$mount_point" "$USB_DEVICE"
        fi
    else
        print_info "BIOS system detected"
        grub_target="i386-pc"
        
        # Install GRUB for BIOS
        if [[ "$DEBUG_MODE" == "true" ]]; then
            print_info "🐛 DEBUG: Installing GRUB for BIOS (target: $grub_target)..."
            sudo grub-install --force --removable --target="$grub_target" \
                             --boot-directory="$mount_point/boot" "$USB_DEVICE"
        else
            run_cmd sudo grub-install --force --removable --target="$grub_target" \
                                     --boot-directory="$mount_point/boot" "$USB_DEVICE"
        fi
    fi
    
    if [[ $? -eq 0 ]]; then
        print_success "GRUB installed successfully"
    else
        print_error "GRUB installation failed"
        safe_umount "$mount_point"
        exit 1
    fi
    
    # Unmount
    safe_umount "$mount_point"
    run_cmd sudo rmdir "$mount_point"
}

copy_grub_config() {
    print_info "Copying GRUB configuration files..."
    
    local mount_point="/mnt/multiboot_usb"
    local partition="${USB_DEVICE}1"
    
    # Mount the USB
    run_cmd sudo mkdir -p "$mount_point"
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_info "🐛 DEBUG: Mounting $partition to $mount_point for GRUB config copy..."
        sudo mount "$partition" "$mount_point"
    else
        run_cmd sudo mount "$partition" "$mount_point"
    fi
    
    # Copy GRUB configuration
    if [[ -d "$GRUB_CONFIG_DIR" ]]; then
        if [[ "$DEBUG_MODE" == "true" ]]; then
            print_info "🐛 DEBUG: Copying GRUB config from $GRUB_CONFIG_DIR to $mount_point/boot/grub/..."
            sudo cp -rf "$GRUB_CONFIG_DIR"/* "$mount_point/boot/grub/"
        else
            run_cmd sudo cp -rf "$GRUB_CONFIG_DIR"/* "$mount_point/boot/grub/"
        fi
        print_success "GRUB configuration files copied"
    else
        print_error "GRUB configuration directory not found: $GRUB_CONFIG_DIR"
        safe_umount "$mount_point"
        exit 1
    fi
    
    # Unmount
    safe_umount "$mount_point"
    run_cmd sudo rmdir "$mount_point"
}

get_usb_uuid() {
    print_info "Getting USB UUID..."
    
    local partition="${USB_DEVICE}1"
    # USB_UUID=$(run_cmd sudo blkid -s UUID -o value "$partition" || true)

    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_info "🐛 DEBUG: Attempting to get UUID directly with: sudo blkid -s UUID -o value \"$partition\""
    fi

    # Capture only the stdout of blkid; redirect its stderr to /dev/null
    local raw_uuid
    raw_uuid=$(sudo blkid -s UUID -o value "$partition" 2>/dev/null)
    local blkid_exit_code=$?

    if [[ "$DEBUG_MODE" == "true" ]]; then
        if [[ $blkid_exit_code -eq 0 && -n "$raw_uuid" ]]; then
            print_info "🐛 DEBUG: Raw output from blkid: '$raw_uuid'"
        elif [[ $blkid_exit_code -ne 0 ]]; then
            print_error "🐛 DEBUG: blkid command failed with exit code: $blkid_exit_code"
        else
            print_warning "🐛 DEBUG: blkid command succeeded but returned an empty UUID."
        fi
    fi

    # Sanitize the UUID: keep only alphanumeric characters and hyphens
    USB_UUID=$(echo "$raw_uuid" | tr -dc '[:alnum:]-')

    if [[ -n "$USB_UUID" ]]; then
        print_success "USB UUID: $USB_UUID"
        if [[ "$DEBUG_MODE" == "true" ]]; then
            print_info "🐛 DEBUG: Full blkid output for $partition:"
            run_cmd_with_output sudo blkid "$partition"
        fi
    else
        print_error "Failed to get USB UUID"
        if [[ "$DEBUG_MODE" == "true" ]]; then
            print_info "🐛 DEBUG: Troubleshooting UUID detection..."
            print_info "🐛 DEBUG: Partition table:"
            run_cmd_with_output sudo fdisk -l "$USB_DEVICE"
            print_info "🐛 DEBUG: All block device UUIDs:"
            run_cmd_with_output sudo blkid
        fi
        # In auto mode, script might proceed and fail later.
        # Consider if exiting here is better if UUID is critical and not found.
        # For now, matching original behavior of trying to continue.
        # exit 1 # Potentially exit if UUID is absolutely critical
    fi
}

detect_partition_table_type() {
    print_info "Detecting partition table type..."
    
    local partition_table_type=$(run_cmd sudo fdisk -l "$USB_DEVICE" | grep "Disklabel type:" | awk '{print $3}' || true)
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_info "🐛 DEBUG: Full fdisk output for partition table detection:"
        run_cmd_with_output sudo fdisk -l "$USB_DEVICE"
        print_info "🐛 DEBUG: Detected partition table type: '$partition_table_type'"
    fi
    
    if [[ "$partition_table_type" == "gpt" ]]; then
        PARTITION_TYPE="gpt"
        PARTITION_REF="gpt1"
        print_success "Detected GPT partition table"
    else
        PARTITION_TYPE="dos"
        PARTITION_REF="msdos1"
        print_success "Detected MBR/DOS partition table"
    fi
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_info "🐛 DEBUG: Set PARTITION_TYPE='$PARTITION_TYPE', PARTITION_REF='$PARTITION_REF'"
    fi
}

update_grub_config() {
    print_info "Updating GRUB configuration with USB UUID and partition type..."
    
    local mount_point="/mnt/multiboot_usb"
    local partition="${USB_DEVICE}1"
    
    # Mount the USB
    run_cmd sudo mkdir -p "$mount_point"
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_info "🐛 DEBUG: Mounting $partition to $mount_point for GRUB config update..."
        sudo mount "$partition" "$mount_point"
    else
        run_cmd sudo mount "$partition" "$mount_point"
    fi
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_info "🐛 DEBUG: Original grub.cfg content (first 20 lines):"
        head -20 "$mount_point/boot/grub/grub.cfg" || true
    fi
    
    # Update grub.cfg with the actual UUID using # as a delimiter for sed
    if [[ -z "$USB_UUID" ]]; then
        print_error "Cannot update grub.cfg: USB_UUID is empty!"
        print_warning "GRUB configuration will NOT be updated with UUID. This will likely cause boot issues."
    else
        if [[ "$DEBUG_MODE" == "true" ]]; then
            print_info "🐛 DEBUG: Updating UUID placeholders with '$USB_UUID' using '#' delimiter in sed..."
        fi
        # Use # as delimiter for sed to avoid issues if USB_UUID could contain /
        run_cmd sudo sed -i "s#YOUR_UUID#${USB_UUID}#g" "$mount_point/boot/grub/grub.cfg"
    fi
    
    # Update partition table references based on detected type
    if [[ "$PARTITION_TYPE" == "gpt" ]]; then
        print_info "Updating configuration for GPT partition table..."
        if [[ "$DEBUG_MODE" == "true" ]]; then
            print_info "🐛 DEBUG: Applying GPT-specific updates..."
        fi
        # Replace insmod part_msdos with part_gpt
        run_cmd sudo sed -i "s/insmod part_msdos/insmod part_gpt/g" "$mount_point/boot/grub/grub.cfg"
        # Replace msdos1 with gpt1
        run_cmd sudo sed -i "s/msdos1/gpt1/g" "$mount_point/boot/grub/grub.cfg"
        # Replace (hd0,1) with (hd0,gpt1) for better compatibility
        run_cmd sudo sed -i "s/'(hd0,1)'/'(hd0,gpt1)'/g" "$mount_point/boot/grub/grub.cfg"
        run_cmd sudo sed -i "s/=(hd0,1)/=(hd0,gpt1)/g" "$mount_point/boot/grub/grub.cfg"
        # Also update hint references
        run_cmd sudo sed -i "s/ahci0,msdos1/ahci0,gpt1/g" "$mount_point/boot/grub/grub.cfg"
    else
        print_info "Using MBR/DOS partition table references (default)..."
        if [[ "$DEBUG_MODE" == "true" ]]; then
            print_info "🐛 DEBUG: Applying MBR-specific updates..."
        fi
        # Ensure part_msdos is used (should already be correct in template)
        run_cmd sudo sed -i "s/insmod part_gpt/insmod part_msdos/g" "$mount_point/boot/grub/grub.cfg"
        # Ensure msdos1 is used (should already be correct in template)
        run_cmd sudo sed -i "s/gpt1/msdos1/g" "$mount_point/boot/grub/grub.cfg"
        # Ensure (hd0,1) format is used for MBR
        run_cmd sudo sed -i "s/'(hd0,gpt1)'/'(hd0,1)'/g" "$mount_point/boot/grub/grub.cfg"
        run_cmd sudo sed -i "s/=(hd0,gpt1)/=(hd0,1)/g" "$mount_point/boot/grub/grub.cfg"
        # Ensure hint references are correct
        run_cmd sudo sed -i "s/ahci0,gpt1/ahci0,msdos1/g" "$mount_point/boot/grub/grub.cfg"
    fi
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_info "🐛 DEBUG: Updated grub.cfg content (first 30 lines):"
        head -30 "$mount_point/boot/grub/grub.cfg" || true
        print_info "🐛 DEBUG: Checking for UUID replacement:"
        grep -n "UUID" "$mount_point/boot/grub/grub.cfg" | head -5 || true
    fi
    
    print_success "GRUB configuration updated with UUID ($USB_UUID) and partition type ($PARTITION_TYPE)"
    
    # Unmount
    safe_umount "$mount_point"
    run_cmd sudo rmdir "$mount_point"
}

copy_iso_files() {
    print_info "Checking for ISO files to copy..."
    
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
    
    # Analyze and calculate total ISO size with validation
    local total_size_kb=0
    local valid_isos=()
    local iso_info=()
    
    print_info "Analyzing ${#iso_files[@]} ISO file(s)..."
    
    for iso in "${iso_files[@]}"; do
        local iso_name=$(basename "$iso")
        local iso_size_kb=$(du -k "$iso" | cut -f1)
        local iso_size_gb=$((iso_size_kb / 1024 / 1024))
        
        # Quick ISO validation and analysis
        local analysis_result=""
        if [[ "$ISO_DETECTION_AVAILABLE" == "true" ]]; then
            if detect_iso_boot_files "$iso"; then
                analysis_result="✓ $ISO_DISTRO"
                valid_isos+=("$iso")
                iso_info+=("$iso_name|$iso_size_gb|$ISO_DISTRO|valid")
            else
                analysis_result="⚠ Unknown"
                valid_isos+=("$iso")
                iso_info+=("$iso_name|$iso_size_gb|unknown|generic")
            fi
        else
            analysis_result="? Not analyzed"
            valid_isos+=("$iso")
            iso_info+=("$iso_name|$iso_size_gb|unknown|basic")
        fi
        
        total_size_kb=$((total_size_kb + iso_size_kb))
        printf "  %-50s %3dGB  %s\n" "$iso_name" "$iso_size_gb" "$analysis_result"
    done
    
    local total_size_gb=$((total_size_kb / 1024 / 1024))
    echo
    print_info "Analysis complete: ${#valid_isos[@]} ISO(s), Total size: ${total_size_gb}GB"
    
    # Check if there's enough space (with 1GB buffer)
    local required_space_gb=$((total_size_gb + 1))
    if [[ $available_space_gb -lt $required_space_gb ]]; then
        print_error "Insufficient space! Need ${required_space_gb}GB, have ${available_space_gb}GB"
        print_info "Available options:"
        echo "  1. Use a larger USB drive"
        echo "  2. Remove some ISO files from $ISOS_DIR"
        echo "  3. Continue without copying ISOs (add them manually later)"
        echo
        read -p "Continue without copying ISOs? (y/n): " skip_copy
        if [[ "$skip_copy" != "y" && "$skip_copy" != "Y" ]]; then
            safe_umount "$mount_point"
            sudo rmdir "$mount_point"
            exit 1
        fi
        print_info "Skipping ISO copy - you can add them manually later"
        safe_umount "$mount_point"
        sudo rmdir "$mount_point"
        return
    fi
    
    # Auto-proceed if space is sufficient (minimal interaction)
    print_success "Space check passed - proceeding with ISO copy..."
    echo
    
    # Copy ISOs with progress and real-time analysis
    local copied_count=0
    local failed_count=0
    
    print_info "=== STARTING ISO COPY PROCESS ==="
    print_info "Total ISOs to copy: ${#valid_isos[@]}"
    echo
    
    for iso in "${valid_isos[@]}"; do
        local iso_name=$(basename "$iso")
        local iso_size_kb=$(du -k "$iso" | cut -f1)
        local iso_size_gb=$((iso_size_kb / 1024 / 1024))
        
        print_info "📀 Processing ISO $((copied_count + failed_count + 1))/${#valid_isos[@]}: $iso_name (${iso_size_gb}GB)"
        
        # Check if ISO already exists on USB (skip if same size)
        if [[ -f "$mount_point/$iso_name" ]]; then
            local existing_size=$(du -k "$mount_point/$iso_name" | cut -f1)
            if [[ $existing_size -eq $iso_size_kb ]]; then
                print_success "✓ $iso_name already exists with correct size - skipping"
                ((copied_count++))
                continue
            else
                print_warning "⚠ $iso_name exists but size differs - replacing..."
                sudo rm -f "$mount_point/$iso_name" 2>/dev/null || true
            fi
        fi
        
        local copy_to_buffer_success=false
        local copy_error_msg=""

        # Determine copy method and execute
        if command -v rsync &> /dev/null; then
            print_info "🔄 Copying $iso_name using rsync with progress..."
            # Using --info=progress2 for overall percentage.
            # --partial allows resuming.
            # --no-inc-recursive because we are copying files one by one.
            # --no-owner and --no-group to prevent chown errors on exFAT/FAT32 filesystems.
            # --times (-t) is kept from --archive to preserve modification times if possible.
            if sudo rsync --times --partial --info=progress2 --no-inc-recursive --no-owner --no-group "$iso" "$mount_point/"; then
                copy_to_buffer_success=true
                print_success "✅ $iso_name copied to system buffers (via rsync)."
            else
                copy_error_msg="rsync copy failed"
                print_warning "❌ rsync copy to buffer failed for $iso_name."
            fi
        elif command -v cp &> /dev/null; then # cp should almost always be available
            print_info "🔄 Copying $iso_name using cp (no detailed progress for this step)..."
            if sudo cp "$iso" "$mount_point/"; then
                copy_to_buffer_success=true
                print_success "✅ $iso_name copied to system buffers (via cp)."
            else
                copy_error_msg="cp copy failed"
                print_error "❌ cp copy to buffer failed for $iso_name."
            fi
        else
            # This case should be rare as 'cp' is a very basic utility.
            copy_error_msg="Neither rsync nor cp command found"
            print_error "❌ Critical: Neither rsync nor cp found. Cannot copy $iso_name."
            # No need to increment failed_count here if we bail or mark all remaining as failed.
            # For simplicity, let the loop increment failed_count based on copy_to_buffer_success.
        fi
        
        # Process result of copy to buffer
        if [[ "$copy_to_buffer_success" == "true" ]]; then
            # Verify copy integrity (checks against buffer/cache initially)
            local copied_size_kb=$(du -k "$mount_point/$iso_name" | cut -f1 2>/dev/null || echo "0")
            if [[ $copied_size_kb -eq $iso_size_kb ]]; then
                print_success "✓ Size verification in buffer passed for $iso_name"
            else
                print_warning "⚠ Size mismatch in buffer detected for $iso_name (expected: ${iso_size_kb}KB, got: ${copied_size_kb}KB)"
                # This could indicate an issue even before sync, but sync might still be attempted.
            fi
            
            # Force sync for this file to ensure it's physically written
            print_info "📡 Ensuring $iso_name is physically written from buffers to USB..."
            
            # Check dirty data before sync
            local dirty_before_kb=$(grep "^Dirty:" /proc/meminfo | awk '{print $2}' || echo 0)
            local dirty_before_mb=$((dirty_before_kb / 1024))
            
            if [[ $dirty_before_kb -gt 100000 ]]; then  # > 100MB dirty
                local sync_message="💾 Writing ~${dirty_before_mb}MB of buffered data for $iso_name..."
            else
                local sync_message="💾 Flushing remaining buffered data for $iso_name..."
            fi
                
            local sync_successful=false # Assume failure until sync confirms success
            # Use the new sync function with spinner and custom message
            if sync_with_spinner "$sync_message"; then 
                sync_successful=true
                ((copied_count++)) # Increment successful physical copies
            else
                print_error "❌ Sync operation FAILED after attempting to write $iso_name."
                print_warning "   This indicates a potentially serious issue with writing to the USB drive."
                print_warning "   The integrity of $iso_name on the USB is not guaranteed."
                ((failed_count++)) # Mark as failed if sync reports an error
            fi
            
            if [[ "$sync_successful" == "true" ]]; then
                # Check dirty data after sync
                local dirty_after_kb=$(grep "^Dirty:" /proc/meminfo | awk '{print $2}' || echo 0)
                local dirty_after_mb=$((dirty_after_kb / 1024))
                local dirty_reduced_kb=$((dirty_before_kb - dirty_after_kb))
                
                if [[ $dirty_reduced_kb -gt 0 ]]; then
                    local dirty_reduced_mb=$((dirty_reduced_kb / 1024))
                    print_success "📉 Reduced dirty buffers by approximately ${dirty_reduced_mb}MB during sync."
                fi
                print_info "💾 Current system dirty buffers: ${dirty_after_mb}MB"
            fi
            
        else # copy_to_buffer_success was false
            ((failed_count++))
            print_error "❌ FAILED (Copy to Buffer): $iso_name - $copy_error_msg ($failed_count failures)"
            print_warning "⚠ Continuing with next ISO..."
        fi
        
        echo "----------------------------------------"
    done
    
    # Final summary
    echo
    print_info "=== ISO COPY SUMMARY ==="
    print_success "✅ Successfully copied: $copied_count ISOs"
    if [[ $failed_count -gt 0 ]]; then
        print_error "❌ Failed to copy: $failed_count ISOs"
    fi
    print_info "📊 Total processed: $((copied_count + failed_count))/${#valid_isos[@]} ISOs"
    
    if [[ $copied_count -gt 0 ]]; then
        print_success "🎉 ISO copy process completed with $copied_count successful copies!"
    else
        print_warning "⚠ No ISO files were copied successfully"
    fi
    
    # Always continue to menu generation regardless of copy results
    print_info "📝 Proceeding to menu generation..."
    
    # Unmount for next step
    safe_umount "$mount_point"
    sudo rmdir "$mount_point"
    
    # Return success to continue script execution
    return 0
}

generate_menu_entries() {
    print_info "Analyzing ISO files and generating menu entries..."
    
    local mount_point="/mnt/multiboot_usb"
    local partition="${USB_DEVICE}1"
    
    # Mount the USB with error handling
    sudo mkdir -p "$mount_point"
    if ! sudo mount "$partition" "$mount_point"; then
        print_error "Failed to mount USB for menu generation"
        print_warning "Menu entries will need to be created manually later."
        return 0  # Don't exit the script, just skip menu generation
    fi
    
    # Find ISO files on the USB
    local iso_files=($(find "$mount_point" -maxdepth 1 -name "*.iso" -type f 2>/dev/null))
    
    if [[ ${#iso_files[@]} -eq 0 ]]; then
        print_info "No ISO files found on USB. Menu entries can be configured manually later."
        safe_umount "$mount_point"
        sudo rmdir "$mount_point" 2>/dev/null || true
        return 0
    fi
    
    print_info "Found ${#iso_files[@]} ISO file(s) on USB, generating menu entries..."
    
    # Create a backup of the original config
    if [[ -f "$mount_point/boot/grub/grub.cfg" ]]; then
        sudo cp "$mount_point/boot/grub/grub.cfg" "$mount_point/boot/grub/grub.cfg.backup" 2>/dev/null || true
        
        # Create custom entries file
        local custom_entries=""
        
        if [[ "$ISO_DETECTION_AVAILABLE" == "true" ]]; then
            # Use advanced ISO detection
            print_info "Using automatic kernel/initrd detection..."
            custom_entries=$(generate_advanced_menu_entries_content "$mount_point" "${iso_files[@]}")
        else
            # Use manual entries for common distributions
            print_info "Using manual entries for common distributions..."
            custom_entries=$(generate_manual_menu_entries_content "${iso_files[@]}")
        fi
        
        # Add custom entries to grub.cfg
        if [[ -n "$custom_entries" ]]; then
            {
                echo ""
                echo "#==============================================#"
                echo "#          Custom ISO Menu Entries          #"
                echo "#==============================================#"
                echo ""
                echo "$custom_entries"
            } | sudo tee -a "$mount_point/boot/grub/grub.cfg" > /dev/null
            
            print_success "✅ Menu entries added to GRUB configuration"
        else
            print_warning "⚠ No menu entries were generated"
        fi
    else
        print_warning "GRUB config file not found, skipping menu generation"
    fi
    
    # Unmount with error handling
    safe_umount "$mount_point"
    sudo rmdir "$mount_point" 2>/dev/null || true
    
    print_success "Menu entry generation completed"
    return 0  # Ensure successful return
}

# Generate manual menu entries for common distributions (fallback method)
generate_manual_menu_entries_content() {
    local iso_files=("$@")
    local entries=""
    local entries_count=0
    
    for iso_path in "${iso_files[@]}"; do
        local iso_name=$(basename "$iso_path")
        local iso_lower=$(echo "$iso_name" | tr '[:upper:]' '[:lower:]')
        
        print_info "📝 Creating manual entry for $iso_name..."
        
        # Linux Mint entries
        if [[ "$iso_lower" == *"mint"* ]]; then
            entries+="# Linux Mint - $iso_name"$'\n'
            entries+="menuentry \"Linux Mint - $iso_name\" --class mint --class linux {"$'\n'
            entries+="    set root='(hd0,$PARTITION_REF)'"$'\n'
            entries+="    set isofile=\"/$iso_name\""$'\n'
            entries+="    loopback loop \$isofile"$'\n'
            entries+="    linux (loop)/casper/vmlinuz boot=casper iso-scan/filename=\${isofile} quiet splash vt.global_cursor_default=0 loglevel=2 rd.systemd.show_status=false rd.udev.log-priority=3 sysrq_always_enabled=1 cow_spacesize=1G"$'\n'
            entries+="    initrd (loop)/casper/initrd"$'\n'
            entries+="}"$'\n'
            entries+=""$'\n'
            ((entries_count++))
            print_success "✓ Added Linux Mint entry"
            
        # Kubuntu entries  
        elif [[ "$iso_lower" == *"kubuntu"* ]]; then
            entries+="# Kubuntu - $iso_name"$'\n'
            entries+="menuentry \"Kubuntu - $iso_name\" --class kubuntu --class linux {"$'\n'
            entries+="    set root='(hd0,$PARTITION_REF)'"$'\n'
            entries+="    set isofile=\"/$iso_name\""$'\n'
            entries+="    loopback loop \$isofile"$'\n'
            entries+="    linux (loop)/casper/vmlinuz boot=casper iso-scan/filename=\${isofile} quiet splash"$'\n'
            entries+="    initrd (loop)/casper/initrd"$'\n'
            entries+="}"$'\n'
            entries+=""$'\n'
            ((entries_count++))
            print_success "✓ Added Kubuntu entry"
            
        # Ubuntu entries
        elif [[ "$iso_lower" == *"ubuntu"* ]]; then
            entries+="# Ubuntu - $iso_name"$'\n'
            entries+="menuentry \"Ubuntu - $iso_name\" --class ubuntu --class linux {"$'\n'
            entries+="    set root='(hd0,$PARTITION_REF)'"$'\n'
            entries+="    set isofile=\"/$iso_name\""$'\n'
            entries+="    loopback loop \$isofile"$'\n'
            entries+="    linux (loop)/casper/vmlinuz boot=casper iso-scan/filename=\${isofile} quiet splash"$'\n'
            entries+="    initrd (loop)/casper/initrd"$'\n'
            entries+="}"$'\n'
            entries+=""$'\n'
            ((entries_count++))
            print_success "✓ Added Ubuntu entry"
            
        # Generic entries for other ISOs
        else
            entries+="# Generic Linux - $iso_name"$'\n'
            entries+="menuentry \"Linux ISO - $iso_name\" --class linux {"$'\n'
            entries+="    set root='(hd0,$PARTITION_REF)'"$'\n'
            entries+="    set isofile=\"/$iso_name\""$'\n'
            entries+="    loopback loop \$isofile"$'\n'
            entries+="    linux (loop)/casper/vmlinuz boot=casper iso-scan/filename=\${isofile} quiet splash"$'\n'
            entries+="    initrd (loop)/casper/initrd"$'\n'
            entries+="}"$'\n'
            entries+=""$'\n'
            ((entries_count++))
            print_success "✓ Added generic entry"
        fi
    done
    
    if [[ $entries_count -gt 0 ]]; then
        print_success "📝 Generated $entries_count manual menu entries"
    else
        print_warning "⚠ No manual entries were created"
    fi
    
    echo "$entries"
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
    echo "  Partition Table: $PARTITION_TYPE (auto-detected)"
    if [[ "$ISO_DETECTION_AVAILABLE" == "true" ]]; then
        echo "  ISO Detection: Enhanced (automatic kernel/initrd detection)"
    else
        echo "  ISO Detection: Basic (pattern matching)"
    fi
    echo
    print_info "To add more ISOs later:"
    echo "  1. Mount the USB drive"
    echo "  2. Copy ISO files to the root directory (any size supported)"
    echo "  3. Edit /boot/grub/grub.cfg to add menu entries"
    if [[ "$ISO_DETECTION_AVAILABLE" == "true" ]]; then
        echo "  4. Or use: sudo ./analyze_iso.sh your_new_iso.iso"
    fi
    echo
    print_info "ISO storage location: Root of USB drive"
    print_info "Configuration backup: /boot/grub/grub.cfg.backup"
    print_info "Technical note: GRUB configuration automatically adjusted for $PARTITION_TYPE partition table"
}

# Main execution
main() {
    # Handle command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                print_header
                print_usage
                exit 0
                ;;
            --auto|-a)
                AUTO_MODE=true
                shift
                ;;
            --debug|-d)
                DEBUG_MODE=true
                shift
                ;;
            "")
                # Empty argument, skip
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    print_header
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_warning "🐛 DEBUG MODE ENABLED"
        print_info "• All command output will be shown"
        print_info "• Detailed execution information will be displayed"
        print_info "• This may produce verbose output"
        echo
    fi
    
    if [[ "$AUTO_MODE" == "true" ]]; then
        print_success "🤖 AUTO MODE ENABLED"
        print_info "• Single USB device will be auto-selected"
        print_info "• Automatic confirmation with 3-second safety delay"
        print_info "• ISOs will be automatically analyzed and copied"
        print_info "• Enhanced menu generation with minimal interaction"
        echo
    fi
    
    # Initialize ISO detection capabilities
    init_iso_detection
    
    # Execute main steps with error handling
    local main_error=false
    
    print_info "🚀 Starting multiboot USB creation process..."
    echo
    
    # Step 1: Initial checks
    check_root
    check_dependencies
    detect_usb_devices
    check_usb_ready
    confirm_usb_format
    
    print_info "✅ Initial checks completed - starting USB preparation..."
    
    # Step 2: USB preparation
    if ! partition_usb; then
        print_error "❌ USB partitioning failed"
        main_error=true
    fi
    
    if ! format_usb; then
        print_error "❌ USB formatting failed"
        main_error=true
    fi
    
    # Step 3: GRUB installation
    if ! install_grub; then
        print_error "❌ GRUB installation failed"
        main_error=true
    fi
    
    if ! copy_grub_config; then
        print_error "❌ GRUB configuration copy failed"
        main_error=true
    fi
    
    # Step 4: Configuration
    if ! get_usb_uuid; then
        print_error "❌ Failed to get USB UUID"
        main_error=true
    fi
    
    if ! detect_partition_table_type; then
        print_error "❌ Failed to detect partition table type"
        main_error=true
    fi
    
    if ! update_grub_config; then
        print_error "❌ Failed to update GRUB configuration"
        main_error=true
    fi
    
    # Step 5: ISO copying (non-critical - continue even if fails)
    print_info "📀 Starting ISO copy process..."
    copy_iso_files || print_warning "⚠ ISO copying had issues but continuing..."
    
    # Step 6: Menu generation (non-critical - continue even if fails)
    print_info "📝 Starting menu generation process..."
    generate_menu_entries || print_warning "⚠ Menu generation had issues but USB is still functional..."
    
    # Step 7: Always show completion info
    echo
    print_info "🏁 MULTIBOOT USB CREATION PROCESS COMPLETED"
    echo
    
    if [[ "$main_error" == "true" ]]; then
        print_warning "⚠ Some critical steps had errors - USB may not be fully functional"
        print_info "💡 Try running the script again or check the errors above"
    else
        print_success "🎉 All main steps completed successfully!"
    fi
    
    # Always show completion info regardless of errors
    show_completion_info
    
    # Exit with appropriate code
    if [[ "$main_error" == "true" ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@" 