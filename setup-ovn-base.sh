#!/bin/sh

yum -y install \
	ovn \
	ovn-host \
	ovn-central \
	openvswitch \
	tcpdump \
	wireshark-cli \
	qemu-guest-agent \
	avahi

yum -y remove firewalld

cat > /etc/avahi/avahi-daemon.conf <<EOF
[server]
allow-interfaces=eth0
use-ipv4=yes
use-ipv6=yes
ratelimit-interval-usec=1000000
ratelimit-burst=1000
[wide-area]
enable-wide-area=yes
[publish]
publish-hinfo=no
publish-workstation=no
[reflector]
[rlimits]
EOF

systemctl enable qemu-guest-agent
systemctl enable avahi-daemon

mkdir -m 700 /root/.ssh
curl -o /root/.ssh/authorized_keys https://github.com/larsks.keys
chmod 600 /root/.ssh/authorized_keys
