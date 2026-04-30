# 🚀 PXE-Bootable FCOS with Custom Virt Stack

![Fedora CoreOS](https://img.shields.io/badge/Fedora%20CoreOS-43.20260413.3.2-294172?logo=fedora&logoColor=white)
![QEMU](https://img.shields.io/badge/QEMU-10.1.0-ff6600?logo=qemu)
![Go](https://img.shields.io/badge/Go-1.24.4-00ADD8?logo=go)
![License](https://img.shields.io/badge/license-MIT-blue)

A complete implementation of a **PXE-bootable Fedora CoreOS (FCOS)** system with a custom virtualization stack (static QEMU + Go hypervisor) packaged as a **systemd-sysext** extension. Testable via QEMU with full iPXE support.

---

## 📋 Table of Contents

- [🏗️ Architecture](#️-architecture)
- [📦 Prerequisites](#-prerequisites)
- [🚀 Quick Start](#-quick-start)
- [📥 Step 1: Fetch FCOS PXE Artifacts](#-step-1-fetch-fcos-pxe-artifacts)
- [🔧 Step 2: Build Custom Virt Stack Sysext](#-step-2-build-custom-virt-stack-sysext)
- [⚙️ Step 3: Create Ignition Configs](#️-step-3-create-ignition-configs)
- [🌐 Step 4: Set Up iPXE Boot](#-step-4-set-up-ipxe-boot)
- [🖥️ Step 5: Test iPXE Boot with QEMU](#️-step-5-test-ipxe-boot-with-qemu)
- [▶️ How to Start a VM](#️-how-to-start-a-vm)
- [🔧 How to Configure a VM](#️-how-to-configure-a-vm)
- [📝 How to Create Ignition Files](#-how-to-create-ignition-files)
- [🛠️ Troubleshooting](#️-troubleshooting)
- [📁 File Reference](#-file-reference)

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│              PXE Boot Chain                       │
├─────────────────────────────────────────────────────┤
│  iPXE ROM → TFTP (boot.ipxe) → HTTP Server      │
│     ↓                                           │
│  kernel + initrd → FCOS Live Boot                │
│     ↓                                           │
│  Ignition (fcos-config.ign) → Provision FCOS     │
│     ↓                                           │
│  systemd-sysext → Load QEMU + Hypervisor       │
└─────────────────────────────────────────────────────┘
```

| Component | Description |
|-----------|-------------|
| **Base OS** | Fedora CoreOS (FCOS) - immutable, rpm-ostree based |
| **Boot Method** | iPXE fetches kernel/initrd via TFTP, rootfs + Ignition + sysext via HTTP |
| **Custom Stack** | QEMU + Go hypervisor packaged as `systemd-sysext` SquashFS image |
| **Provisioning** | Ignition (declarative config) runs at first boot |

---

## 📦 Prerequisites

Ensure these tools are available:

```bash
# Check/install required packages
sudo apt-get install -y podman go qemu-system-x86_64 python3 dnsmasq git-lfs
```

| Tool | Purpose |
|------|---------|
| `podman` | Run containers (coreos-installer, fcct) |
| `go` | Compile the custom Go hypervisor |
| `qemu-system-x86_64` | Test VM and guest virtualization |
| `python3` | HTTP server for PXE boot files |
| `dnsmasq` | DHCP/TFTP server (optional, QEMU user-mode works) |
| `git-lfs` | Track large files (rootfs.img, etc.) |

---

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/pilab-dev/pivirt-linux.git
cd pivirt-linux

# Start HTTP server (serves PXE files)
cd http-root && python3 -m http.server 8888 &

# Test iPXE boot
bash test-pxe-boot.sh
# Press Ctrl+A, then X to exit QEMU
```

---

## 📥 Step 1: Fetch FCOS PXE Artifacts

Download official FCOS live PXE files using `coreos-installer`:

```bash
mkdir -p {tftpboot,http-root,my-virt-stack/usr/bin,my-virt-stack/usr/lib/extension-release.d}
cd pivirt-linux

# Download FCOS PXE artifacts
podman run --security-opt label=disable --rm -v $(pwd)/tftpboot:/data/tftpboot -w /data/tftpboot \
  quay.io/coreos/coreos-installer:release download -f pxe -C /data/tftpboot

# Rename to simple names
cd tftpboot
mv fedora-coreos-*-live-kernel.x86_64 vmlinuz
mv fedora-coreos-*-live-initramfs.x86_64.img initramfs.img
mv fedora-coreos-*-live-rootfs.x86_64.img ../http-root/rootfs.img
```

**Downloaded Files:**
- ✅ `vmlinuz` - FCOS kernel (~18M)
- ✅ `initramfs.img` - Initial ramdisk (~121M)
- ✅ `rootfs.img` - SquashFS root filesystem (~850M)

---

## 🔧 Step 2: Build Custom Virt Stack Sysext

Package QEMU and your Go hypervisor into a systemd-sysext SquashFS image.

### 2a. Create Go Hypervisor

```go
// my-virt-stack/myhypervisor.go
package main

import (
    "log"
    "net/http"
    "os"
    "os/signal"
    "syscall"
)

func main() {
    log.Println("MyHypervisor v0.1 starting...")
    
    go func() {
        http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
            w.Write([]byte("OK\n"))
        })
        log.Fatal(http.ListenAndServe(":8080", nil))
    }()
    
    sig := make(chan os.Signal, 1)
    signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
    <-sig
    log.Println("Shutting down...")
}
```

### 2b. Compile Binaries

```bash
cd my-virt-stack
go build -o usr/bin/myhypervisor ./myhypervisor.go
cp /usr/bin/qemu-system-x86_64 usr/bin/
```

### 2c. Create Sysext Metadata

> **⚠️ Critical:** `VERSION_ID` must match the FCOS major version!

```bash
cat << EOF > usr/lib/extension-release.d/extension-release.my-virt-stack
ID=fedora
VERSION_ID=43
EOF
```

### 2d. Build SquashFS Image

```bash
cd ..
mksquashfs my-virt-stack my-virt-stack.raw -comp zstd
cp my-virt-stack.raw http-root/
```

---

## ⚙️ Step 3: Create Ignition Configs

FCOS uses **Ignition** (JSON) for provisioning. We write **FCC (Fedora CoreOS Config)** in YAML and transpile with `fcct`.

### 3a. Write FCC Config

Create `fcos-config.fcc`:

```yaml
variant: fcos
version: 1.4.0
storage:
  files:
    - path: /var/lib/extensions/my-virt-stack.raw
      contents:
        source: http://10.0.2.2:8888/my-virt-stack.raw
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

```bash
podman run --security-opt label=disable --rm -v $(pwd):/data:z -w /data \
  quay.io/coreos/fcct:release fcos-config.fcc -o fcos-config.ign
cp fcos-config.ign http-root/
```

---

## 🌐 Step 4: Set Up iPXE Boot

### 4a. Create iPXE Boot Script

`http-root/boot.ipxe` (also copy to `tftpboot/`):

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

```bash
cd http-root
python3 -m http.server 8888 --bind 0.0.0.0 &
```

---

## 🖥️ Step 5: Test iPXE Boot with QEMU

Create `test-pxe-boot.sh`:

```bash
#!/bin/bash
cd /home/paalgyula/wspace/poc/pivirt-linux

qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -boot order=n \
  -netdev user,id=net0,tftp=/home/paalgyula/wspace/poc/pivirt-linux/tftpboot,bootfile=boot.ipxe \
  -device virtio-net-pci,netdev=net0 \
  -serial mon:stdio \
  -nographic \
  -display none
```

```bash
chmod +x test-pxe-boot.sh
bash test-pxe-boot.sh
# Press Ctrl+A, then X to exit QEMU
```

---

## ▶️ How to Start a VM

### Start the FCOS Host VM (via iPXE)

```bash
bash test-pxe-boot.sh
```

### Start a Guest VM (using custom QEMU from sysext)

Once FCOS is booted, use the QEMU binary deployed via sysext:

```bash
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

## 🔧 How to Configure a VM

### Configure the FCOS Host

Modify `fcos-config.fcc` to add:
- **Users**: `passwd.users` section
- **Network**: `networking` section
- **Additional Files**: More entries under `storage.files`
- **Services**: More `systemd.units` entries

Regenerate Ignition and reboot.

### Configure Guest VMs

| Guest OS | Configuration Method |
|----------|---------------------|
| FCOS | Create separate Ignition config, pass via `ignition.config.url` |
| Other Linux | Use cloud-init or traditional config management |

---

## 📝 How to Create Ignition Files

1. **Write FCC** - Use YAML syntax (see [FCC docs](https://docs.fedoraproject.org/en-US/fedora-coreos/fcct-config/))
2. **Transpile** - Use `fcct` container: `podman run ... quay.io/coreos/fcct:release`
3. **Validate** - `fcct --strict fcos-config.fcc`
4. **Serve** - Place `.ign` file in HTTP root directory

---

## 🛠️ Troubleshooting

| Issue | Solution |
|-------|----------|
| 🚫 iPXE 404 Not Found | Copy files to `http-root/` (iPXE fetches via HTTP, not just TFTP) |
| 🔒 dnsmasq permission denied | Fix permissions: `chmod o+x /home /home/user /home/user/wspace` |
| 🔌 HTTP server port conflict | Use high port (8888) and update FCC + boot.ipxe |
| ⚠️ Sysext not loading | Ensure `VERSION_ID` in extension-release matches FCOS version |
| 🐢 Slow boot | Ensure `rootfs.img` is accessible via HTTP, check network |

---

## 📁 File Reference

```
pivirt-linux/
├── 📄 README.md              # This file
├── 📄 PLAN.md               # Original implementation plan
├── 🔧 test-pxe-boot.sh      # QEMU test script
├── 📝 fcos-config.fcc       # FCC config (YAML)
├── 📋 fcos-config.ign       # Ignition config (JSON)
├── 🌐 boot.ipxe             # iPXE boot script
├── ⚙️ dnsmasq.conf          # dnsmasq configuration
│
├── 📁 tftpboot/             # TFTP-served files
│   ├── 🐧 vmlinuz          # FCOS kernel
│   ├── 💾 initramfs.img    # Initial ramdisk
│   └── 🌐 boot.ipxe       # iPXE script (copy)
│
├── 📁 http-root/            # HTTP-served files
│   ├── 🐧 vmlinuz          # FCOS kernel (LFS)
│   ├── 💾 initramfs.img    # Initial ramdisk (LFS)
│   ├── 📦 rootfs.img       # Root filesystem (LFS)
│   ├── 📦 my-virt-stack.raw # Sysext image (LFS)
│   ├── 📋 fcos-config.ign  # Ignition config
│   └── 🌐 boot.ipxe       # iPXE script
│
├── 📁 my-virt-stack/        # Sysext build directory
│   ├── 📁 usr/bin/        # Binaries
│   │   ├── 🔧 qemu-system-x86_64
│   │   └── 🐹 myhypervisor
│   └── 📁 usr/lib/extension-release.d/
│       └── 📄 extension-release.my-virt-stack
│
└── 📦 my-virt-stack.raw    # Compiled sysext (LFS)
```

> **Note:** Large files are tracked via [Git LFS](https://git-lfs.github.com/)

---

## 📊 Stats

![GitHub repo size](https://img.shields.io/github/repo-size/pilab-dev/pivirt-linux)
![GitHub last commit](https://img.shields.io/github/last-commit/pilab-dev/pivirt-linux)
![GitHub](https://img.shields.io/github/license/pilab-dev/pivirt-linux)

---

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

---

<div align="center">

### Made with ❤️ by Progressive Innovation LAB

[![GitHub](https://img.shields.io/badge/GitHub-pilab--dev-181717?logo=github)](https://github.com/pilab-dev)
[![Website](https://img.shields.io/badge/Website-pilab--dev.org-00ADD8?logo=google-chrome)](https://pilab-dev.org)

</div>
