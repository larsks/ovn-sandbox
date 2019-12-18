#!/bin/sh

pool=default
size=10

for x in {0..2}; do
	name=ovn${x}

	virsh destroy ${name} >/dev/null 2>&1
	virsh undefine --remove-all-storage ${name} >/dev/null 2>&1

	virt-install \
		-r 4096 \
		--os-variant rhel7.7 \
		--controller=scsi,model=virtio-scsi \
		--noautoconsole \
		-w bridge=virbr0 \
		--cpu host-model \
		--import \
		--disk pool=${pool},size=${size},format=qcow2,backing_store=ovn-base.qcow2,backing_format=qcow2,bus=scsi \
		-n ${name}
done
