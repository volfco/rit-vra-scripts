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
#   $DomainType         freeipa or ad
#   $Domain             Domain
#   $Username           User to bind to the domain with
#   $Password

echo "== Installing IPA Client ==============="
yum -y install ipa-client > /dev/null

HOSTNAME=$(hostname | tr '[:upper:]' '[:lower:]')
# Src: http://stackoverflow.com/a/33550399
NET_IF=`netstat -rn | awk '/^0.0.0.0/ {thif=substr($0,74,10); print thif;} /^default.*UG/ {thif=substr($0,65,10); print thif;}'`
NET_IP=`/usr/sbin/ifconfig ${NET_IF} | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'`

echo "127.0.0.1     localhost" > /etc/hosts
echo "$NET_IP     $HOSTNAME.$Domain " >> /etc/hosts
hostnamectl set-hostname $(echo "$HOSTNAME.$Doamin")


echo "== Mounting Shared Drive ==============="
/usr/sbin/ipa-client-install --domain=$(echo $Domain) --principal=$(echo $Username) --password=$(echo $Password) --unattended --enable-dns-updates
