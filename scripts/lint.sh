#!/usr/bin/env bash

# https://stackoverflow.com/a/246128
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd $DIR/../cdk
cdk synth > $DIR/../test/main-test/template.yaml
cd $DIR/../test/main-test
taskcat lint
