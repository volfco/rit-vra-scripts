#!/bin/bash

# Copyright 2017 Rochester Institute of Technology
#   Colum McGaley <cxm7688@rit.edu>

# This product, and all resources contained herein, are provided for reference
# and non-commercial uses only. Modifications are permitted for Personal and
# Educational use only, as long as they are distributed for the same purpose and
# not for used for commercial purposes. Any other use is prohibited unless
# authorized by owner or the Institute.
#
# Required Inputs
#   $DomainTemplate     Domain Template for the zone
#   $ServerName         This server's name. This will be the new hostname
#   $Password           FreeIPA Administrator and Directory Password
#   $CAServer           CA Server (dcano1.ca.local or dcano2.ca.local)
#   $Domain

echo "== Mounting Shared Drive ==============="
mkdir /mnt/shared
yum -y install cifs-utils > /dev/null
mount -t cifs //itsnas01.main.ad.rit.edu/vRAscripts$ /mnt/shared -o ro,username=vrauser,password=Student1!

echo "== Setting Variables ==================="
USERNAME=$(/usr/bin/python3 /mnt/shared/Components/guesthelpr/src/workitem.py --property virtualmachine.admin.owner --filter username)
DOMAIN="${DomainTemplate/'%VRMOwner%'/$USERNAME}"
DOMAIN="${DOMAIN/'%Domain%'/$Domain}"
ServerFQDN="$ServerName.$DOMAIN"
FQDN="$DOMAIN"
echo "Username: $USERNAME"
echo "Domain: $DOMAIN"
echo "Server FQDN: $ServerFQDN"

# Install FreeIPA Server
echo "== Install FreeIPA Server Components ==="
yum -y install freeipa-server ipa-server-dns > /dev/null

# Src: http://stackoverflow.com/a/33550399
NET_IF=`netstat -rn | awk '/^0.0.0.0/ {thif=substr($0,74,10); print thif;} /^default.*UG/ {thif=substr($0,65,10); print thif;}'`
NET_IP=`/usr/sbin/ifconfig ${NET_IF} | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'`

echo "127.0.0.1     localhost" > /etc/hosts
echo "$NET_IP     $ServerFQDN " >> /etc/hosts
hostnamectl set-hostname $(echo "$ServerFQDN")

# Part 1. Install without CA, so we can get the CSR
echo "== Install FreeIPA Server =============="
/usr/sbin/ipa-server-install -r $(echo $DOMAIN) -n $(echo $DOMAIN) -p $(echo $Password) -a $(echo $Password) -U --hostname $(echo "$ServerFQDN") --external-ca --setup-dns --forwarder=172.31.1.1 --forwarder=172.31.1.2 --no-reverse

if [ $? -ne 0 ]; then
  exit 1
fi

echo "== Signing CA Cert ====================="
/usr/bin/python3 /mnt/shared/Components/certsrv/src/certsrv.py --hostname $(echo $CAServer) --csr /root/ipa.csr --crt /root/ipa.crt --include-chain --no-ssl --verbose

if [ $? -ne 0 ]; then
  exit 1
fi

# TODO Add synthetic entropy to drop the run time of the below command
echo "== Finishing up ========================"
/usr/sbin/ipa-server-install -r $(echo $DOMAIN) -p $(echo $Password) -a $(echo $Password) -U --external-cert-file=/root/ipa.crt

if [ $? -ne 0 ]; then
  exit 1
fi

echo "== Opening Ports ======================="
firewall-cmd --add-port=80/tcp --permanent    # HTTP
firewall-cmd --add-port=443/tcp --permanent   # HTTPs
firewall-cmd --add-port=389/tcp --permanent   # LDAP
firewall-cmd --add-port=636/tcp --permanent   # LDAPS
firewall-cmd --add-port=88/tcp --permanent    # Kerberos
firewall-cmd --add-port=464/tcp --permanent   # Kerberos
firewall-cmd --add-port=53/tcp --permanent    # DNS
firewall-cmd --add-port=88/udp --permanent    # Kerberos
firewall-cmd --add-port=464/udp --permanent   # Kerberos
firewall-cmd --add-port=53/udp --permanent    # DNS
firewall-cmd --add-port=123/udp --permanent   # NTP
systemctl reload firewalld