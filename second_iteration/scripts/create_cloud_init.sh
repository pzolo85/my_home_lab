#!/bin/bash 

set -e

if [ -z "$VM_NAME" ]; then
	echo "Error: VM_NAME is not set."
	exit 1
fi

TEMPLATE_FILE="./cloud_init.tpl"
OUT_FILE="./cloud_init.tmp" 
CLOUD_INIT_BASE="/var/lib/libvirt/images/cloud-init/"

if [ ! -f "$TEMPLATE_FILE" ]; then
	echo "Error: Template file '$TEMPLATE_FILE' does not exist."
	exit 1
fi

envsubst < "${TEMPLATE_FILE}" > "${OUT_FILE}" 

sudo cloud-localds "${CLOUD_INIT_BASE}${VM_NAME}.iso" "${OUT_FILE}"
rm "${OUT_FILE}"

