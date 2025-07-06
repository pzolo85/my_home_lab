# Hardware

- [TRIGKEY S6 Mini PC 8 Core 16 Thread Mini Computer Desktop PC Ryzen 7 Pro 6800U（Up to 4.7GHz） 32G DDR4+1TB NVME SSD Micro PC | 12Core 2600MHz HD graphics | WiFi-6 | BT 5.2 | HDMI+DP | Type-C | WOL](https://www.amazon.co.uk/dp/B0C3CR3XQQ)

# Software 

- Debian 12 
```
$ uname -a ; cat /etc/os-release 
Linux trigkey 6.1.0-37-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.1.140-1 (2025-05-22) x86_64 GNU/Linux
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
NAME="Debian GNU/Linux"
VERSION_ID="12"
VERSION="12 (bookworm)"
VERSION_CODENAME=bookworm
ID=debian
HOME_URL="https://www.debian.org/"
SUPPORT_URL="https://www.debian.org/support"
BUG_REPORT_URL="https://bugs.debian.org/"
```

# Installation 

## Virtualization 
- KVM/QEMU & Libvirt
```
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager cloud-image-utils
```
- Add user to group 
```
sudo usermod -aG libvirt $(whoami)
sudo usermod -aG kvm $(whoami)
```
- Create bridge with DHCP (using the ISP's dhcpd) - Optional step, if we want to see the VM with an IP address assigned by the ISP at the same level as the hypervisor 
```
cat /etc/network/interfaces
source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

## The primary network interface
## original setup
# allow-hotplug enp1s0
# iface enp1s0 inet dhcp

auto enp1s0
iface enp1s0 inet manual 

# bridge for KVM 
auto br0
iface br0 inet dhcp
    bridge_ports enp1s0    # Attach physical NIC
    bridge_stp off
    bridge_fd 0

```
- reboot 
- Download [debian 12 cloud image](https://cloud.debian.org/images/cloud/) the [generic](https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2) image includes `could-init` support 
```
$ curl -LO https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
```


# VM Deployment 

## Generic steps 
- create cloud init disk 
```
cat config/cloud-init/k8s-master-01 
#cloud-config
hostname: k8s-master-01
users:
  - name: debian
    ssh-authorized-keys:
      - ssh-rsa AA..
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
package_update: true
packages:
  - qemu-guest-agent
runcmd:
  - echo "Hello from Cloud-Init!" > /etc/motd
```
- create iso 
```
cloud-localds /tmp/cloud-init-master-01.iso config/cloud-init/k8s-master-01
```
- enable autos-start after VM starts 
```
sudo virsh autostart k8s-master-01
```
- access the VM using ssh, because it only accepts public keys 
```
$ ssh debian@192.168.122.156
Linux k8s-master-01 6.1.0-37-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.1.140-1 (2025-05-22) x86_64
Hello from Cloud-Init!
Last login: Sun Jul  6 02:31:33 2025 from 192.168.122.1
debian@k8s-master-01:~$ free -h 
               total        used        free      shared  buff/cache   available
Mem:           1.9Gi       236Mi       1.5Gi       632Ki       373Mi       1.7Gi
Swap:             0B          0B          0B
debian@k8s-master-01:~$ cat /proc/cpuinfo | grep name
model name      : AMD Ryzen 7 5800H with Radeon Graphics
model name      : AMD Ryzen 7 5800H with Radeon Graphics
```

## Bridge mode 
- deploy VM 
```
sudo virt-install \
  --name k8s-master-01 \
  --ram 2048 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/k8s-cluster/master-01.qcow2,backing_store=/var/lib/libvirt/images/qcow2/debian-12-generic-amd64.qcow2,size=20 \
  --disk path=/tmp/cloud-init-master-01.iso,device=cdrom \
  --os-variant debian11 \
  --network bridge=br0,model=virtio \
  --graphics none \
  --console pty,target_type=serial \
  --import
```

## NAT mode 
- auto start default network 
```
$ sudo virsh net-start default
Network default started

$ sudo virsh net-autostart default
Network default marked as autostarted

$ sudo virsh net-info --network default 
Name:           default
UUID:           f9d2ad79-8cb8-45f1-9ca1-3622d907e540
Active:         yes
Persistent:     yes
Autostart:      yes
Bridge:         virbr0
```
- deploy vm 
```

udo virt-install \
  --name k8s-master-01 \
  --ram 2048 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/k8s-cluster/master-01.qcow2,backing_store=/var/lib/libvirt/images/qcow2/debian-12-generic-amd64.qcow2,size=20 \
  --disk path=/var/lib/libvirt/images/cloud-init/cloud-init-master-01.iso,device=cdrom \
  --os-variant debian11 \
  --network network=default,model=virtio \
  --graphics none \
  --noautoconsole \
  --import

Starting install...
Allocating 'master-01.qcow2'                                                                                                                                                                                           |    0 B  00:00:00 ... 
Creating domain...                                                                                                                                                                                                     |    0 B  00:00:00     
Domain creation completed.
```
- List IP address 
```
$ sudo virsh domifaddr k8s-master-01
 Name       MAC address          Protocol     Address
-------------------------------------------------------------------------------
 vnet0      52:54:00:8a:fc:d5    ipv4         192.168.122.29/24
```
- List all leases 
```
$ sudo virsh net-dhcp-leases default
 Expiry Time           MAC address         Protocol   IP address          Hostname   Client ID or DUID
-----------------------------------------------------------------------------------------------------------------------------------------------
 2025-07-06 04:17:34   52:54:00:8a:fc:d5   ipv4       192.168.122.29/24   -          ff:56:50:4d:98:00:02:00:00:ab:11:49:8d:37:42:f3:5a:f2:af
```

# VM Delete 
- turn off if running 
```
sudo virsh destroy k8s-master-01
```
- undefine VM 
```
sudo virsh undefine k8s-master-01
```
- remove qcow2 disk image 
- this creates a VM that uses the generic qcow2 as a base, but writes all changes to the images/k8s-cluster qcow2
```
sudo rm /var/lib/libvirt/images/k8s-cluster/k8s-master-01.qcow2
```

