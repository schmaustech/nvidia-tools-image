#!/bin/bash
# Quick script to run inside container to show network interface and driver it maps to
printf "%10s %s %20s %8s\n" "Device" "Address" "Driver" "State"
for interface in /sys/class/net/*; do
    device=$(basename $interface)
    driver=$(readlink $interface/device/driver/module)
    if [ $driver ]; then
        driver=$(basename $driver)
    fi
    address=$(cat $interface/address)
    state=$(cat $interface/operstate)
    printf "%10s [%s]: %10s (%s)\n" "$device" "$address" "$driver" "$state"
done
