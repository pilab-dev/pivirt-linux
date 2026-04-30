#!/bin/bash
set -e

# Build customized FCOS ISO with embedded sysext
# Usage: bash build-iso.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR/iso-work"
ISO_NAME="pivirt-linux"
FCOS_STREAM="stable"

echo "=== pivirt-linux ISO Builder ==="
echo ""

# Check dependencies
for cmd in podman base64 python3; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is required but not installed."
        exit 1
    fi
done

# Clean work directory
if [ -d "$WORK_DIR" ]; then
    echo "Cleaning work directory..."
    rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"

# Step 1: Download FCOS ISO
echo "Step 1: Downloading FCOS ISO..."
podman run --security-opt label=disable --rm -v "$WORK_DIR":/data -w /data \
    quay.io/coreos/coreos-installer:release download -f iso -s "$FCOS_STREAM" -C /data

# Get downloaded ISO filename
ISO_FILE=$(ls "$WORK_DIR"/fedora-coreos-*-live.x86_64.iso 2>/dev/null | head -1)
if [ -z "$ISO_FILE" ]; then
    echo "Error: Failed to download FCOS ISO"
    exit 1
fi
echo "Downloaded: $(basename "$ISO_FILE")"

# Step 2: Create FCC config with embedded sysext as data URL
echo "Step 2: Creating FCC config with embedded sysext..."

# Generate FCC config with base64-encoded sysext using Python
python3 << PYEOF
import base64
import os

sysext_path = os.path.join("$SCRIPT_DIR", "my-virt-stack.raw")
output_path = os.path.join("$WORK_DIR", "fcos-config-iso.fcc")

# Read and encode the sysext
with open(sysext_path, 'rb') as f:
    sysext_b64 = base64.b64encode(f.read()).decode('utf-8')

# Build FCC content
fcc_content = f"""variant: fcos
version: 1.5.0
storage:
  files:
    - path: /var/lib/extensions/my-virt-stack.raw
      contents:
        source: data:application/octet-stream;base64,{sysext_b64}
      mode: 0644
systemd:
  units:
    - name: systemd-sysext.service
      enabled: true
    - name: myhypervisor.service
      contents: |
        [Unit]
        Description=Custom Go KVM Hypervisor
        After=network.target systemd-sysext.service
        Requires=systemd-sysext.service

        [Service]
        Type=simple
        ExecStart=/usr/bin/myhypervisor
        Restart=always
        LimitNOFILE=1048576

        [Install]
        WantedBy=multi-user.target
      enabled: true
"""

with open(output_path, 'w') as f:
    f.write(fcc_content)

print(f"FCC config created: {output_path}")
print(f"Sysext size: {len(sysext_b64)} bytes (base64)")
PYEOF

# Step 3: Transpile FCC to Ignition
echo "Step 3: Transpiling FCC to Ignition..."
podman run --security-opt label=disable --rm -v "$WORK_DIR":/data -w /data \
    quay.io/coreos/fcct:release fcos-config-iso.fcc -o fcos-config-iso.ign

# Step 4: Embed Ignition into ISO
echo "Step 4: Embedding Ignition config into ISO..."
podman run --security-opt label=disable --rm -v "$WORK_DIR":/data -w /data \
    quay.io/coreos/coreos-installer:release iso ignition embed \
    -i /data/fcos-config-iso.ign -f \
    "$(basename "$ISO_FILE")"

# Step 5: Move final ISO to project root
echo "Step 5: Finalizing..."
mv "$ISO_FILE" "$SCRIPT_DIR/${ISO_NAME}.iso"

# Cleanup work dir
rm -rf "$WORK_DIR"

echo ""
echo "=== Build Complete ==="
echo "ISO created: $SCRIPT_DIR/${ISO_NAME}.iso"
echo "ISO size: $(du -h "$SCRIPT_DIR/${ISO_NAME}.iso" | cut -f1)"
echo ""
echo "To test with QEMU:"
echo "  qemu-system-x86_64 -enable-kvm -m 4096 -cdrom ${ISO_NAME}.iso -boot d -serial mon:stdio -nographic"
echo ""
echo "To install to disk from live environment:"
echo "  1. Boot from ISO"
echo "  2. Run: sudo coreos-installer install /dev/sda --ignition /path/to/fcos-config.ign"
