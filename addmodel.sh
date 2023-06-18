#!/bin/bash

ls -d */ | grep -v -e "9p" -e "disks"
for D in $(ls -d */ | grep -v -e "9p" -e "disks"); do
  E=$(echo "${D}" | sed 's#/##')
  echo "Add model ${1} for ${E} rpext-index.json"
  jsonfile=$(jq --arg model "${1}" --arg url "https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/master/${E}/recipes/universal.json" '.releases += { ($model_42218): $url }' "./${E}/rpext-index.json") && echo "$jsonfile" > "./${E}/rpext-index.json"
  jsonfile=$(jq --arg model "${1}" --arg url "https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/master/${E}/recipes/universal.json" '.releases += { ($model_42662): $url }' "./${E}/rpext-index.json") && echo "$jsonfile" > "./${E}/rpext-index.json"
  jsonfile=$(jq --arg model "${1}" --arg url "https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/master/${E}/recipes/universal.json" '.releases += { ($model_64570): $url }' "./${E}/rpext-index.json") && echo "$jsonfile" > "./${E}/rpext-index.json"  
done
