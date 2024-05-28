#!/usr/bin/env ash

# | status      | Hexa value                    |
# | original    | 803e 00b8 0100 0000 7520 488b | 7.1.X
# | original    | 803e 00b8 0100 0000 7524 488b | 7.2.X
# | patched     | 803e 00b8 0100 0000 9090 488b |

MODEL=$(cat /proc/sys/kernel/syno_hw_version)
file="/lib64/libhwcontrol.so.1"

# Replace/add values in synoinfo.conf K=V file
# Args: $1 rd|hd, $2 key, $3 val
function _set_conf_kv() {
  local ROOT
  local FILE
  [ "$1" = "rd" ] && ROOT="" || ROOT=""
  for SD in etc etc.defaults; do
    FILE="${ROOT}/${SD}/synoinfo.conf"
    # Replace
    if grep -q "^$2=" ${FILE}; then
      sed -i ${FILE} -e "s\"^$2=.*\"$2=\\\"$3\\\"\""
    else
      # Add if doesn't exist
      echo "$2=\"$3\"" >>${FILE}
    fi
  done
}

function msgwarning() {
    echo -e "\033[1;33m$1\033[0m"
}

function readanswer() {
    while true; do
        read answ
        case $answ in
            [Yy]* ) answer="$answ"; break;;
            [Nn]* ) answer="$answ"; break;;
            * ) msgwarning "Please answer yY/nN.";;
        esac
    done
}      

if [ "${MODEL}" = "DS3622xs+" ]; then
  echo "Skip ${MODEL} (Not Supported)"
  exit 0
fi

echo "If a problem occurs and you want to restore the modified '/lib64/libhwcontrol.so.1' file to its original state, run the command below with root privileges."
echo "cp -vf ${file}.bak ${file}"
msgwarning "Do you want to enable m.2 volume? [yY/nN] : "
readanswer

if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then
  [ ! -f "${file}.bak" ] && cp -vf "${file}" "${file}.bak"
  /usr/bin/xxd -c $(/usr/bin/xxd -p "${file}.bak" | wc -c) -p "${file}.bak" | sed "s/803e00b801000000752.488b/803e00b8010000009090488b/" | /usr/bin/xxd -r -p > "${file}"
  _set_conf_kv rd "supportnvme" "yes"
  _set_conf_kv rd "support_m2_pool" "yes"
fi
