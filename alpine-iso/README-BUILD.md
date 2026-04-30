# pivirt Alpine ISO - Build Documentation

## Overview

The pivirt Alpine ISO is a customized Alpine Linux image that provides an interactive installer for pivirt. It is based on Alpine extended and includes the pivirt daemon for offline installation.

## Prerequisites

### Required Tools

The following tools must be installed on the build system:

- `wget` - Download Alpine base ISO
- `xorriso` - Create bootable ISO images
- `7z` (p7zip) - Extract ISO contents
- `chmod`, `cp`, `mv` - Standard Unix utilities

### Installation on Alpine

```bash
apk add wget xorriso p7zip
```

### Installation on Debian/Ubuntu

```bash
apt install wget xorriso p7zip-full
```

### Installation on Fedora/RHEL

```bash
yum install wget xorriso p7zip p7zip-plugins
```

## Building the ISO

### Quick Build

```bash
cd alpine-iso
bash build-alpine-iso.sh
```

This will:
1. Download Alpine extended ISO (default: 3.22.4)
2. Extract the ISO contents
3. Add pivirt files (setup-pivirt script, myhypervisor binary)
4. Rebuild the ISO

### Custom Alpine Version

```bash
bash build-alpine-iso.sh 3.21.0
```

### Output

The built ISO will be at: `pivirt-alpine.iso` (in project root)

## Build Script Details

The build script (`alpine-iso/build-alpine-iso.sh`) performs these steps:

1. **Download**: Fetches Alpine extended ISO from the official mirror
2. **Extract**: Uses `7z` to extract ISO contents to a working directory
3. **Add pivirt files**: 
   - Copies `setup-pivirt` script to ISO root
   - Copies `myhypervisor` binary from `my-virt-stack/usr/bin/`
   - Creates `pivirt/README` with instructions
4. **Rebuild**: Uses `xorriso` to create a new bootable ISO with proper El Torito boot catalog

## ISO Contents

```
pivirt-alpine.iso
├── boot/
│   ├── syslinux/      # Boot loader files
│   ├── vmlinuz-lts    # Linux kernel
│   └── initramfs-lts  # Initial ramdisk
├── apks/              # Alpine packages (from extended ISO)
├── pivirt/
│   ├── myhypervisor   # pivirt daemon binary
│   └── README        # Instructions
├── setup-pivirt       # Interactive installer script
└── ...               # Other Alpine files
```

## Using the ISO

### Boot and Install

1. Write ISO to USB or mount in VM:
   ```bash
   dd if=pivirt-alpine.iso of=/dev/sdX bs=4M status=progress
   ```

2. Boot from the media

3. Login as `root` (no password)

4. Run the interactive installer:
   ```bash
   setup-pivirt
   ```

### Test with QEMU

```bash
qemu-system-x86_64 -enable-kvm -m 2048 -cdrom pivirt-alpine.iso -boot d
```

## Customizing the ISO

### Adding More Packages

To include additional APK packages in the ISO:

1. Download the APK files
2. Copy them to `work/iso-build/apks/x86_64/`
3. Rebuild the ISO

### Modifying the Installer

Edit `alpine-iso/setup-pivirt` to change the installation behavior.

## Troubleshooting

### "Permission denied" Errors

If you see permission errors during cleanup:

```bash
chmod -R u+w alpine-iso/work 2>/dev/null || true
rm -rf alpine-iso/work
```

### ISO Won't Boot

Ensure the ISO was built with proper boot catalog:
- Check that `boot/syslinux/isohdpfx.bin` exists in the source ISO
- Verify `xorriso` command includes `-isohybrid-mbr` option

### Missing Dependencies

The build script checks for required tools at startup. Install any missing dependencies as shown in the Prerequisites section.

## File Structure

```
pivirt-linux/
├── alpine-iso/
│   ├── build-alpine-iso.sh    # Main build script
│   ├── setup-pivirt           # Installer script (copied to ISO)
│   ├── mkimg.pivirt.sh        # Alpine profile (alternative build method)
│   └── genapkovl-pivirt.sh   # Overlay script (alternative build method)
├── packages/
│   └── pivirt/
│       ├── APKBUILD           # APK package definition
│       └── pivirt.initd       # OpenRC service file
├── my-virt-stack/
│   └── usr/bin/
│       └── myhypervisor      # pivirt daemon binary
└── pivirt-alpine.iso         # Built ISO (output)
```

## Alternative: Building with mkimage.sh

For a more "Alpine-native" build, use `mkimage.sh` from alpine/aports:

```bash
git clone --depth 1 --branch v3.22 https://gitlab.alpinelinux.org/alpine/aports.git
cd aports/scripts
sh mkimage.sh --profile pivirt --tag v3.22 --outdir /path/to/output
```

This requires a proper Alpine build environment with `apk` and `abuild` tools.
