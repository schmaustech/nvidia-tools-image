#!/bin/bash
# Script must be run as root user
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: $0 Must be run as root user"
  exit 1
fi
 
for device in `lspci -d "*:*:*" | awk '{print $1}'`; do
     # Skip if it doesn't support ACS
    setpci -v -s ${device} ECAP_ACS+0x6.w > /dev/null 2>&1
    if [ $? -ne 0 ]; then
            echo "${device} does not support ACS, skipping..."
            continue
    fi
     echo "Disabling ACS on ${device}..."
    setpci -v -s ${device} ECAP_ACS+0x6.w=0000
done
exit 0
