#!/bin/bash

echo "== Mounting Shared Drive ==============="
yum -y install cifs-utils
mkdir -p /opt/mnt/shared
mount -t cifs //itsnas01.main.ad.rit.edu/vRAscripts$ /opt/mnt/shared -o ro,username=vrauser,password=Student1!

echo "== Installing Powershell ==============="
yum -y install https://github.com/PowerShell/PowerShell/releases/download/v6.0.0-alpha.16/powershell-6.0.0_alpha.16-1.el7.centos.x86_64.rpm

echo "== Cleaning Up ========================="
umount /opt/mnt/shared/
