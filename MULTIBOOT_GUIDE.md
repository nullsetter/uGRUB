# Interactive Multiboot USB Creation Guide

This guide provides step-by-step instructions for creating a multiboot USB drive using the automated scripts based on the uGRUB project.

## Overview

The interactive scripts automate the process described in the original README.md with minimal human interaction required. Two main scripts are provided:

1. **`prepare_multiboot_usb.sh`** - Main script to create multiboot USB
2. **`manage_isos.sh`** - Utility to manage ISO files on existing multiboot USB

## Prerequisites

### System Requirements
- Linux-based operating system
- Root/sudo privileges
- USB drive (8GB+ recommended)

### Filesystem: exFAT Advantages
The script now uses **exFAT** as the default filesystem, providing several advantages over the traditional FAT32:

#### ✅ **Benefits of exFAT:**
- **No 4GB file size limit** - Large ISOs (like your 4.4GB Kubuntu ISO) copy without issues
- **Cross-platform compatibility** - Works with Windows, macOS, and Linux
- **Better performance** - More efficient for large files and modern flash drives
- **Modern design** - Optimized for flash memory and external storage devices

#### ⚠️ **Considerations:**
- Requires `exfatprogs` package (automatically checked by script)
- Slightly newer technology (well-supported on systems from 2010+)
- Some very old systems might need exFAT driver installation

### Required Tools
The script will check for these dependencies automatically:
- `fdisk` - Disk partitioning
- `mkfs.exfat` - exFAT formatting  
- `grub-install` - GRUB bootloader installation
- `lsblk` - List block devices
- `blkid` - Block device identification
- `mount`/`umount` - Mounting operations

### Optional Tools (for enhanced experience):
- `pv` - Progress display during ISO copying (provides real-time progress bars)
- `rsync` - Alternative copy method with progress (fallback if pv unavailable)

### Installation on Ubuntu/Debian:
```bash
sudo apt update
sudo apt install fdisk exfatprogs grub2-common grub-pc-bin grub-efi-amd64-bin util-linux pv
```

### Installation on Arch Linux:
```bash
sudo pacman -S util-linux exfatprogs grub pv
```

### Installation on Fedora/CentOS:
```bash
sudo dnf install util-linux exfatprogs grub2-tools grub2-efi-x64 pv
```

### Copy Methods and Progress Display

The script uses an intelligent fallback system for copying ISO files:

1. **Primary: `pv` method** (if available)
   - ✅ Real-time progress bar with transfer speed
   - ✅ ETA (estimated time remaining)
   - ✅ Visual feedback during large file transfers
   - ✅ Example: `2.98GB 100% 1.62GB/s 0:00:01`

2. **Secondary: `rsync` method** (fallback)
   - ✅ Progress indication with transfer statistics
   - ✅ Resume capability for interrupted transfers
   - ✅ Efficient copying algorithm

3. **Tertiary: `cp` method** (final fallback)
   - ✅ Basic copy functionality
   - ✅ Reliable on all systems
   - ⚠️ No progress indication

**Installation recommendation:** Install `pv` for the best user experience during ISO copying operations.

## Quick Start

### Step 1: Prepare ISO Files
Place your ISO files in the `isos/` directory:
```bash
# ISO files are already present in the isos directory:
ls isos/
# kubuntu-25.04-desktop-amd64.iso
# linuxmint-22.1-cinnamon-64bit.iso
```

### Step 2: Run the Main Script
```bash
./prepare_multiboot_usb.sh
```

### Step 3: Follow Interactive Prompts
The script will guide you through:
1. USB device selection
2. Confirmation of data destruction warning
3. Automatic partitioning and formatting
4. GRUB installation (UEFI/BIOS auto-detection)
5. Configuration copying and UUID updating
6. ISO file copying (optional)
7. Menu entry generation

## Detailed Script Features

### Main Script: `prepare_multiboot_usb.sh`

#### Features:
- ✅ **Automatic USB Detection** - Lists available USB devices with sizes
- ✅ **Safety Checks** - Multiple confirmation prompts before data destruction
- ✅ **UEFI/BIOS Auto-Detection** - Automatically configures for your system
- ✅ **UUID Management** - Automatically updates GRUB configuration with USB UUID
- ✅ **Error Handling** - Comprehensive error checking and recovery
- ✅ **Progress Indicators** - Clear status messages throughout the process
- ✅ **Dependency Verification** - Checks for required tools before starting

#### Process Flow:
1. **Preparation Phase**
   - Dependency checking
   - USB device detection and selection
   - Safety confirmations

2. **USB Preparation Phase**
   - Automatic partitioning (deletes all existing partitions)
   - exFAT formatting with "Multiboot" label (supports files > 4GB)
   - Bootable flag setting

3. **GRUB Installation Phase**
   - Boot mode detection (UEFI vs BIOS)
   - Appropriate GRUB target selection
   - Bootloader installation with removable flag

4. **Configuration Phase**
   - GRUB theme and configuration copying
   - UUID extraction and replacement
   - Menu entry preparation

5. **ISO Management Phase**
   - Optional ISO copying from `isos/` directory
   - Automatic menu entry generation for recognized distributions
   - Configuration backup creation

#### Supported Distributions (Auto-Detection):
- Ubuntu variants (Ubuntu, Kubuntu, Xubuntu)
- Linux Mint
- Arch Linux
- More can be added by modifying the menu entry patterns

### Utility Script: `manage_isos.sh`

#### Features:
- 📋 **ISO Inventory** - List ISOs in local `isos/` directory
- 📤 **Copy Management** - Selective copying of ISOs to USB
- 📊 **USB Analysis** - Show ISOs and available space on USB
- 🗑️ **Cleanup Tools** - Remove ISOs from USB drive
- 🔍 **Auto-Detection** - Finds existing multiboot USB drives

#### Menu Options:
1. **List Available ISOs** - Shows ISOs in `isos/` directory with sizes
2. **Copy ISOs to USB** - Interactive selection and copying
3. **List USB ISOs** - Show current ISOs on multiboot USB
4. **Remove USB ISOs** - Selective removal of ISOs from USB
5. **Exit** - Clean script termination

## File Structure

After successful setup, your multiboot USB will have this structure:
```
USB Root/
├── boot/
│   └── grub/
│       ├── grub.cfg                 # Main GRUB configuration
│       ├── grub.cfg.backup         # Backup of original config
│       ├── themes/                 # GRUB themes
│       │   ├── Stylish/           # Default theme
│       │   ├── Tela/              # Alternative themes
│       │   ├── Slaze/
│       │   └── Vimix/
│       └── fonts/                  # GRUB fonts
├── EFI/                           # UEFI boot files (if UEFI system)
│   └── BOOT/
│       └── BOOTX64.EFI
├── your-iso-file-1.iso            # Your ISO files
├── your-iso-file-2.iso
└── ...
```

## Usage Examples

### Example 1: Basic Multiboot USB Creation
```bash
# 1. Place ISOs in the isos directory
cp ~/Downloads/ubuntu-22.04.iso isos/
cp ~/Downloads/arch-linux.iso isos/

# 2. Run the preparation script
./prepare_multiboot_usb.sh

# 3. Follow prompts:
# - Select USB device (e.g., /dev/sdb)
# - Confirm data destruction
# - Choose to copy ISOs
# - Script handles the rest automatically
```

### Example 2: Managing ISOs Later
```bash
# Run the ISO management utility
./manage_isos.sh

# Use menu to:
# - Add new ISOs to USB
# - Remove old ISOs to free space
# - Check available space
```

### Example 3: Adding New Distributions
```bash
# 1. Download new ISO
wget https://releases.ubuntu.com/22.04/ubuntu-22.04.3-desktop-amd64.iso -P isos/

# 2. Copy to existing multiboot USB
./manage_isos.sh
# Select option 2, then select the new ISO

# 3. Manually update GRUB menu entry (if needed)
# Mount USB and edit /boot/grub/grub.cfg
```

## Manual Menu Entry Creation

If the automatic menu generation doesn't work for your specific distribution, you can manually add entries:

### Menu Entry Template:
```
menuentry "Distribution Name" --class icon-name --class linux {
    set root='(hd0,1)'
    set isofile="/your-iso-file.iso"
    loopback loop $isofile
    linux (loop)/path/to/kernel iso-scan/filename=${isofile} additional_parameters
    initrd (loop)/path/to/initrd
}
```

### Real Examples:

#### Example 1: Kubuntu 25.04
```
menuentry "Kubuntu 25.04 Desktop" --class kubuntu --class linux {
    set root='(hd0,1)'
    set isofile="/kubuntu-25.04-desktop-amd64.iso"
    loopback loop $isofile
    linux (loop)/casper/vmlinuz boot=casper iso-scan/filename=${isofile} quiet splash vt.global_cursor_default=0 loglevel=2 rd.systemd.show_status=false rd.udev.log-priority=3 sysrq_always_enabled=1 cow_spacesize=1G
    initrd (loop)/casper/initrd
}
```

#### Example 2: Linux Mint 22.1
```
menuentry "Linux Mint 22.1 Cinnamon" --class mint --class linux {
    set root='(hd0,1)'
    set isofile="/linuxmint-22.1-cinnamon-64bit.iso"
    loopback loop $isofile
    linux (loop)/casper/vmlinuz boot=casper iso-scan/filename=${isofile} quiet splash vt.global_cursor_default=0 loglevel=2 rd.systemd.show_status=false rd.udev.log-priority=3 sysrq_always_enabled=1 cow_spacesize=1G
    initrd (loop)/casper/initrd
}
```

#### Example 3: Arch Linux
```
menuentry "Arch Linux Live ISO" --class arch --class archlinux --class linux {
    set root='(hd0,1)'
    set isofile="/archlinux-2024.01.01-x86_64.iso"
    set dri="free"
    search --no-floppy -f --set=root $isofile
    probe -u $root --set=abc
    set pqr="/dev/disk/by-uuid/$abc"
    loopback loop $isofile
    linux (loop)/arch/boot/x86_64/vmlinuz-linux img_dev=$pqr img_loop=$isofile driver=$dri quiet splash vt.global_cursor_default=0 loglevel=2 rd.systemd.show_status=false rd.udev.log-priority=3 sysrq_always_enabled=1 cow_spacesize=1G
    initrd (loop)/arch/boot/amd-ucode.img (loop)/arch/boot/intel-ucode.img (loop)/arch/boot/x86_64/archiso.img
}
```

#### Example 4: Ubuntu 22.04 LTS
```
menuentry "Ubuntu 22.04 LTS Desktop" --class ubuntu --class linux {
    set root='(hd0,1)'
    set isofile="/ubuntu-22.04.3-desktop-amd64.iso"
    loopback loop $isofile
    linux (loop)/casper/vmlinuz boot=casper iso-scan/filename=${isofile} quiet splash vt.global_cursor_default=0 loglevel=2 rd.systemd.show_status=false rd.udev.log-priority=3 sysrq_always_enabled=1 cow_spacesize=1G
    initrd (loop)/casper/initrd
}
```

### Key Components Explained:

#### Menu Entry Structure:
- **`menuentry "Title"`** - Display name in GRUB menu
- **`--class icon-name`** - Icon theme class for visual representation
- **`set root='(hd0,1)'`** - GRUB device notation for first partition of first disk
- **`set isofile="/filename.iso"`** - Path to ISO file on USB root

#### Boot Parameters:
- **`boot=casper`** - Ubuntu/Debian live boot system
- **`iso-scan/filename=${isofile}`** - Tells kernel where to find the ISO
- **`quiet splash`** - Minimal boot output with splash screen
- **`vt.global_cursor_default=0`** - Hide text cursor
- **`loglevel=2`** - Reduce kernel log verbosity
- **`cow_spacesize=1G`** - Allocate 1GB for changes overlay

### Finding Kernel and Initrd Paths:
```bash
# Mount the ISO to examine its structure
sudo mkdir /mnt/iso
sudo mount -o loop your-iso-file.iso /mnt/iso
ls -la /mnt/iso
# Look for boot/, casper/, live/, or arch/ directories
sudo umount /mnt/iso
```

### What Kernel and Initrd Files Look Like:

#### **Kernel Files** (executable, usually 5-15MB):
**Common Names:**
- `vmlinuz` - Standard Linux kernel naming
- `vmlinuz-linux` - Arch Linux style
- `vmlinuz.efi` - UEFI kernels
- `bzImage` - Alternative kernel name
- `linux` - Simple naming (some distros)

**Examples by Distribution:**
- **Ubuntu/Kubuntu/Mint**: `/casper/vmlinuz`
- **Arch Linux**: `/arch/boot/x86_64/vmlinuz-linux`
- **Fedora**: `/isolinux/vmlinuz` or `/images/pxeboot/vmlinuz`
- **Debian**: `/live/vmlinuz-*` or `/install/vmlinuz`
- **CentOS/RHEL**: `/isolinux/vmlinuz` or `/images/pxeboot/vmlinuz`
- **openSUSE**: `/boot/x86_64/loader/linux`

#### **Initrd Files** (compressed archive, usually 20-500MB):
**Common Names:**
- `initrd` - Standard initial ramdisk
- `initrd.img` - With .img extension
- `initramfs` - Modern initramfs naming
- `archiso.img` - Arch Linux specific
- `filesystem.squashfs` - Some live systems

**Examples by Distribution:**
- **Ubuntu/Kubuntu/Mint**: `/casper/initrd`
- **Arch Linux**: `/arch/boot/x86_64/archiso.img`
- **Fedora**: `/isolinux/initrd.img` or `/images/pxeboot/initrd.img`
- **Debian**: `/live/initrd.img-*`
- **CentOS/RHEL**: `/isolinux/initrd.img`
- **openSUSE**: `/boot/x86_64/loader/initrd`

### **Real File Structure Examples:**

#### Ubuntu/Kubuntu/Mint ISO Structure:
```
/mnt/iso/
├── casper/
│   ├── vmlinuz              ← Kernel file (~10MB)
│   ├── initrd               ← Initrd file (~50-100MB)
│   ├── filesystem.squashfs  ← Root filesystem (~2-4GB)
│   └── filesystem.manifest
├── boot/
│   └── grub/
│       └── grub.cfg
├── isolinux/
└── .disk/
```

#### Arch Linux ISO Structure:
```
/mnt/iso/
├── arch/
│   └── boot/
│       ├── x86_64/
│       │   ├── vmlinuz-linux     ← Kernel file (~12MB)
│       │   ├── archiso.img       ← Main initrd (~800MB)
│       │   └── initramfs-linux.img
│       ├── amd-ucode.img         ← AMD microcode (~3MB)
│       └── intel-ucode.img       ← Intel microcode (~4MB)
├── loader/
└── EFI/
```

#### Fedora ISO Structure:
```
/mnt/iso/
├── isolinux/
│   ├── vmlinuz          ← Kernel file (~12MB)
│   └── initrd.img       ← Initrd file (~80MB)
├── images/
│   ├── pxeboot/
│   │   ├── vmlinuz
│   │   └── initrd.img
│   └── install.img      ← Installation image
├── LiveOS/
│   └── squashfs.img     ← Live filesystem
└── EFI/
```

### **How to Identify Files:**

#### **1. File Size Indicators:**
```bash
# Kernel files are typically 5-15MB
find /mnt/iso -name "*vmlinuz*" -o -name "*linux*" | xargs ls -lh

# Initrd files are typically 20-500MB  
find /mnt/iso -name "*initrd*" -o -name "*archiso*" | xargs ls -lh
```

#### **2. File Type Check:**
```bash
# Kernel files show as "Linux kernel x86 boot executable"
file /mnt/iso/casper/vmlinuz

# Initrd files show as "gzip compressed data" or "ASCII cpio archive"
file /mnt/iso/casper/initrd
```

#### **3. Common Directory Patterns:**
- **`/casper/`** - Ubuntu derivatives (Ubuntu, Mint, elementary)
- **`/live/`** - Debian live systems
- **`/arch/boot/`** - Arch Linux and derivatives
- **`/isolinux/`** - Many traditional distros
- **`/boot/`** - Generic boot directory
- **`/images/pxeboot/`** - Red Hat family (Fedora, CentOS)

## Troubleshooting

### Common Issues:

#### 1. "No USB devices found"
- **Solution**: Ensure USB drive is connected and recognized by system
- **Check**: Run `lsblk` to verify USB detection

#### 2. "Missing dependencies: mkfs.exfat"
- **Solution**: Install exFAT tools for your distribution
- **Ubuntu/Debian**: `sudo apt install exfatprogs`
- **Arch Linux**: `sudo pacman -S exfatprogs`
- **Fedora/CentOS**: `sudo dnf install exfatprogs`

#### 3. "GRUB installation failed"
- **Solution**: Check if system has required GRUB packages
- **UEFI Systems**: Ensure `grub-efi-amd64-bin` is installed
- **BIOS Systems**: Ensure `grub-pc-bin` is installed

#### 4. "Permission denied" errors
- **Solution**: Script needs sudo privileges for disk operations
- **Check**: User must be in sudoers group

#### 5. ISO doesn't boot properly
- **Solution**: Check if ISO supports loopback booting
- **Alternative**: Some ISOs need to be extracted rather than loop-mounted

#### 6. exFAT filesystem not recognized
- **Old Systems**: Very old systems (pre-2010) might need exFAT drivers
- **Solution**: Update kernel or install exfat-fuse package
- **Alternative**: Use FAT32 for maximum compatibility (limited to 4GB files)

### exFAT-Specific Benefits:

#### ✅ **Large File Support:**
- Your 4.4GB Kubuntu ISO now copies without issues
- No file size limitations (unlike FAT32's 4GB limit)
- Better for modern large Linux distributions

#### ✅ **Performance:**
- Faster write speeds for large files
- Optimized for flash memory
- Reduced fragmentation

#### ✅ **Compatibility:**
- Works on Windows 7+, macOS 10.6.5+, Linux with exfat support
- Better cross-platform support than NTFS
- Native support in modern operating systems

### Recovery Options:

#### Restore USB to Normal State:
```bash
# Use fdisk to repartition
sudo fdisk /dev/sdX
# Delete all partitions (d)
# Create new partition (n)
# Write changes (w)

# Format as normal storage (choose your preferred filesystem)
sudo mkfs.ext4 /dev/sdX1    # For Linux
sudo mkfs.exfat /dev/sdX1   # For cross-platform use
sudo mkfs.vfat /dev/sdX1    # For maximum compatibility
```

#### Backup Configuration:
```bash
# Before making changes, backup your working config
cp /path/to/usb/boot/grub/grub.cfg ~/grub.cfg.backup
```

## Customization

### Changing Themes:
Edit `/boot/grub/grub.cfg` on the USB and replace theme references:
```bash
# Change from Stylish to Tela theme
sed -i 's/Stylish/Tela/g' /path/to/usb/boot/grub/grub.cfg
```

### Adding Custom ISOs:
1. Copy ISO to USB root
2. Add menu entry to `/boot/grub/grub.cfg`
3. Test boot functionality

### Boot Parameters:
Common parameters you might need to modify:
- `quiet splash` - Minimal boot output
- `nomodeset` - Disable graphics drivers
- `acpi=off` - Disable ACPI
- `mem=4G` - Limit RAM usage

## Performance Tips

- 💾 **USB Speed**: Use USB 3.0+ drives for better performance
- 📏 **USB Size**: 32GB+ recommended for multiple large ISOs
- ⚡ **SSD vs HDD**: USB drives with SSD are significantly faster
- 🎯 **ISO Selection**: Remove unused ISOs to free space and reduce boot menu clutter
- 📁 **exFAT Benefits**: Large files copy faster and perform better than with FAT32

## Support and Contribution

This project is based on the excellent work by [adi1090x/uGRUB](https://github.com/adi1090x/uGRUB). 

### Getting Help:
1. Check this guide's troubleshooting section
2. Verify all dependencies are installed (especially exfatprogs)
3. Test with known-working ISOs first
4. Check original uGRUB documentation for manual procedures

---

**⚠️ Important**: Always backup important data before running these scripts. The USB drive will be completely erased during the process.