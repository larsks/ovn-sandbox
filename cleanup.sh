#!/bin/sh

for x in {0..2}; do
	echo removing ovn${x}
	virsh destroy ovn${x} > /dev/null 2>&1
	virsh undefine --remove-all-storage ovn${x} > /dev/null 2>&1
done
