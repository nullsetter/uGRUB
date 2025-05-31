#!/bin/bash

#==============================================#
#     ISO Kernel/Initrd Detection Functions   #
#     For integration with multiboot script   #
#==============================================#

# Auto-detect kernel and initrd paths in an ISO file
# Usage: detect_iso_boot_files "/path/to/file.iso"
# Returns: Sets global variables ISO_KERNEL, ISO_INITRD, ISO_DISTRO
detect_iso_boot_files() {
    local iso_file="$1"
    local temp_mount="/tmp/iso_detect_$$"
    
    # Reset global variables
    ISO_KERNEL=""
    ISO_INITRD=""
    ISO_DISTRO=""
    ISO_BOOT_PARAMS=""
    
    if [[ ! -f "$iso_file" ]]; then
        print_error "ISO file not found: $iso_file"
        return 1
    fi
    
    # Create temporary mount point
    sudo mkdir -p "$temp_mount" || return 1
    
    # Mount ISO read-only
    if ! sudo mount -o loop,ro "$iso_file" "$temp_mount" 2>/dev/null; then
        print_warning "Failed to mount ISO for analysis: $(basename "$iso_file")"
        sudo rmdir "$temp_mount" 2>/dev/null
        return 1
    fi
    
    # Detect distribution
    ISO_DISTRO=$(detect_iso_distribution "$temp_mount")
    
    # Find kernel and initrd
    local kernels=($(find_iso_kernels "$temp_mount"))
    local initrds=($(find_iso_initrds "$temp_mount"))
    
    # Select the best kernel/initrd pair
    if [[ ${#kernels[@]} -gt 0 ]]; then
        ISO_KERNEL="${kernels[0]}"  # Take first/best match
    fi
    
    if [[ ${#initrds[@]} -gt 0 ]]; then
        ISO_INITRD="${initrds[0]}"  # Take first/best match
    fi
    
    # Set appropriate boot parameters based on distribution
    set_iso_boot_params "$ISO_DISTRO" "$temp_mount"
    
    # Cleanup
    sudo umount "$temp_mount" 2>/dev/null
    sudo rmdir "$temp_mount" 2>/dev/null
    
    # Return success if we found at least a kernel
    [[ -n "$ISO_KERNEL" ]]
}

# Detect distribution from mounted ISO
detect_iso_distribution() {
    local mount_point="$1"
    
    # Check Ubuntu/Debian family
    if [[ -f "$mount_point/.disk/info" ]]; then
        local info=$(cat "$mount_point/.disk/info" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        case "$info" in
            *ubuntu*) echo "ubuntu" ;;
            *kubuntu*) echo "kubuntu" ;;
            *xubuntu*) echo "xubuntu" ;;
            *lubuntu*) echo "lubuntu" ;;
            *mint*) echo "mint" ;;
            *elementary*) echo "elementary" ;;
            *) echo "debian" ;;
        esac
        return 0
    fi
    
    # Check for other distributions
    if [[ -d "$mount_point/arch" && -f "$mount_point/arch/boot/x86_64/vmlinuz-linux" ]]; then
        echo "arch"
    elif [[ -d "$mount_point/suse" || -f "$mount_point/.opensuse-factory" ]]; then
        echo "opensuse"
    elif [[ -f "$mount_point/fedora_label" || -d "$mount_point/Fedora" ]]; then
        echo "fedora"
    elif [[ -d "$mount_point/centos" || -f "$mount_point/.centos" ]]; then
        echo "centos"
    elif [[ -d "$mount_point/live" && -f "$mount_point/live/vmlinuz" ]]; then
        echo "debian-live"
    elif [[ -f "$mount_point/manjaro" || "$mount_point" == *manjaro* ]]; then
        echo "manjaro"
    elif [[ -d "$mount_point/antergos" ]]; then
        echo "antergos"
    else
        echo "unknown"
    fi
}

# Find kernel files in mounted ISO
find_iso_kernels() {
    local mount_point="$1"
    local kernels=()
    
    # Distribution-specific kernel locations (ordered by priority)
    local kernel_searches=(
        # Ubuntu/Debian Live (highest priority)
        "$mount_point/casper/vmlinuz*"
        # Arch Linux
        "$mount_point/arch/boot/x86_64/vmlinuz*"
        # Fedora/CentOS
        "$mount_point/images/pxeboot/vmlinuz*"
        # openSUSE
        "$mount_point/boot/x86_64/loader/linux"
        # Debian Live
        "$mount_point/live/vmlinuz*"
        # Generic locations
        "$mount_point/boot/vmlinuz*"
        "$mount_point/boot/bzImage*"
        "$mount_point/isolinux/vmlinuz*"
        "$mount_point/syslinux/vmlinuz*"
        # Root level (lowest priority)
        "$mount_point/vmlinuz*"
        "$mount_point/linux*"
    )
    
    for search in "${kernel_searches[@]}"; do
        for file in $search; do
            if [[ -f "$file" ]]; then
                # Exclude GRUB modules, focus on actual bootable kernels
                if [[ ! "$file" =~ /boot/grub/ ]]; then
                    local basename=$(basename "$file")
                    # Only include files that look like kernels
                    if [[ "$basename" =~ ^(vmlinuz|bzImage|linux|kernel) ]] && [[ ! "$basename" =~ \.(mod|img)$ ]]; then
                        local rel_path="${file#$mount_point}"
                        kernels+=("$rel_path")
                    fi
                fi
            fi
        done
    done
    
    # Remove duplicates and return
    printf '%s\n' "${kernels[@]}" | sort -u
}

# Find initrd files in mounted ISO  
find_iso_initrds() {
    local mount_point="$1"
    local initrds=()
    
    # Distribution-specific initrd locations (ordered by priority)
    local initrd_searches=(
        # Ubuntu/Debian Live (highest priority)
        "$mount_point/casper/initrd*"
        # Arch Linux
        "$mount_point/arch/boot/x86_64/initramfs*"
        "$mount_point/arch/boot/amd-ucode.img"
        "$mount_point/arch/boot/intel-ucode.img"
        # Fedora/CentOS
        "$mount_point/images/pxeboot/initrd*"
        # openSUSE
        "$mount_point/boot/x86_64/loader/initrd"
        # Debian Live
        "$mount_point/live/initrd*"
        # Generic locations
        "$mount_point/boot/initrd*"
        "$mount_point/boot/initramfs*"
        "$mount_point/isolinux/initrd*"
        "$mount_point/syslinux/initrd*"
        # Root level
        "$mount_point/initrd*"
        "$mount_point/initramfs*"
    )
    
    for search in "${initrd_searches[@]}"; do
        for file in $search; do
            if [[ -f "$file" ]]; then
                # Exclude GRUB modules and kernel files
                if [[ ! "$file" =~ /boot/grub/ ]]; then
                    local basename=$(basename "$file")
                    # Only include files that look like initrd/initramfs
                    if [[ "$basename" =~ ^(initrd|initramfs|ramdisk) ]] || 
                       [[ "$basename" =~ \.(img|gz|lz|xz|lzma)$ && ! "$basename" =~ ^(eltorito|boot|vmlinuz|bzImage|linux|kernel) ]]; then
                        local rel_path="${file#$mount_point}"
                        initrds+=("$rel_path")
                    fi
                fi
            fi
        done
    done
    
    # Remove duplicates and return
    printf '%s\n' "${initrds[@]}" | sort -u
}

# Set appropriate boot parameters based on distribution
set_iso_boot_params() {
    local distro="$1"
    local mount_point="$2"
    
    case "$distro" in
        ubuntu|kubuntu|xubuntu|lubuntu|mint|elementary|debian)
            ISO_BOOT_PARAMS="boot=casper iso-scan/filename=\${isofile} quiet splash"
            ;;
        arch|manjaro|antergos)
            ISO_BOOT_PARAMS="img_loop=\${isofile} driver=free quiet splash cow_spacesize=1G"
            ;;
        fedora|centos)
            ISO_BOOT_PARAMS="root=live:CDLABEL=\$(blkid -s LABEL -o value \$root) rd.live.image quiet"
            ;;
        opensuse)
            ISO_BOOT_PARAMS="isofrom_device=/dev/disk/by-uuid/\$(blkid -s UUID -o value \$root) isofrom_system=\${isofile} quiet splash"
            ;;
        debian-live)
            ISO_BOOT_PARAMS="boot=live components quiet splash findiso=\${isofile}"
            ;;
        *)
            ISO_BOOT_PARAMS="iso-scan/filename=\${isofile} quiet splash"
            ;;
    esac
}

# Generate a complete GRUB menu entry for an ISO
generate_auto_grub_entry() {
    local iso_file="$1"
    local entry_title="$2"
    local iso_name=$(basename "$iso_file")
    
    if [[ -z "$entry_title" ]]; then
        entry_title="$ISO_DISTRO - $iso_name"
    fi
    
    local class_name=$(echo "$ISO_DISTRO" | tr '[:upper:]' '[:lower:]' | tr ' -' '__')
    
    cat << EOF
menuentry "$entry_title" --class $class_name --class linux {
    set root='(hd0,1)'
    set isofile="/$iso_name"
    loopback loop \$isofile
EOF
    
    if [[ -n "$ISO_KERNEL" ]]; then
        echo "    linux (loop)$ISO_KERNEL $ISO_BOOT_PARAMS"
    else
        echo "    # ERROR: No kernel found!"
    fi
    
    if [[ -n "$ISO_INITRD" ]]; then
        echo "    initrd (loop)$ISO_INITRD"
    else
        echo "    # WARNING: No initrd found"
    fi
    
    echo "}"
}

# Batch analyze all ISOs in a directory
analyze_iso_directory() {
    local iso_dir="$1"
    local results_file="$2"
    
    if [[ ! -d "$iso_dir" ]]; then
        print_error "Directory not found: $iso_dir"
        return 1
    fi
    
    local iso_files=($(find "$iso_dir" -name "*.iso" -type f))
    
    if [[ ${#iso_files[@]} -eq 0 ]]; then
        print_warning "No ISO files found in $iso_dir"
        return 1
    fi
    
    print_info "Analyzing ${#iso_files[@]} ISO file(s)..."
    
    if [[ -n "$results_file" ]]; then
        echo "# Auto-generated GRUB entries" > "$results_file"
        echo "# Generated on $(date)" >> "$results_file"
        echo >> "$results_file"
    fi
    
    for iso_file in "${iso_files[@]}"; do
        local iso_name=$(basename "$iso_file")
        print_info "Processing: $iso_name"
        
        if detect_iso_boot_files "$iso_file"; then
            print_success "✓ $iso_name: $ISO_DISTRO (kernel: $ISO_KERNEL)"
            
            if [[ -n "$results_file" ]]; then
                echo "# $iso_name - $ISO_DISTRO" >> "$results_file"
                generate_auto_grub_entry "$iso_file" >> "$results_file"
                echo >> "$results_file"
            fi
        else
            print_warning "✗ $iso_name: Could not detect boot files"
        fi
    done
    
    if [[ -n "$results_file" ]]; then
        print_success "Results saved to: $results_file"
    fi
} 