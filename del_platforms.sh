#!/bin/bash

baseurl="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/master"  # Base URL

ls -d */ | grep -v -e "9p" -e "inject-loader" | while IFS= read -r dir; do
  for baseplatform in `cat delplatforms`
  do 
    
    echo "Removing ${baseplatform} to ${dir}rpext-index.json"

    jsonfile="./${dir}rpext-index.json"
    model_url="${baseurl}/${dir}recipes/universal.json"
    jq --arg model "${baseplatform}" '.releases |= del(.[$model])' "$jsonfile" > temp.json && mv temp.json "$jsonfile"

  done
done
