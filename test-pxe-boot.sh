#!/bin/bash
cd /home/paalgyula/wspace/poc/pivirt-linux

# Boot QEMU with iPXE network boot (no direct kernel boot)
# iPXE will load from network, get DHCP, download boot.ipxe, and boot FCOS
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -boot order=n \
  -netdev user,id=net0,tftp=/home/paalgyula/wspace/poc/pivirt-linux/tftpboot,bootfile=boot.ipxe \
  -device virtio-net-pci,netdev=net0 \
  -serial mon:stdio \
  -nographic \
  -display none
