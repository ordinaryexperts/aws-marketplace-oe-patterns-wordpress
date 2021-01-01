#!/bin/bash -eux

# wait for cloud-init to be done
if [ ! "$IN_DOCKER" = true ]; then
    cloud-init status --wait
fi

# apt upgrade
export DEBIAN_FRONTEND=noninteractive
apt-get -y update && apt-get -y upgrade

# install helpful utilities
apt-get -y install curl git jq ntp software-properties-common unzip vim wget zip

# install latest CFN utilities
apt-get -y install python-pip
pip install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz

# install aws cli
cd /tmp
curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip
unzip awscliv2.zip
./aws/install
cd -

# install SSM Agent
# https://docs.aws.amazon.com/systems-manager/latest/userguide/agent-install-deb.html
mkdir /tmp/ssm
cd /tmp/ssm
wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
dpkg -i -E ./amazon-ssm-agent.deb
systemctl enable amazon-ssm-agent

# install CloudWatch agent
cd /tmp
curl https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -o amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb
cd -
# collectd for metrics
apt-get -y install collectd

# install CodeDeploy agent - requires ruby
apt-get -y install ruby
cd /tmp
curl https://aws-codedeploy-us-west-1.s3.us-west-1.amazonaws.com/latest/install -o install
chmod +x ./install
./install auto
cd -

# install efs mount helper - requires git
apt-get -y install binutils git
git clone https://github.com/aws/efs-utils /tmp/efs-utils
cd /tmp/efs-utils
./build-deb.sh
apt-get install -y ./build/amazon-efs-utils*deb
cd -

# install RDS SSL CA for Aurora
mkdir -p /opt/aws/rds
cd /opt/aws/rds
wget https://www.amazontrust.com/repository/AmazonRootCA1.pem
cd -

# install RDS SSL CA for MySQL instance
cd /opt/aws/rds
wget https://s3.amazonaws.com/rds-downloads/rds-ca-2019-root.pem
cd -

# start WordPress specific stuff
# based on php:7.3-buster-apache
# https://github.com/docker-library/php/blob/26e65d3c2acc800f7b8f190540007b8bf0d66047/7.3/buster/apache/Dockerfile
{
    echo 'Package: php*';
    echo 'Pin: release *';
    echo 'Pin-Priority: -1';
} > /etc/apt/preferences.d/no-debian-php

apt-get install -y --no-install-recommends \
    autoconf \
    ca-certificates \
    curl \
    dpkg-dev \
    file \
    g++ \
    gcc \
    libc-dev \
    make \
    mariadb-client \
    pkg-config \
    re2c \
    xz-utils

APACHE_CONFDIR=/etc/apache2
APACHE_ENVVARS=$APACHE_CONFDIR/envvars

apt-get install -y --no-install-recommends apache2
rm -rvf /var/www/html/*
a2dismod mpm_event && a2enmod mpm_prefork

PHP_EXTRA_BUILD_DEPS=apache2-dev

GPG_KEYS="CBAF69F173A0FEA4B537F470D66C9593118BCCB6 F38252826ACD957EF380D39F2F7956BC5DA04B5D"

PHP_VERSION="7.4.13"
PHP_URL="https://www.php.net/distributions/php-7.4.13.tar.xz"
PHP_ASC_URL="https://www.php.net/distributions/php-7.4.13.tar.xz.asc"
PHP_SHA256="0865cff41e7210de2537bcd5750377cfe09a9312b9b44c1a166cf372d5204b8f"

# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=863199
mkdir -p /usr/share/man/man1
apt-get install -y --no-install-recommends gnupg dirmngr

mkdir -p /usr/src/php
cd /usr/src
curl -fsSL -o php.tar.xz "$PHP_URL"
tar -Jxf /usr/src/php.tar.xz -C "/usr/src/php" --strip-components=1

apt-get install -y --no-install-recommends \
   ghostscript \
   libargon2-dev \
   libcurl4-openssl-dev \
   libedit-dev \
   libfreetype6-dev \
   libjpeg-dev \
   libmagickwand-dev \
   libmcrypt-dev \
   libonig-dev \
   libpng-dev \
   libsodium-dev \
   libsqlite3-dev \
   libssl-dev \
   libxml2-dev \
   libzip-dev \
   libzip4 \
   zlib1g-dev \
   ${PHP_EXTRA_BUILD_DEPS:-}
