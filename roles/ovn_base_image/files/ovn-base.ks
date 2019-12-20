# Use text mode install
text
repo --name=fedora-31 --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-31&arch=$basearch
repo --name=fedora-31-updates --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=updates-released-f31&arch=$basearch
reboot

# System bootloader configuration
bootloader --append="net.ifnames=0 console=tty1 console=ttyS0,115200n8 crashkernel=auto" --location=mbr --boot-drive=vda

# Disk configuration
ignoredisk --only-use=vda
autopart --type=thinp
clearpart --all --initlabel --drives=vda

# Keyboard layouts
keyboard --vckeymap=us --xlayouts=''
# System language
lang en_US.UTF-8

# Network information
network  --bootproto=dhcp --ipv6=auto --activate
network  --hostname=localhost.localdomain
# Root password
rootpw --lock --iscrypted *locked*
# Don't run the Setup Agent on first boot
firstboot --disable
# Do not configure the X Window System
skipx
# System timezone
timezone America/New_York --isUtc

%packages
@^minimal-environment
@container-management
git
tmux
yum-utils
ansible
ovn-host
ovn-central
jq
tcpdump
wireshark-cli
qemu-guest-agent
avahi
python3-libselinux
%end

%post --interpreter=/usr/bin/ansible-playbook --log=/root/postinstall-0.log
---
- hosts: localhost
  tasks:
    - name: create serial-getty@ttyS0 override directory
      file:
        path: /etc/systemd/system/serial-getty@ttyS0.service.d
        state: directory

    - name: create serial-getty@ttyS0 override configuration
      copy:
        dest: /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf
        content: |
          [Service]
          ExecStart=
          ExecStart=-/sbin/agetty -o '-p -- \\u' --keep-baud 115200,38400,9600 --noclear --autologin root ttyS0 $TERM
    
    - name: configure login for passwordless root access on secure ttys
      lineinfile:
        path: /etc/pam.d/login
        insertafter: '^#%PAM'
        line: >-
          auth sufficient pam_listfile.so item=tty sense=allow file=/etc/securetty onerr=fail apply=root

    - name: configure ttyS0 as a secure tty
      lineinfile:
        path: /etc/securetty
        create: true
        line: ttyS0

    - name: remove firewalld package
      package:
        name: firewalld
        state: absent

    - name: enable services
      service:
        name: "{{ item }}"
        enabled: true
      loop:
        - avahi-daemon
        - openvswitch
        - ovn-controller
        - qemu-guest-agent

    - name: add authorized keys to root account
      authorized_key:
        user: root
        key: https://github.com/larsks.keys
%end
