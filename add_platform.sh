#!/bin/bash

baseurl="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/master"  # Base URL

ls -d */ | grep -v -e "9p" | while IFS= read -r dir; do
  for baseplatform in `cat platforms`
  do 
    
    echo "Adding ${baseplatform} to ${dir}rpext-index.json"

    jsonfile="./${dir}rpext-index.json"
    model_url="${baseurl}/${dir}recipes/universal.json"
    jq --arg model "${baseplatform}" --arg url "$model_url" '.releases += { ($model): $url }' "$jsonfile" > temp.json && mv temp.json "$jsonfile"    

  done
done
