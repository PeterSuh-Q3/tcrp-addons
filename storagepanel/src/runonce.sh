#!/bin/bash

# Check if the script has already run
if [ -f "/etc/flagfile" ]; then
    echo "Script has already run. Exiting."
    exit 0
fi

# Your processing logic here
echo "Processing..."
eval $(/bin/sqlite3 /usr/syno/etc/esynoscheduler/esynoscheduler.db "select operation from task a where task_name = 'Change Storage Panel';" | awk -F'#' '{print $1}')

# Create a flag file to indicate that the script has run
touch "/etc/flagfile"

echo "Script completed."
