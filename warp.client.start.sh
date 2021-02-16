#!/bin/sh
warp client $(ip a | grep 172.20.2 | awk -F ' ' '{print $2}' | sed 's/\/.*//g'):8000
