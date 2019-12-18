#!/bin/bash

NB=ovn-nbctl

# exit on error
set -e

# create switches
$NB --may-exist ls-add net0

# create net0 port for gateway
$NB --may-exist lsp-add net0 net0-gw
$NB lsp-set-addresses net0-gw "c0:ff:ee:00:00:01 10.0.0.1"

ovs-vsctl --may-exist add-port br-int net0-gw -- \
	set interface net0-gw \
	    type=internal mac='"c0:ff:ee:00:00:01"' \
	    external_ids:iface-id=net0-gw

dhcp_options=$($NB create dhcp_options \
	cidr=10.0.0.0/24 \
	options='
		"lease_time"="3600" \
		"router"="10.0.0.1" \
		"server_id"="10.0.0.1" \
		"server_mac"="c0:ff:ee:00:00:01"')

for portnum in {1..3}; do
	port=port${portnum}
	echo "Creating port $port"

	addr=$(( 10 + portnum ))
	macaddr="c0:ff:ee:00:00:$addr"
	ipaddr="10.0.0.$addr"

	$NB --may-exist lsp-add net0 $port
	$NB lsp-set-addresses $port "$macaddr $ipaddr"
	$NB lsp-set-dhcpv4-options $port $dhcp_options
done

ip addr add 10.0.0.1/24 dev net0-gw
ip link set net0-gw up

