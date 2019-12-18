#!/bin/sh

pool=default
size=20g
basevol=ovn-base.qcow2

if ! virsh vol-info --pool ${pool} --vol ${basevol} > /dev/null 2>&1; then
	echo creating ovn-base.qcow2
	virsh vol-create-as \
		--pool ${pool} \
		--name ${basevol} \
		--capacity ${size} \
		--format qcow2 \
		--backing-vol fedora-31-base.qcow2 \
		--backing-vol-format qcow2

	vol_path=$(virsh vol-path --pool ${pool} --vol ${basevol})

	virt-customize -a ${vol_path} \
		--run setup-ovn-base.sh \
		--selinux-relabel
fi

for x in {0..2}; do
	vol=ovn${x}.qcow2
	if ! virsh vol-info --pool ${pool} --vol ${vol} >/dev/null 2>&1; then
		echo creating ${vol}
		virsh vol-create-as \
			--pool ${pool} \
			--name ${vol} \
			--capacity ${size} \
			--format qcow2 \
			--backing-vol ${basevol} \
			--backing-vol-format qcow2

		vol_path=$(virsh vol-path --pool ${pool} --vol ${vol})

		virt-customize -a ${vol_path} \
			--hostname "ovn${x}" \
			--selinux-relabel
	fi
done
