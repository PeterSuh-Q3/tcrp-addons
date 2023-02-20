#!/bin/sh

echo "Collecting 1st nvme paths"
nvmepath1=$(udevadm info --query path --name nvme0n1 | awk -F "/" '{print $4}' )
echo "Found local 1st nvme with path $nvmepath1"
if [ $(echo $nvmepath1 | wc -w) -eq 0 ]; then
    echo "Not found local 1st nvme"
    exit 0
else
    hex1=$(udevadm info --query path --name nvme0n1 | awk -F "/" '{print $4}' | awk -F ":" '{print $3}' | cut -c 1-1 | xxd  -c 256 -ps | sed "s/..$//")
    hex2=$(udevadm info --query path --name nvme0n1 | awk -F "/" '{print $4}' | awk -F ":" '{print $3}' | cut -c 2-2 | xxd  -c 256 -ps | sed "s/..$//")
    hex3=$(udevadm info --query path --name nvme0n1 | awk -F "/" '{print $4}' | awk -F ":" '{print $3}' | cut -c 4-4 | xxd  -c 256 -ps | sed "s/..$//")
    nvme1hex=$(echo "3a$hex1 $hex2/2e $hex3/00" | sed "s/\///g" )
    echo $nvme1hex

    nvme3hex=$(echo "$hex1$hex2 2e$hex3")
    echo $nvme3hex
fi

echo ""
echo "Collecting 2nd nvme paths"
nvmepath2=$(udevadm info --query path --name nvme1n1 | awk -F "/" '{print $4}' )
echo "Found local 2nd nvme with path $nvmepath2"
if [ $(echo $nvmepath2 | wc -w) -eq 0 ]; then
    echo "Not found local 2nd nvme"
else
    hex4=$(udevadm info --query path --name nvme1n1 | awk -F "/" '{print $4}' | awk -F ":" '{print $3}' | cut -c 1-1 | xxd  -c 256 -ps | sed "s/..$//")
    hex5=$(udevadm info --query path --name nvme1n1 | awk -F "/" '{print $4}' | awk -F ":" '{print $3}' | cut -c 2-2 | xxd  -c 256 -ps | sed "s/..$//")
    hex6=$(udevadm info --query path --name nvme1n1 | awk -F "/" '{print $4}' | awk -F ":" '{print $3}' | cut -c 4-4 | xxd  -c 256 -ps | sed "s/..$//")
    nvme2hex=$(echo "$hex4$hex5 2e$hex6")
    echo $nvme2hex

    nvme4hex=$(echo "3a$hex4" )
    echo $nvme4hex

    nvme6hex=$(echo "$hex5/2e $hex6/00" | sed "s/\///g" )
    echo $nvme6hex
fi

if [ $(uname -a | grep '918+\|1019+\|1621xs+' | wc -l) -gt 0 ]; then
    echo "Backup & Copy original libsynonvme.so.1 file to root home"
    if [ -f /lib64/libsynonvme.so.1.bak ]; then
        echo "Found libsynonvme.so.1.bak file"
    else
        cp /lib64/libsynonvme.so.1 /lib64/libsynonvme.so.1.bak
    fi    
    cp /lib64/libsynonvme.so.1.bak /root/libsynonvme.so
fi

if [ $(uname -a | grep '918+' | wc -l) -gt 0 ]; then
    if [ $(echo $nvmepath2 | wc -w) -gt 0 ]; then
        xxd /root/libsynonvme.so | sed "s/3a31 332e 3100/$nvme1hex/" | sed "s/3133 2e32/$nvme2hex/" | xxd -r > /lib64/libsynonvme.so.1
    else
        xxd /root/libsynonvme.so | sed "s/3a31 332e 3100/$nvme1hex/" | xxd -r > /lib64/libsynonvme.so.1
    fi
elif [ $(uname -a | grep '1019+' | wc -l) -gt 0 ]; then
    xxd /root/libsynonvme.so | sed "s/3134 2e31/$nvme3hex/" | xxd -r > /lib64/libsynonvme.so.1
elif [ $(uname -a | grep '1621xs+' | wc -l) -gt 0 ]; then
    if [ $(echo $nvmepath2 | wc -w) -gt 0 ]; then
        xxd /root/libsynonvme.so | sed "s/3031 2e31/$nvme3hex/" | sed "s/2e30 0030 3030 303a 3030 3a30/2e30 0030 3030 303a 3030 $nvme4hex/" | sed "s/312e 3000/$nvme6hex/" | xxd -r > /lib64/libsynonvme.so.1
    else
        xxd /root/libsynonvme.so | sed "s/3031 2e31/$nvme3hex/" | xxd -r > /lib64/libsynonvme.so.1
    fi
else
    if [ $(echo $nvmepath1 | wc -w) -gt 0 ]; then
        sed -i "/pci1=\"*\"/cpci1=\"$nvmepath1\"" /etc.defaults/extensionPorts
        cat /etc.defaults/extensionPorts
    fi

    if [ $(echo $nvmepath2 | wc -w) -gt 0 ]; then
        sed -i '3d' /etc.defaults/extensionPorts
        echo "pci2=\"$nvmepath2\"" >> /etc.defaults/extensionPorts
        cat /etc.defaults/extensionPorts
    fi
# add supportnvme="yes" to /etc.defaults/synoinfo.conf 2023.02.10
    if [ $(cat /etc.defaults/synoinfo.conf | grep supportnvme | wc -l) -eq 0 ]; then
        echo 'add supportnvme="yes" to /etc.defaults/synoinfo.conf'
        echo 'supportnvme="yes"' >> /etc.defaults/synoinfo.conf
        cat /etc.defaults/synoinfo.conf | grep supportnvme
    fi
fi

#DS918+�nvme_model_spec_get.c�%s:%d Bad paramter�0000:00:13.1�0000:00:13.2�RS1619xs+�0000:00:03.2�0000:00:03.3�DS419+�DS1019+�0000:00:14.1�DS719+�DS1621xs+�0000:00:1d.0�0000:00:01.0�04.0�05.0�08.0
#DS918+ DS1019+ DS1621xs+
#xxd /lib64/libsynonvme.so.1 |grep '3a31 332e 3100'
#xxd /lib64/libsynonvme.so.1 |grep '3a31 642e 3000'

