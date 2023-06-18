#!/bin/bash

ls -d */ | grep -v -e "9p" -e "disks"
for D in `ls -d */ | grep -v -e "9p" -e "disks"`; do
  E=$(echo ${D} | sed 's#/##')
  echo "Add model ${1} for ${E} rpext-index.json"  
  jsonfile=$(jq '.releases |= .+ {$1_42218: "https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/master/${E}/recipes/universal.json"}' "./${E}/rpext-index.json") && echo $jsonfile | jq . > "./${E}/rpext-index.json"
  jsonfile=$(jq '.releases |= .+ {$1_42962: "https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/master/${E}/recipes/universal.json"}' "./${E}/rpext-index.json") && echo $jsonfile | jq . > "./${E}/rpext-index.json"
  jsonfile=$(jq '.releases |= .+ {$1_64570: "https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/master/${E}/recipes/universal.json"}' "./${E}/rpext-index.json") && echo $jsonfile | jq . > "./${E}/rpext-index.json"  
done
