#!/bin/bash

if [ -z "$1" ]; then
  echo "Please provide a model as an argument."
  exit 1
fi

model="$1"
baseurl="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/master"  # Base URL

ls -d */ | grep -v -e "9p" | while IFS= read -r dir; do
  echo "Adding model $model for ${dir}rpext-index.json"
  jsonfile="./${dir}rpext-index.json"

  model_url="${baseurl}/${dir}recipes/universal.json"
  jq --arg model "${model}_42218" --arg url "$model_url" '.releases += { ($model): $url }' "$jsonfile" > temp.json && mv temp.json "$jsonfile"
  jq --arg model "${model}_42962" --arg url "$model_url" '.releases += { ($model): $url }' "$jsonfile" > temp.json && mv temp.json "$jsonfile"
  jq --arg model "${model}_64570" --arg url "$model_url" '.releases += { ($model): $url }' "$jsonfile" > temp.json && mv temp.json "$jsonfile"  
  jq --arg model "${model}_69057" --arg url "$model_url" '.releases += { ($model): $url }' "$jsonfile" > temp.json && mv temp.json "$jsonfile"    
done
