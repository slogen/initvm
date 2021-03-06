#!/bin/bash

REALM=SCADAMINDS.COM
WORKGROUP=${REALM%%.*}

config_ntp() {
    local conf="/etc/ntp.conf"
    test -f "$conf" && return 1
    tee "$conf" <<EOF
tinker panic 0

driftfile /var/lib/ntp/ntp.drift
statsdir /var/log/ntpstats/

statistics loopstats peerstats clockstats
filegen loopstats file loopstats type day enable
filegen peerstats file peerstats type day enable
filegen clockstats file clockstats type day enable

server ntp.scadaminds.com minpoll 4 maxpoll 8
server 0.dk.pool.ntp.org 
server 1.dk.pool.ntp.org

restrict -4 default kod notrap nomodify nopeer noquery
restrict -6 default kod notrap nomodify nopeer noquery

restrict 127.0.0.1
restrict ::1
EOF
    DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y ntp
}


config_snmpd() {
    local snmpd_config_file=/etc/snmp/snmpd.conf
    test -f "$snmpd_config_file" && return 1
    mkdir -p $(dirname $snmpd_config_file)
    tee "$snmpd_config_file" <<EOF
rocommunity  public 10.20.15.100
rocommunity  public 62.242.41.100
disk / 10%
syslocation VM
syscontact  root@scadaminds.com
trap sink:        62.242.41.100
trap community:        public
snmpEnableAuthenTraps:    enabled
EOF
    DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y snmpd
}

pam_homedir() {
    local conf_file="/usr/share/pam-configs/mkhomedir"
    test -f "$conf_file" && return 0
    tee "$conf_file" <<EOF
Name: activate mkhomedir
Default: yes
Priority: 900
Session-Type: Additional
Session:
        required                        pam_mkhomedir.so umask=0022 skel=/etc/skel
EOF
    DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y libpam-mkhomedir
    pam-auth-update --package
}

install_utils() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server git emacs24-nox tmux aptitude atsar atop console-log git-el
}

domain_join() {
test -f /etc/samba/smb.conf && return 1
debconf-set-selections -v <<EOF
krb5-config     krb5-config/default_realm       string  $REALM
libpam-runtime  libpam-runtime/profiles multiselect     unix, winbind, systemd
EOF

local pam_cfg=/etc/security/pam_winbind.conf
if test '!' -e "$pam_cfg"; then
    tee "$pam_cfg" <<EOF
[global]
require_membership_of = remote_desktoppers
EOF
fi


mkdir -p /etc/samba
tee /etc/samba/smb.conf <<EOF
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
winbind enum groups = yes
winbind use default domain = yes
winbind nested groups = yes
winbind expand groups = 5
winbind offline logon = true
winbind normalize names = yes
winbind refresh tickets = true
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
    tee /etc/sudoers.d/ad <<EOF
"%domain_admins"             ALL=(ALL:ALL) NOPASSWD: ALL
EOF
    chmod 0440 /etc/sudoers.d/ad
fi

JOINPASS="$(dig joinpass.scadaminds.com txt +short)"
JOINPASS="${JOINPASS%\"}"
JOINPASS="${JOINPASS#\"}"

DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" install -y \
    openssh-server krb5-user winbind libpam-winbind libnss-winbind
net ADS JOIN -U "JoinMachine@scadaminds.com%${JOINPASS}"
grep 'winbind' /etc/nsswitch.conf || \
  sed -e 's/^\(\(passwd\|group\|shadow\):[ ]*\)compat$/\1compat winbind/'\
       -i /etc/nsswitch.conf
service winbind restart
}

help() {
cat 1>&2 <<EOF
usage: $0 [ALL|install_utils|domain_join|config_snmpd]
EOF
}

ALL() {
    domain_join
    install_utils
    config_snmpd
    config_ntp
    pam_homedir
}

test $# -eq 0 && help && exit 1
while test $# -ge 1; do
    case "$1" in 
	(domain_join) domain_join; shift;;
	(install_utils) install_utils; shift;;
	(config_snmpd) config_snmpd; shift;;
	(config_ntp) config_ntp; shift;;
	(pam_homedir) pam_homedir; shift;;
	(ALL) ALL; shift;;
	(*) help; exit 1;;
    esac
done
