#!/usr/bin/env bash

for cont in $(seq 1 1 10)
do
    for key in $(seq 1 1 1000)
    do
        vault kv put kv/dummy-data/key_${key} value=$(uuidgen)
    done
done
