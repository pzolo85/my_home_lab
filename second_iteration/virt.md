# KVM / QEMU :alien: - Preparing the hypervisor

## Components 

| Component  | Role                                                                 | Relation to Others                          |
|------------|----------------------------------------------------------------------|--------------------------------------------|
| **QEMU**   | Emulator/Virtualizer (handles devices, CPU emulation)                | Works alone or with KVM for acceleration.  |
| **KVM**    | Kernel module (enables hardware-assisted virtualization)             | Needs QEMU for full virtualization.        |
| **libvirt**| Management API (abstracts QEMU/KVM, Xen, etc.)                       | Uses QEMU-KVM as a backend.                |
| **virsh**  | CLI tool to control VMs (via libvirt)                                | Frontend for libvirt.                      |
- QEMU + KVM = High-performance virtualization (QEMU emulates devices, KVM accelerates CPU).
- libvirt = Manages QEMU-KVM (and other hypervisors) via APIs/tools like virsh.
- virsh = Lets you interact with libvirt from the command line.

## Installation 

- KVM/QEMU & Libvirt
```bash
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager cloud-image-utils
```
- Add user to group 
```bash
sudo usermod -aG libvirt $(whoami)
sudo usermod -aG kvm $(whoami)
```

## Networking 

There are two options to set-up the network for the virtual machines.
I can either have a bridge in front of my `enp1s0` interface, so that every VM gets its IP address assigned by the ISP router,
or I can use `libvirt` NAT and have the VM available only from within the hypervisor.
I decided to go for the NAT option (`libvirt` defaut network), but I tried the bridge mode first.

### Bridge mode 

- Edit `/etc/network/interfaces`
```bash
source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

## The primary network interface
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
- Reboot the server to apply the changes. 
- On this mode, `virt-install` needs to be run with `--network bridge=br0,model=virtio`

### NAT mode (default)

- Auto start default network 
```bash
$ sudo virsh net-start default
Network default started

$ sudo virsh net-autostart default
Network default marked as autostarted

$ sudo virsh net-dumpxml default 
<network>
  <name>default</name>
  <uuid>f9d2ad79-8cb8-45f1-9ca1-3622d907e540</uuid>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr0' stp='on' delay='0'/>
  <mac address='52:54:00:07:e8:d6'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
```
- `libvirt` uses `dnsmasq` for DNS Caching and DHCP server 

## Images 

### qcow2 :cow:

QEMU workds with qcow2 images (Copy-on-Write). This type of images offer dynamic allocation, so it grows only as data is written.
It also allows using backing files, so you can have child images that are basd on a read-only parent image.

We have a single `/var/lib/libvirt/images/qcow2/debian-12-generic-amd64.qcow2` parent qcow2 image that will be shared by all the VM.
The [generic](https://cdimage.debian.org/images/cloud/) image includes `cloud-init`, so I can set public keys and install packages on first boot. 
```bash
$ curl -LO https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
```

### cloud-init :cloud:

cloud-init images are `iso` files that get mounted as `cdrom` on `virt-install`

## Scripts :scroll:

I've created a series of [scripts](scripts/) to facilitate the creation / deletion of VM in the lab.

### Create VM :new:

- Start by creating a new `cloud-init` iso 
```bash
$ VM_NAME=test001 ./create_cloud_init.sh
$ file /var/lib/libvirt/images/cloud-init/test001.iso
/var/lib/libvirt/images/cloud-init/test001.iso: ISO 9660 CD-ROM filesystem data 'cidata'
```
- Create the new VM 
```bash
$ VM_NAME=test001 VM_RAM=512 VM_CPU=1 VM_DISK=5 ./create_vm.sh  
WARNING  Requested memory 512 MiB is less than the recommended 1024 MiB for OS debian11

Starting install...
Allocating 'test001.qcow2'  |    0 B  00:00:00 ... 
Creating domain...          |    0 B  00:00:00     
Domain creation completed.
Domain 'test001' marked as autostarted
```
- Confirm that the VM is running
```bash
$ sudo virsh list 
 Id   Name      State
-------------------------
 1    test001   running

$ sudo virsh domifaddr test001
 Name       MAC address          Protocol     Address
-------------------------------------------------------------------------------
 vnet0      52:54:00:7b:a8:a5    ipv4         192.168.122.119/24
 ```
 - Access via ssh 
```bash
 $ ssh debian@192.168.122.119
Linux test001 6.1.0-37-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.1.140-1 (2025-05-22) x86_64
welcome to test001

debian@test001:~$ free -h 
               total        used        free      shared  buff/cache   available
Mem:           457Mi        83Mi       116Mi       628Ki       269Mi       373Mi
Swap:             0B          0B          0B

debian@test001:~$ df -h /dev/vda1
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda1       4.8G  1.2G  3.3G  27% /
```

### Destroy VM :boom: 

- When the VM is created the following files are associated with it
```bash
$ sudo tree /var/lib/libvirt/
/var/lib/libvirt/
├── boot
├── dnsmasq
[...]
├── images
│   ├── cloud-init
│   │   └── test001.iso                         <-- cloud-init iso
│   ├── k8s-cluster
│   │   └── test001.qcow2                       <-- qcow2 image
│   └── qcow2
│       └── debian-12-generic-amd64.qcow2
├── qemu
│   ├── channel
│   │   └── target
│   │       └── domain-1-test001                <-- qemu channel
│   │           └── org.qemu.guest_agent.0
│   ├── checkpoint
│   ├── domain-1-test001                        <-- qemu keys
│   │   ├── master-key.aes
│   │   └── monitor.sock
│   ├── dump
[...]
```
- remove VM and all related files 
```bash
$ VM_NAME=test001 ./delete_vm.sh 
Domain 'test001' destroyed

Domain 'test001' has been undefined
```
