#!/bin/bash
set -e

# Build pivirt Alpine ISO by remastering alpine-extended
# Usage: bash build-alpine-iso.sh [ALPINE_VERSION]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR/work"
OUT_DIR="$SCRIPT_DIR/output"
ALPINE_VER="${1:-3.22.4}"
ISO_NAME="pivirt-alpine-${ALPINE_VER}-x86_64.iso"
DOWNLOAD_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER%.*}/releases/x86_64/alpine-extended-${ALPINE_VER}-x86_64.iso"

echo "=== pivirt Alpine ISO Builder ==="
echo "Alpine version: $ALPINE_VER"
echo ""

# Check dependencies
for cmd in wget xorriso 7z; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is required but not installed."
        echo "Install with: apk add $cmd (or apt/yum equivalent)"
        exit 1
    fi
done

# Clean work directory
rm -rf "$WORK_DIR" 2>/dev/null || true
mkdir -p "$WORK_DIR" "$OUT_DIR" "$WORK_DIR/iso-build"

# Step1: Download Alpine extended ISO
echo "Step 1: Downloading Alpine extended ISO..."
wget -q --show-progress -O "$WORK_DIR/alpine-extended.iso" "$DOWNLOAD_URL"
echo "Download complete: $(du -h "$WORK_DIR/alpine-extended.iso" | cut -f1)"

# Step2: Extract ISO contents using 7z (no mount needed)
echo "Step 2: Extracting ISO..."
cd "$WORK_DIR/iso-build"
7z x "$WORK_DIR/alpine-extended.iso" -o"$WORK_DIR/iso-build" 2>/dev/null || \
    xorriso -osirrox on -indev "$WORK_DIR/alpine-extended.iso" -extract / "$WORK_DIR/iso-build" 2>/dev/null
chmod -R u+w "$WORK_DIR/iso-build" 2>/dev/null || true
echo "Extraction complete."

# Step3: Add pivirt files to ISO
echo "Step 3: Adding pivirt files..."

# Copy setup-pivirt script to ISO root
cp "$SCRIPT_DIR/setup-pivirt" "$WORK_DIR/iso-build/"
chmod +x "$WORK_DIR/iso-build/setup-pivirt"

# Create pivirt directory with additional files
mkdir -p "$WORK_DIR/iso-build/pivirt"

# If myhypervisor exists, include it
if [ -f "$SCRIPT_DIR/../my-virt-stack/usr/bin/myhypervisor" ]; then
    cp "$SCRIPT_DIR/../my-virt-stack/usr/bin/myhypervisor" "$WORK_DIR/iso-build/pivirt/"
    chmod +x "$WORK_DIR/iso-build/pivirt/myhypervisor"
    echo "  Added: myhypervisor binary"
fi

# Create a README in the ISO
cat > "$WORK_DIR/iso-build/pivirt/README" << 'EOF'
pivirt - PXE-bootable Virtualization Linux

To install pivirt:
1. Boot from this ISO
2. Login as root (no password)
3. Run: setup-pivirt

For more info: https://github.com/yourorg/pivirt-linux
EOF

# Step4: Rebuild ISO
echo "Step 4: Building new ISO..."
cd "$WORK_DIR"
xorriso -as mkisofs \
    -o "$OUT_DIR/$ISO_NAME" \
    -isohybrid-mbr "$WORK_DIR/iso-build/boot/syslinux/isohdpfx.bin" \
    -c boot/syslinux/boot.cat \
    -b boot/syslinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -V "pivirt-alpine" \
    -input-charset utf-8 \
    "$WORK_DIR/iso-build" 2>/dev/null

# Step5: Finalize
mv "$OUT_DIR/$ISO_NAME" "$SCRIPT_DIR/../pivirt-alpine.iso"
rm -rf "$WORK_DIR" "$OUT_DIR"

echo ""
echo "=== Build Complete ==="
echo "ISO created: $SCRIPT_DIR/../pivirt-alpine.iso"
echo "ISO size: $(du -h "$SCRIPT_DIR/../pivirt-alpine.iso" | cut -f1)"
echo ""
echo "To test with QEMU:"
echo "  qemu-system-x86_64 -enable-kvm -m 2048 -cdrom pivirt-alpine.iso -boot d"
echo ""
echo "To install interactively:"
echo "  1. Boot from ISO"
echo "  2. Login as root (no password)"
echo "  3. Run: setup-pivirt"
