#!/bin/bash

#==============================================#
#     ISO Analysis and Kernel Detection       #
#     Auto-detect kernel/initrd paths         #
#==============================================#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# Source the detection functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/iso_detection_functions.sh" ]]; then
    source "$SCRIPT_DIR/iso_detection_functions.sh"
else
    print_error "Detection functions not found: $SCRIPT_DIR/iso_detection_functions.sh"
    exit 1
fi

analyze_iso() {
    local iso_file="$1"
    
    if [[ ! -f "$iso_file" ]]; then
        print_error "ISO file not found: $iso_file"
        return 1
    fi
    
    print_info "Analyzing ISO: $(basename "$iso_file")"
    echo "==============================================="
    
    # Use the improved detection functions
    if detect_iso_boot_files "$iso_file"; then
        print_info "Detected distribution: $ISO_DISTRO"
        
        if [[ -n "$ISO_KERNEL" ]]; then
            print_info "Found kernel: $ISO_KERNEL"
        else
            print_warning "No kernel found"
        fi
        
        if [[ -n "$ISO_INITRD" ]]; then
            print_info "Found initrd: $ISO_INITRD"
        else
            print_warning "No initrd found"
        fi
        
        # Generate GRUB entry
        echo
        print_info "Suggested GRUB menu entry:"
        echo "----------------------------------------"
        generate_auto_grub_entry "$iso_file"
        
        # Show boot parameters
        echo
        print_info "Boot parameters: $ISO_BOOT_PARAMS"
        
    else
        print_error "Failed to analyze ISO file"
        return 1
    fi
}

# Main execution
if [[ $# -eq 0 ]]; then
    echo "ISO Analysis and Kernel Detection Tool"
    echo "Usage: $0 <iso_file> [iso_file2] ..."
    echo
    echo "Examples:"
    echo "  $0 ubuntu-20.04.3-desktop-amd64.iso"
    echo "  $0 *.iso"
    exit 1
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script requires sudo privileges to mount ISOs"
    print_info "Run with: sudo $0 $*"
    exit 1
fi

# Analyze each ISO file
for iso_file in "$@"; do
    if [[ -f "$iso_file" ]]; then
        analyze_iso "$iso_file"
        echo
        echo "==============================================="
        echo
    else
        print_error "File not found: $iso_file"
    fi
done 