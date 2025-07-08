#!/bin/bash 

set -e

# Consts
DISK_BASE_PATH="/var/lib/libvirt/images/k8s-cluster/"
BACKING_STORE="/var/lib/libvirt/images/qcow2/debian-12-generic-amd64.qcow2"
CLOUD_INIT_BASE="/var/lib/libvirt/images/cloud-init/"

# Check required vars 
if [ -z "$VM_NAME" ]; then 
	echo "Error: VM_NAME is not set."
	exit 1
fi 

if [ -z "$VM_RAM" ]; then 
	echo "Error: VM_RAM is not set."
	exit 1
fi 

if [ -z "$VM_CPU" ]; then 
	echo "Error: VM_CPU is not set."
	exit 1
fi 

if [ -z "$VM_DISK" ]; then 
	echo "Error: VM_DISK is not set."
	exit 1
fi 

if [ ! -f "${CLOUD_INIT_BASE}${VM_NAME}.iso" ]; then 
	echo "Cloud init file missing."
	exit 1 
fi 

sudo virt-install \
	--name "$VM_NAME"\
	--ram "$VM_RAM"\
	--vcpus "$VM_CPU"\
	--disk path="${DISK_BASE_PATH}${VM_NAME}.qcow2,backing_store=${BACKING_STORE},size=${VM_DISK}"\
	--disk path="${CLOUD_INIT_BASE}${VM_NAME}.iso,device=cdrom"\
	--os-variant debian11\
	--network network=default,model=virtio\
	--graphics none\
	--noautoconsole\
	--import

sudo virsh autostart "${VM_NAME}"
