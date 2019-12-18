#!/bin/bash
#
# usage: create-port-ns.sh <nsname> <portname> <macaddr>

while getopts a: ch; do
	case $ch in
	(a)	port_address=$OPTARG
		;;
	esac
done
shift $(( OPTIND - 1 ))

if [[ $# -ne 3 ]]; then
	echo "usage: $0 <nsname> <portname> <macaddr>" >&2
	exit 2
fi

nsname=$1
portname=$2
macaddr=$3

ip netns add $nsname
ovs-vsctl --may-exist add-port br-int $portname -- \
	set interface $portname \
		mac="[\"$macaddr\"]" \
		type=internal \
		external_ids:iface-id=$portname

ip link set netns $nsname $portname

if [[ $port_address ]]; then
	ip netns exec $nsname ip addr add $port_address dev $portname
fi

ip netns exec $nsname ip link set $portname up
