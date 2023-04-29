#!/bin/bash

# Define the JSON file location
JSON_FILE="./recipes/universal.json"

# Update each URL
for i in {0..1}
do
    URL=$(jq -r ".files[$i].url" $JSON_FILE)
    SHA256=$(curl -sSL $URL | sha256sum | awk '{print $1}')
    jq --arg sha256 "$SHA256" ".files[$i].sha256 = \$sha256" $JSON_FILE > tmp.json && mv tmp.json $JSON_FILE
done
