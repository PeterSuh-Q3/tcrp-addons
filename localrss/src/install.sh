#!/usr/bin/env ash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "patches" ]; then
  echo "Installing addon localrss - ${1}"

  # MajorVersion=`/bin/get_key_value /etc.defaults/VERSION majorversion`
  # MinorVersion=`/bin/get_key_value /etc.defaults/VERSION minorversion`
  . "/etc.defaults/VERSION"

  MODEL=$(cat /proc/sys/kernel/syno_hw_version)
  MODEL=${MODEL/-*/}

  MCHECKSUM=$(jq -r --arg model "$MODEL" --arg ver "$productversion" --arg build "$buildnumber" '.[$model][$ver + "-" + $build + "-0"].sum // "NOT_FOUND"' pats.json)
  MLINK=$(jq -r --arg model "$MODEL" --arg ver "$productversion" --arg build "$buildnumber" '.[$model][$ver + "-" + $build + "-0"].url // "NOT_FOUND"' pats.json)
  
  echo "${MLINK}"
  echo "${MCHECKSUM}"
  
  # External incoming required ${MLINK} and ${MCHECKSUM}
  if [ "${MLINK}" = "NOT_FOUND" ] || [ "${MCHECKSUM}" = "NOT_FOUND" ]; then
    echo "MLINK or MCHECKSUM not found in pats.json"
    return
  fi

  cat >"/usr/syno/web/localrss.json" <<EOF
{
  "version": "2.0",
  "channel": {
    "title": "RSS for DSM Auto Update",
    "link": "https://update.synology.com/autoupdate/v2/getList",
    "pubDate": "$(TZ=CST-8 date)",
    "copyright": "Copyright 2026 Synology Inc",
    "item": [
      {
        "title": "DSM ${major}.${minor}$([ "0" = "${micro}" ] || echo ".${micro}")-${buildnumber}",
        "MajorVer": ${major},
        "MinorVer": ${minor},
        "NanoVer": ${micro},
        "BuildPhase": 0,
        "BuildNum": ${buildnumber},
        "BuildDate": "${builddate}",
        "ReqMajorVer": ${major},
        "ReqMinorVer": 0,
        "ReqBuildPhase": 0,
        "ReqBuildNum": 0,
        "ReqBuildDate": "${builddate}",
        "isSecurityVersion": false,
        "phase": "Release",
        "model": [
            {
                "mUnique": "${unique}",
                "mLink": "${MLINK}",
                "mCheckSum": "${MCHECKSUM}"
            }
        ]
      }
    ]
  }
}
EOF

  cat >"/usr/syno/web/localrss.xml" <<EOF
<?xml version="1.0"?>
<rss version="2.0">
  <channel>
      <title>RSS for DSM Auto Update</title>
      <link>http://update.synology.com/autoupdate/genRSS.php</link>
      <pubDate>$(TZ=CST-8 date)</pubDate>
      <copyright>Copyright 2026 Synology Inc</copyright>
    <item>
      <title>DSM ${major}.${minor}$([ "0" = "${micro}" ] || echo ".${micro}")-${buildnumber}</title>
      <MajorVer>${major}</MajorVer>
      <MinorVer>${minor}</MinorVer>
      <BuildPhase>0</BuildPhase>
      <BuildNum>${buildnumber}</BuildNum>
      <BuildDate>${builddate}</BuildDate>
      <ReqMajorVer>${major}</ReqMajorVer>
      <ReqMinorVer>0</ReqMinorVer>
      <ReqBuildPhase>0</ReqBuildPhase>
      <ReqBuildNum>0</ReqBuildNum>
      <ReqBuildDate>${builddate}</ReqBuildDate>
      <model>
        <mUnique>${unique}</mUnique>
        <mLink>${MLINK}</mLink>
        <mCheckSum>${MCHECKSUM}</mCheckSum>
      </model>
    </item>
  </channel>
</rss>
EOF

  if [ -f "/usr/syno/web/localrss.xml" ]; then
    # cat /usr/syno/web/localrss.xml
    sed -i "s|rss_server=.*$|rss_server=\"http://localhost:5000/localrss.xml\"|g" "/etc/synoinfo.conf" "/etc.defaults/synoinfo.conf"
    sed -i "s|rss_server_ssl=.*$|rss_server_ssl=\"http://localhost:5000/localrss.xml\"|g" "/etc/synoinfo.conf" "/etc.defaults/synoinfo.conf"
  fi
  if [ -f "/usr/syno/web/localrss.json" ]; then
    # cat /usr/syno/web/localrss.json
    sed -i "s|rss_server_v2=.*$|rss_server_v2=\"http://localhost:5000/localrss.json\"|g" "/etc/synoinfo.conf" "/etc.defaults/synoinfo.conf"
  fi
  grep "rss_server" "/etc.defaults/synoinfo.conf"
fi
