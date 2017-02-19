#!/bin/sh

echo "== Mounting Shared Drive ==============="
mkdir /mnt/shared
yum -y install cifs-utils
mount -t cifs //itsnas01.main.ad.rit.edu/vRAscripts$ /mnt/shared -o ro,username=vrauser,password=Student1!

echo "== Setting Variables ==================="
USERNAME=$(/usr/bin/python3 /mnt/shared/Common/guesthelpr/src/workitem.py --property virtualmachine.admin.owner --filter username)
DOMAIN="${DomainTemplate/%VRMOwner%/$USERNAME}"
PASSWORD="Student1!"
echo "Username: $USERNAME"
echo "Domain: $DOMAIN"

# Install FreeIPA Server
echo "== Install FreeIPA Server Components ==="
yum -y install freeipa-server ipa-server-dns

echo "127.0.0.1     localhost" > /etc/hosts
echo "dc01.freeipa.cxm7688-admin.lab" >> /etc/hosts
hostnamectl set-hostname dc01.freeipa.cxm7688-admin.lab

# Part 1. Install without CA, so we can get the CSR
echo "== Install FreeIPA Server =============="
ipa-server-install -r freeipa.cxm7688-admin.lab -b freeipa.cxm7688-admin.lab -p $(echo $PASSWORD) -a $(echo $PASSWORD) -U --hostname dc01.freeipa.cxm7688-admin.lab --external-ca --setup-dns --forwarder=172.31.1.1 --forwarder=172.31.1.2 --no-reverse

echo "== Signing CA Cert ====================="
python3 /mnt/shared/Components/certsrv/src/certsrv.py --hostname dcano1.ca.local --csr /root/ipa.csr --crt /root/ipa.crt --include-chain

# TODO Add synthetic entropy to drop the run time of the below command
echo "== Finishing up ========================"
ipa-server-install -r freeipa.cxm7688-admin.lab -p $(echo $PASSWORD) -a $(echo $PASSWORD) -U --external-cert-file=/root/ipa.crt

echo "== Opening Ports ======================="
firewall-cmd --add-port=80/tcp --permanent    # HTTP
firewall-cmd --add-port=443/tcp --permanent   # HTTPs
firewall-cmd --add-port=80/tcp --permanent    # HTTP
firewall-cmd --add-port=80/tcp --permanent    # HTTP
firewall-cmd --add-port=80/tcp --permanent    # HTTP
