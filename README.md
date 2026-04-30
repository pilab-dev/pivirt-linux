# PXE-Bootable FCOS with Custom Virt Stack: Complete Guide

Based on the implementation we just completed, here's a full guide to reproducing the setup, managing VMs, and creating Ignition configs.

---

## Prerequisites

Ensure these tools are available:

```bash
# Check/install required packages
sudo apt-get install -y podman go qemu-system-x86_64 python3 dnsmasq
```

---

## Architecture Overview

- **Base OS**: Fedora CoreOS (FCOS) - immutable, rpm-ostree based, native PXE support
- **Boot Method**: iPXE fetches kernel/initrd via TFTP, rootfs + Ignition + sysext via HTTP
- **Custom Stack**: QEMU + Go hypervisor packaged as a `systemd-sysext` SquashFS image overlaid on FCOS's `/usr`
- **Provisioning**: Ignition (declarative config) runs at first boot to deploy sysext, enable services

---

## Step 1: Fetch FCOS PXE Artifacts

We used `coreos-installer` (via Podman) to download official FCOS live PXE files:

```bash
mkdir -p /path/to/pivirt-linux/{tftpboot,http-root,my-virt-stack/usr/bin,my-virt-stack/usr/lib/extension-release.d}
cd /path/to/pivirt-linux

# Download FCOS PXE artifacts (kernel, initrd, rootfs) to tftpboot/http-root
podman run --security-opt label=disable --rm -v /path/to/pivirt-linux/tftpboot:/data/tftpboot -w /data/tftpboot \
  quay.io/coreos/coreos-installer:release download -f pxe -C /data/tftpboot

# Rename files to simple names
cd tftpboot
mv fedora-coreos-*-live-kernel.x86_64 vmlinuz
mv fedora-coreos-*-live-initramfs.x86_64.img initramfs.img
mv fedora-coreos-*-live-rootfs.x86_64.img ../http-root/rootfs.img
```

---

## Step 2: Build Custom Virt Stack Sysext

Package static QEMU + Go hypervisor into a systemd-sysext (SquashFS image):

### 2a. Create Go Hypervisor (Example)

```go
// my-virt-stack/myhypervisor.go
package main

import (
    "log"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"
)

func main() {
    log.Printf("MyHypervisor v0.1 starting...")
    go func() {
        http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("OK\n")) })
        log.Fatal(http.ListenAndServe(":8080", nil))
    }()
    sig := make(chan os.Signal, 1)
    signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
    <-sig
    log.Printf("Shutting down...")
}
```

### 2b. Compile Binaries

```bash
cd /path/to/pivirt-linux/my-virt-stack
go build -o usr/bin/myhypervisor ./myhypervisor.go
cp /usr/bin/qemu-system-x86_64 usr/bin/
```

### 2c. Create Sysext Metadata

**Critical**: `VERSION_ID` must match the FCOS major version (we used FCOS 43, so VERSION_ID=43):

```bash
cat << EOF > usr/lib/extension-release.d/extension-release.my-virt-stack
ID=fedora
VERSION_ID=43
EOF
```

### 2d. Build SquashFS Image

```bash
cd /path/to/pivirt-linux
mksquashfs my-virt-stack my-virt-stack.raw -comp zstd
cp my-virt-stack.raw http-root/  # Serve via HTTP
```

---

## Step 3: Create Ignition Configs

FCOS uses **Ignition** (JSON) for provisioning, but we write **FCC (Fedora CoreOS Config)** (YAML) and transpile it with `fcct`.

### 3a. Write FCC Config

Create `fcos-config.fcc`:

```yaml
variant: fcos
version: 1.4.0
storage:
  files:
    - path: /var/lib/extensions/my-virt-stack.raw
      contents:
        source: http://10.0.2.2:8888/my-virt-stack.raw  # QEMU user-mode host IP
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

### 3b. Transpile to Ignition

Use `fcct` via Podman (no local install needed):

```bash
podman run --security-opt label=disable --rm -v /path/to/pivirt-linux:/data:z -w /data \
  quay.io/coreos/fcct:release fcos-config.fcc -o fcos-config.ign
cp fcos-config.ign http-root/
```

---

## Step 4: Set Up iPXE Boot

iPXE fetches a boot script that loads the kernel, initrd, and passes boot arguments.

### 4a. Create iPXE Boot Script

`http-root/boot.ipxe` (also copy to `tftpboot/` for TFTP):

```
#!ipxe
set base-url http://10.0.2.2:8888
kernel ${base-url}/vmlinuz initrd=initramfs.img console=ttyS0 coreos.live.rootfs_url=${base-url}/rootfs.img ignition.firstboot ignition.platform.id=qemu ignition.config.url=${base-url}/fcos-config.ign
initrd ${base-url}/initramfs.img
boot
```

```bash
cp http-root/boot.ipxe tftpboot/
```

### 4b. Start HTTP Server

Serve files from `http-root` (port 8888 to avoid conflicts):

```bash
cd /path/to/pivirt-linux/http-root
python3 -m http.server 8888 --bind 0.0.0.0 &
```

---

## Step 5: Test iPXE Boot with QEMU

Create a test script `test-pxe-boot.sh`:

```bash
#!/bin/bash
cd /path/to/pivirt-linux

qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -boot order=n \
  -netdev user,id=net0,tftp=/path/to/pivirt-linux/tftpboot,bootfile=boot.ipxe \
  -device virtio-net-pci,netdev=net0 \
  -serial mon:stdio \
  -nographic \
  -display none
```

```bash
chmod +x test-pxe-boot.sh
bash test-pxe-boot.sh  # Ctrl+A X to exit QEMU
```

---

## How to Start a VM

### Start the FCOS Host VM (via iPXE)

Run the test script above: this boots the FCOS host with your custom virt stack.

### Start a Guest VM (using custom QEMU from sysext)

Once FCOS is booted, use the QEMU binary deployed via sysext (`/usr/bin/qemu-system-x86_64`):

```bash
# Example: Boot a guest FCOS VM via PXE
/usr/bin/qemu-system-x86_64 \
  -enable-kvm \
  -m 2048 \
  -boot order=n \
  -netdev user,id=net0,tftp=/var/lib/tftpboot,bootfile=boot.ipxe \
  -device virtio-net-pci,netdev=net0 \
  -drive file=/var/lib/guest-vm.qcow2,format=qcow2 \
  -serial mon:stdio \
  -nographic
```

---

## How to Configure a VM

### Configure the FCOS Host

Modify the FCC config (`fcos-config.fcc`) to add:
- **Users**: `passwd.users` section
- **Network**: `networking` section
- **Additional Files**: More entries under `storage.files`
- **Services**: More `systemd.units` entries

Regenerate Ignition and reboot (Ignition runs at first boot only; for existing systems, use `rpm-ostree` or edit files directly on the mutable `/var` partition).

### Configure Guest VMs

- For FCOS guests: Create a separate Ignition config and pass it via `ignition.config.url` kernel argument
- For other Linux guests: Use cloud-init or traditional config management

---

## How to Create Ignition Files

Ignition files are JSON, but we use the human-friendly FCC YAML format:

1. **Write FCC**: Use the syntax in Step 3a (see [FCC docs](https://docs.fedoraproject.org/en-US/fedora-coreos/fcct-config/))
2. **Transpile**: Use `fcct` (via Podman) as in Step 3b
3. **Validate**: Check syntax with `fcct --strict fcos-config.fcc`
4. **Serve**: Place the `.ign` file in your HTTP root directory

---

## Troubleshooting (Based on Our Experience)

| Issue | Solution |
|-------|----------|
| iPXE 404 Not Found for vmlinuz/initramfs | Copy files to `http-root/` (iPXE fetches via HTTP, not just TFTP) |
| dnsmasq permission denied for tftpboot | Fix parent directory permissions: `chmod o+x /home /home/user /home/user/wspace` etc. |
| HTTP server port conflict | Use a high port (8888 instead of 80/8080) and update FCC + boot.ipxe |
| Sysext not loading | Ensure `extension-release.my-virt-stack` has correct `ID=fedora` and `VERSION_ID` matching FCOS |

---

## File Reference

```
pivirt-linux/
├── tftpboot/           # TFTP-served files (vmlinuz, initramfs.img, boot.ipxe)
├── http-root/           # HTTP-served files (rootfs.img, my-virt-stack.raw, fcos-config.ign, boot.ipxe)
├── my-virt-stack/       # Sysext build directory
│   ├── usr/bin/        # Binaries (qemu-system-x86_64, myhypervisor)
│   └── usr/lib/extension-release.d/  # Sysext metadata
├── my-virt-stack.raw   # Compiled sysext SquashFS image
├── fcos-config.fcc      # FCC config (YAML)
├── fcos-config.ign      # Ignition config (JSON)
├── boot.ipxe            # iPXE boot script
└── test-pxe-boot.sh     # QEMU test script
```
