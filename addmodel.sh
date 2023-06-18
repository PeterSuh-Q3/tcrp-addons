#!/bin/bash

ls -d */ | grep -v -e "9p" -e "disks"
for D in `ls -d */ | grep -v -e "9p" -e "disks"`; do
  E=$(echo ${D} | sed 's#/##')
  echo "Add model for ${E} directory"  
done
