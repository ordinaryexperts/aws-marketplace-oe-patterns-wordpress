#!/usr/bin/env bash

echo "$(date): Starting setup-env.sh"

# this is also set in cdk/setup.py
export CDK_VERSION=1.137.0
export PACKER_VERSION=1.5.5
export TASKCAT_VERSION=0.9.29

# system upgrades and tools
export DEBIAN_FRONTEND=noninteractive
apt-get -y -q update && apt-get -y -q upgrade
apt-get -y -q install \
        curl  \
        git   \
        groff \
        jq    \
        less  \
        unzip \
        vim   \
        wget

# aws cli
cd /tmp
curl --silent --show-error https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip
unzip -q awscliv2.zip
./aws/install
cd -

# taskcat
apt-get -y -q install python3 python3-pip
pip3 install -q taskcat==$TASKCAT_VERSION

# For scripts/pfl.py
pip3 install -q \
     openpyxl   \
     pystache   \
     pyyaml

# more recent nodejs
curl -sL https://deb.nodesource.com/setup_14.x | bash -
apt-get -y -q install nodejs

# cdk
npm install -g aws-cdk@$CDK_VERSION

# packer
wget -q -O /tmp/packer.zip https://releases.hashicorp.com/packer/$PACKER_VERSION/packer_${PACKER_VERSION}_linux_amd64.zip
unzip /tmp/packer.zip -d /usr/local/bin/
rm /tmp/packer.zip

echo "$(date): Finished setup-env.sh"
