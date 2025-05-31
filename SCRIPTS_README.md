# Interactive Multiboot USB Scripts

Automated scripts to create and manage multiboot USB drives with GRUB2 bootloader.

## Quick Usage

### 🚀 Create Multiboot USB
```bash
./prepare_multiboot_usb.sh
```

### 🔧 Manage ISOs  
```bash
./manage_isos.sh
```

## 📁 Files Overview

| File | Purpose |
|------|---------|
| `prepare_multiboot_usb.sh` | Main script - creates multiboot USB from scratch |
| `manage_isos.sh` | Utility script - manage ISOs on existing multiboot USB |
| `MULTIBOOT_GUIDE.md` | Comprehensive documentation and troubleshooting |
| `isos/` | Directory for your ISO files |
| `grub/` | GRUB configuration and themes |

## ⚡ Quick Start

1. **Place ISOs** in the `isos/` directory
2. **Run main script**: `./prepare_multiboot_usb.sh`
3. **Follow prompts** to select USB and confirm
4. **Boot from USB** and enjoy your multiboot system!

## ✨ Features

- ✅ **Automatic USB detection** and selection
- ✅ **UEFI/BIOS auto-configuration**
- ✅ **exFAT filesystem** (no 4GB file size limit)
- ✅ **Safety confirmations** before data destruction
- ✅ **Progress indicators** and error handling
- ✅ **Multiple themes** included (Stylish, Tela, Slaze, Vimix)
- ✅ **Auto-menu generation** for common distros
- ✅ **ISO management** utilities

## 🎯 Supported Distributions

Auto-detected distributions (menu entries generated automatically):
- Ubuntu, Kubuntu, Xubuntu
- Linux Mint  
- Arch Linux
- Manual entries available for many others

## ⚠️ Important Notes

- **USB will be completely erased** - backup important data first
- **Requires sudo privileges** for disk operations
- **8GB+ USB recommended** for multiple ISOs
- **Internet connection** may be needed for dependency installation

## 📖 Full Documentation

See `MULTIBOOT_GUIDE.md` for:
- Detailed step-by-step instructions
- Troubleshooting guide
- Advanced configuration options
- Manual menu entry creation
- Performance optimization tips

## 🛠️ Dependencies

Required tools (auto-checked):
- `fdisk`, `mkfs.exfat`, `grub-install`
- `lsblk`, `blkid`, `mount`, `umount`

Install on Ubuntu/Debian:
```bash
sudo apt install fdisk exfatprogs grub2-common grub-pc-bin grub-efi-amd64-bin util-linux
```

## 🤝 Credits

Based on the excellent [uGRUB project](https://github.com/adi1090x/uGRUB) by adi1090x.

---

**Ready to create your multiboot USB? Run `./prepare_multiboot_usb.sh` to get started!** 🚀 