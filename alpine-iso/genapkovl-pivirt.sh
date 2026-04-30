#!/bin/sh
# Generate apkovl overlay for pivirt live ISO
# This runs inside mkimage.sh to create the overlay

set -e

# Create temporary directory for overlay
tmp=$(mktemp -d)

# Create /etc/apk/world with packages to install in live system
mkdir -p "$tmp/etc/apk"
cat > "$tmp/etc/apk/world" <<EOF
alpine-base
openssh
qemu-openrc
bridge
chrony
pivirt
EOF

# Create setup-pivirt script in live system
mkdir -p "$tmp/usr/local/bin"
cat > "$tmp/usr/local/bin/setup-pivirt" <<'EOF'
#!/bin/sh
# pivirt interactive installer

echo "========================================"
echo "   pivirt Interactive Installer"
echo "========================================"
echo ""
echo "This will guide you through installing pivirt to disk."
echo ""

# Run setup-alpine for base system install
echo "Step 1: Basic system configuration..."
setup-alpine

echo ""
echo "Step 2: Installing pivirt..."
apk add pivirt

echo ""
echo "Step 3: Enabling services..."
rc-update add pivirt default 2>/dev/null || true
rc-update add qemu default 2>/dev/null || true

echo ""
echo "========================================"
echo "   Installation Complete!"
echo "   Rebooting into installed system..."
echo "========================================"
sleep 3
reboot
EOF
chmod +x "$tmp/usr/local/bin/setup-pivirt"

# Add pivirt to default runlevel if OpenRC service exists
mkdir -p "$tmp/etc/runlevels/default"
ln -sf /etc/init.d/pivirt "$tmp/etc/runlevels/default/pivirt" 2>/dev/null || true

# Create the apkovl tarball
tar czf "$OUTDIR/genapkovl-pivirt.tar.gz" -C "$tmp" .
rm -rf "$tmp"

echo "Generated genapkovl-pivirt.tar.gz"
