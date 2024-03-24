#!/bin/bash

function setnetwork() {

    ethdev=$(ip a | grep UP | grep -v LOOP | head -1 | awk '{print $2}' | sed -e 's/://g')

    echo "Network settings are set to static proceeding setting static IP settings ${ethdev}"
    staticip="$(jq -r -e .ipsettings.ipaddr /mnt/tcrp/user_config.json)"
    staticdns="$(jq -r -e .ipsettings.ipdns /mnt/tcrp/user_config.json)"
    staticgw="$(jq -r -e .ipsettings.ipgw /mnt/tcrp/user_config.json)"
    staticproxy="$(jq -r -e .ipsettings.ipproxy /mnt/tcrp/user_config.json)"

    [ -n "$staticip" ] && [ $(ip a | grep $staticip | wc -l) -eq 0 ] && ip a add "$staticip" dev $ethdev
    [ -n "$staticdns" ] && [ $(grep ${staticdns} /etc/resolv.conf | wc -l) -eq 0 ] && sed -i "a nameserver $staticdns" /etc/resolv.conf
    [ -n "$staticgw" ] && [ $(ip route | grep "default via ${staticgw}" | wc -l) -eq 0 ] && ip route add default via $staticgw dev $ethdev
    [ -n "$staticproxy" ] &&
        export HTTP_PROXY="$staticproxy" && export HTTPS_PROXY="$staticproxy" &&
        export http_proxy="$staticproxy" && export https_proxy="$staticproxy"

}

if [ "${1}" = "patches" ]; then
  echo "Install staticip - ${1}"
  if [ -b /dev/synoboot3 ]; then
    mkdir /mnt/tcrp
    mount /dev/synoboot3 /mnt/tcrp
    if [ "$(jq -r -e .ipsettings.ipset /mnt/tcrp/user_config.json)" = "static" ]; then
      setnetwork
    fi
    umount /mnt/tcrp
  else
    return
  fi
  
fi
