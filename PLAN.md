# PXE Bootable Fedora CoreOS Plan

Goal: Build a PXE-bootable Fedora CoreOS (FCOS) system with a custom virtualization stack (static QEMU + Go hypervisor) packaged as a systemd-sysext, testable via QEMU.

## Architecture
1. **Base OS**: Fedora CoreOS (FCOS) - uses rpm-ostree for atomic read-only root updates, native PXE boot support.
2. **Virt Stack**: Custom static QEMU + Go hypervisor packaged as a `systemd-sysext` SquashFS image, overlaid onto FCOS's read-only `/usr` at boot.
3. **PXE Boot**: Serves FCOS kernel, initramfs, and Ignition config over network; root filesystem delivered via FCOS's SquashFS image over HTTP.
4. **Testing**: Use QEMU with iPXE to simulate PXE boot of the FCOS setup.

---

## Step 1: Fetch FCOS PXE Artifacts
Download official FCOS PXE boot files from the [Fedora CoreOS release page](https://coreos.fedoraproject.org/releases/):
- `vmlinuz` (FCOS kernel)
- `initramfs.img` (FCOS initial ramdisk)
- `rootfs.img` (FCOS SquashFS root filesystem, served via HTTP)

```bash
FCOS_VERSION="38.20231020.3.0"
wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${FCOS_VERSION}/x86_64/fedora-coreos-${FCOS_VERSION}-live-kernel-x86_64 -O vmlinuz
wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${FCOS_VERSION}/x86_64/fedora-coreos-${FCOS_VERSION}-live-initramfs.x86_64.img -O initramfs.img
wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${FCOS_VERSION}/x86_64/fedora-coreos-${FCOS_VERSION}-live-rootfs.x86_64.squashfs -O rootfs.img
```

## Step 2: Build the System Extension (sysext) for Virt Stack
Package static QEMU and Go hypervisor into a sysext SquashFS image (same as original plan):

```bash
mkdir -p my-virt-stack/usr/bin
mkdir -p my-virt-stack/usr/lib/extension-release.d

cp /path/to/static/qemu-system-x86_64 my-virt-stack/usr/bin/
cp /path/to/myhypervisor my-virt-stack/usr/bin/

cat << 'EOF' > my-virt-stack/usr/lib/extension-release.d/extension-release.my-virt-stack
ID=fedora
VERSION_ID=38
EOF

mksquashfs my-virt-stack my-virt-stack.raw -comp zstd
```

## Step 3: Create FCOS Ignition Config
Ignition provisions FCOS at boot (including PXE). Configure it to deploy the sysext and enable services. Use `fcct` (Fedora CoreOS Config Transpiler):

```yaml
# fcos-config.fcc
variant: fcos
version: 1.4.0
storage:
  files:
    - path: /var/lib/extensions/my-virt-stack.raw
      contents:
        source: http://192.168.100.1/my-virt-stack.raw
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
```

Transpile to Ignition:
```bash
fcct -o fcos-config.ign fcos-config.fcc
```

## Step 4: Set Up PXE Boot Infrastructure
Use `dnsmasq` for combined DHCP + TFTP + HTTP:

```bash
sudo apt-get install dnsmasq
```

dnsmasq config (`/etc/dnsmasq.conf`):
```
interface=lo,virbr0
bind-interfaces
dhcp-range=192.168.100.10,192.168.100.50,12h
dhcp-boot=vmlinuz,,192.168.100.1
enable-tftp
tftp-root=/tftpboot
enable-http
listen-address=192.168.100.1
```

Set up TFTP directory:
```bash
sudo mkdir -p /tftpboot
sudo cp vmlinuz initramfs.img /tftpboot/
```

Serve Ignition config and sysext via HTTP:
```bash
python3 -m http.server 80 --bind 192.168.100.1
```

## Step 5: Test with QEMU
Simulate PXE boot using QEMU's iPXE support:

```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 2048 \
  -boot order=n \
  -netdev user,id=net0,net=192.168.100.0/24,tftp=/tftpboot,bootfile=vmlinuz \
  -device virtio-net-pci,netdev=net0 \
  -append "initrd=initramfs.img ignition.config.url=http://192.168.100.1/fcos-config.ign" \
  -serial mon:stdio \
  -nographic
```

## Step 6: Verify
After QEMU boots FCOS:
1. Check sysext: `systemd-sysext status`
2. Verify binaries: `which myhypervisor qemu-system-x86_64`
3. Check service: `systemctl status myhypervisor`

---

## Why This Works
* **FCOS Native PXE**: Official PXE support with Ignition provisioning
* **Immutable Base**: rpm-ostree for read-only root and enterprise patching
* **Sysext Integration**: Custom virt stack is a swappable SquashFS image
* **QEMU Testable**: Fully testable locally before real hardware deployment

## Next Steps
1. Download FCOS PXE artifacts
2. Build sysext with custom binaries
3. Generate Ignition config
4. Set up dnsmasq + HTTP server
5. Test QEMU PXE boot
6. Iterate on sysext/hypervisor
