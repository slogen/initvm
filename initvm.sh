#!/bin/bash

REALM=SCADAMINDS.COM
WORKGROUP=${REALM%%.*}

config_rsyslog() {
    local console_conf_file=/etc/rsyslog.d/99-console.conf
    test -f "$console_conf_file" && return 1
    sudo tee "$console_conf_file" <<EOF
 *.=crit;*.=err;*.=notice;*.=warn /dev/tty1
EOF
    sudo service rsyslog force-reload
}

config_snmpd() {
    local snmpd_config_file=/etc/snmp/snmpd.conf
    test -f "$snmpd_config_file" && return 1
    mkdir -p $(dirname $snmpd_config_file)
    sudo tee "$snmpd_config_file" <<EOF
rocommunity  public 10.20.15.100
rocommunity  public 62.242.41.100
disk / 10%
syslocation VM
syscontact  root@scadaminds.com
trap sink:        62.242.41.100
trap community:        public
snmpEnableAuthenTraps:    enabled
EOF
   fi
   sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y snmpd
}

pam_homedir() {
    local conf_file="/usr/share/pam-configs/mkhomedir"
    test -f "$conf_file" && return 0
    sudo tee "$conf_file" <<EOF
Name: activate mkhomedir
Default: yes
Priority: 900
Session-Type: Additional
Session:
        required                        pam_mkhomedir.so umask=0022 skel=/etc/skel
EOF
    sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y libpam-mkhomedir
    pam-auth-update --package
}

install_utils() {
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server git emacs24-nox tmux aptitude atsar atop console-log
}

domain_join() {
test -f /etc/samba/smb.conf && return 1
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
template homedir = /home/$WORKGROUP/%U
EOF

if test '!' -e /etc/sudoers.d/ad; then
    sudo tee /etc/sudoers.d/ad <<EOF
"%domain admins"             ALL=(ALL:ALL) NOPASSWD: ALL
EOF
    sudo chmod 0440 /etc/sudoers.d/ad
fi

. join_pass

sudo apt-get DEBIAN_FRONTEND=noninteractive -o Dpkg::Options::="--force-confold" install -y \
    openssh-server krb5-user winbind libpam-winbind libnss-winbind
sudo net ADS JOIN -U "JoinMachine@scadaminds.com%${JOINPASS}"
sudo grep 'winbind' /etc/nsswitch.conf || \
  sudo sed -e 's/^\(\(passwd\|group\|shadow\):[ ]*\)compat$/\1compat winbind/'\
       -i /etc/nsswitch.conf
sudo service winbind restart
}

help() {
cat 1>&2 <<EOF
usage: $0 [ALL|install_utils|domain_join|config_rsyslog|config_snmpd]
EOF
}

ALL() {
    domain_join
    install_utils
    config_rsyslog
    config_snmpd
    pam_homedir
}

test $# -eq 0 && help && exit 1
while test $# -ge 1; do
    case "$1" in 
	(domain_join) domain_join; shift;;
	(install_utils) install_utils; shift;;
	(config_rsyslog) config_rsyslog; shift;;
	(config_snmpd) config_snmpd; shift;;
	(pam_homedir) pam_homedir; shift;;
	(ALL) ALL; shift;;
	(*) help; exit 1;;
    esac
done
