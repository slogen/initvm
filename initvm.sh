#!/bin/bash

set -x

REALM=SCADAMINDS.COM
WORKGROUP=${REALM%%.*}

sudo debconf-set-selections -v <<EOF
krb5-config     krb5-config/default_realm       string  $REALM
libpam-runtime  libpam-runtime/profiles multiselect     unix, winbind, systemd
EOF

mkdir -p /etc/samba
sudo tee /etc/samba/smb.conf <<EOF
[global]
security=ads
realm=$REALM
WORKGROUP=$WORKGROUP
server string = %h server (Samba)
domain master = no
local master = no
wins support = no
max log size = 1000
syslog = 0
map to guest = bad user
winbind enum users = yes
winbind use default domain = yes
winbind nested groups = yes
winbind offline logon = true
idmap config $WORKGROUP : backend = rid
idmap config $WORKGROUP : range = 200000 - 210000
idmap config $WORKGROUP : read only = yes
idmap config * : backend = rid
idmap config * : range = 100000 - 110000
idmap config * : read only = yes
idmap cache time = 51840000 # 60 days
template shell = /bin/bash
template homedir = /home/%U
EOF

if test '!' -e /etc/sudoers.d/ad; then
    sudo tee /etc/sudoers.d/ad <<EOF
"%domain admins"             ALL=(ALL:ALL) NOPASSWD: ALL
EOF
    sudo chmod 0440 /etc/sudoers.d/ad
fi

. join_pass

sudo apt-get -o Dpkg::Options::="--force-confold" install openssh-server krb5-user winbind libpam-winbind libnss-winbind
sudo net ADS JOIN -U "JoinMachine@scadaminds.com%${JOINPASS}"
sudo grep 'winbind' /etc/nsswitch.conf || \
  sudo sed -e 's/^\(\(passwd\|group\|shadow\):[ ]*\)compat$/\1compat winbind/'\
       -i /etc/nsswitch.conf
sudo service winbind restart

