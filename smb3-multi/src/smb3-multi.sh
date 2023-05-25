#!/bin/sh
echo "Add the smb3 multichannel configuration to the /etc/samba/smb.conf file."
[ $(cat /etc/samba/smb.conf | grep "server multi channel support=yes" | wc -l) -eq 0 ] && echo "server multi channel support=yes" >> /etc/samba/smb.conf
[ $(cat /etc/samba/smb.conf | grep "aio read size=1" | wc -l) -eq 0 ] && echo "aio read size=1" >> /etc/samba/smb.conf
[ $(cat /etc/samba/smb.conf | grep "aio write size=1" | wc -l) -eq 0 ] && echo "aio write size=1" >> /etc/samba/smb.conf
cat /etc/samba/smb.conf | grep -e multi -e aio
