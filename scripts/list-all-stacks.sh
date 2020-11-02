#!/usr/bin/env bash

readarray -t supported_regions < /code/supported_regions.txt

for i in ${!supported_regions[@]}; do
    region=${supported_regions[$i]}
    echo "Stacks in $region:"
    AWS_REGION=$region aws cloudformation describe-stacks | jq -r '.Stacks[].StackName'
    echo
done
