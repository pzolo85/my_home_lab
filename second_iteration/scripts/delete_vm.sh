#!/bin/bash 

set -e

# Consts
DISK_BASE_PATH="/var/lib/libvirt/images/k8s-cluster/"
CLOUD_INIT_BASE="/var/lib/libvirt/images/cloud-init/"

# Check required vars 
if [ -z "$VM_NAME" ]; then 
	echo "Error: VM_NAME is not set."
	exit 1
fi 

if [ ! -f "${CLOUD_INIT_BASE}${VM_NAME}.iso" ]; then 
	echo "Cloud init file missing. ${CLOUD_INIT_BASE}${VM_NAME}.iso"
	exit 1 
fi 

sudo virsh destroy "${VM_NAME}"
sudo virsh undefine "${VM_NAME}"
sudo rm "${DISK_BASE_PATH}${VM_NAME}.qcow2"
sudo rm "${CLOUD_INIT_BASE}${VM_NAME}.iso"
