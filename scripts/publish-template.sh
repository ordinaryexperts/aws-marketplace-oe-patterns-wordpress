#!/usr/bin/env bash

# https://stackoverflow.com/a/246128
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if [ "$#" -ne 1 ]; then
    VERSION=`git describe`
else
    VERSION=$1
fi

mkdir -p $DIR/../dist
cd $DIR/../cdk
TEMPLATE_VERSION=$VERSION cdk synth \
    --version-reporting false\
    --path-metadata false \
    --asset-metadata false > $DIR/../dist/template.yaml
cd $DIR/..

aws s3 cp dist/template.yaml \
	s3://ordinary-experts-aws-marketplace-pattern-artifacts/wordpress/$VERSION/template.yaml \
	--acl public-read
echo "Copied to https://ordinary-experts-aws-marketplace-pattern-artifacts.s3.amazonaws.com/wordpress/$VERSION/template.yaml"
