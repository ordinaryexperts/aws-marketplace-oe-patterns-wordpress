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
apt-get -y install python3-pip
ln -s /usr/bin/pip3 /usr/bin/pip
pip install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz

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
    rsync \
    xz-utils

# ses smtp integration
apt-get install -y msmtp msmtp-mta

APACHE_CONFDIR=/etc/apache2
APACHE_ENVVARS=$APACHE_CONFDIR/envvars

apt-get install -y --no-install-recommends apache2
a2dissite 000-default
rm -rvf /var/www/html
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

PHP_INI_DIR=/usr/local/etc/php
mkdir -p "$PHP_INI_DIR/conf.d"

PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
PHP_CPPFLAGS="$PHP_CFLAGS"
PHP_LDFLAGS="-Wl,-O1 -pie"
PHP_EXTRA_CONFIGURE_ARGS="--with-apxs2 --disable-cgi"

CFLAGS="$PHP_CFLAGS"
CPPFLAGS="$PHP_CPPFLAGS"
LDFLAGS="$PHP_LDFLAGS"

cd /usr/src/php
gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"
debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"
# https://bugs.php.net/bug.php?id=74125
if [ ! -d /usr/include/curl ]; then
	ln -sT "/usr/include/$debMultiarch/curl" /usr/local/include/curl
fi
# https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions
./configure \
	--build="$gnuArch" \
	--enable-ftp \
	--enable-mbstring \
	--enable-mysqlnd \
	--enable-option-checking=fatal \
	--with-config-file-path="$PHP_INI_DIR" \
	--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
	--with-curl \
	--with-libdir="lib/$debMultiarch" \
	--with-libedit \
	--with-mhash \
	--with-openssl \
	--with-password-argon2 \
    --with-pear \
	--with-pdo-sqlite=/usr \
	--with-pic \
	--with-sodium=shared \
	--with-sqlite3=/usr \
	--with-zip \
	--with-zlib \
    --enable-bcmath \
    --enable-exif \
    --enable-gd \
    --with-freetype \
    --with-jpeg \
    --with-mysqli \
	${PHP_EXTRA_CONFIGURE_ARGS:-}
make -j "$(nproc)"
find -type f -name '*.a' -delete
make install
find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true
make clean

# imagick
printf "\n" | pecl install imagick-3.4.4
echo "extension=imagick.so" > $PHP_INI_DIR/conf.d/imagick.ini

# memcache
printf "\n" | pecl install memcache-4.0.5.2
echo "extension=memcache.so" > $PHP_INI_DIR/conf.d/memcache.ini

# uploadprogress
printf "\n" | pecl install uploadprogress-1.1.3
echo "extension=uploadprogress.so" > $PHP_INI_DIR/conf.d/uploadprogress.ini

# mcrypt
printf "\n" | pecl install mcrypt-1.0.4
echo "extension=mcrypt.so" > $PHP_INI_DIR/conf.d/mcrypt.ini

echo "zend_extension=opcache" > $PHP_INI_DIR/conf.d/opcache.ini
echo "extension=sodium" > $PHP_INI_DIR/conf.d/sodium.ini

cat <<EOF > $PHP_INI_DIR/conf.d/opcache-recommended.ini
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000
opcache.revalidate_freq=2
opcache.fast_shutdown=1
EOF

cat <<EOF > $PHP_INI_DIR/conf.d/error-logging.ini
error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR
display_errors = Off
display_startup_errors = Off
log_errors = On
error_log = /var/log/apache2/php-error.log
log_errors_max_len = 1024
ignore_repeated_errors = On
ignore_repeated_source = Off
html_errors = Off
EOF

# configure apache
a2enmod rewrite
a2enmod ssl

# wp-cli
curl https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /tmp/wp-cli.phar
chmod 755 /tmp/wp-cli.phar
mv /tmp/wp-cli.phar /usr/local/bin/wp

cat <<EOF > /etc/apache2/sites-available/wordpress.conf
LogFormat "{\"time\":\"%{%Y-%m-%d}tT%{%T}t.%{msec_frac}tZ\", \"process\":\"%D\", \"filename\":\"%f\", \"remoteIP\":\"%a\", \"host\":\"%V\", \"request\":\"%U\", \"query\":\"%q\", \"method\":\"%m\", \"status\":\"%>s\", \"userAgent\":\"%{User-agent}i\", \"referer\":\"%{Referer}i\"}" cloudwatch
ErrorLogFormat "{\"time\":\"%{%usec_frac}t\", \"function\":\"[%-m:%l]\", \"process\":\"[pid%P]\", \"message\":\"%M\"}"

<VirtualHost *:80>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/app/bedrock/web

        LogLevel warn
        ErrorLog /var/log/apache2/error.log
        CustomLog /var/log/apache2/access.log cloudwatch

        RewriteEngine On
        RewriteOptions Inherit

        <Directory /var/www/app/bedrock/web>
            Options -Indexes
            AllowOverride All
            Require all granted
            <IfModule mod_rewrite.c>
                RewriteEngine On
                RewriteBase /
                RewriteRule ^index.php$ - [L]
                RewriteCond %{REQUEST_FILENAME} !-f
                RewriteCond %{REQUEST_FILENAME} !-d
                RewriteRule . /index.php [L]
            </IfModule>
        </Directory>

        AddType application/x-httpd-php .php
        AddType application/x-httpd-php phtml pht php

        php_value memory_limit 128M
        php_value post_max_size 100M
        php_value upload_max_filesize 100M
</VirtualHost>
<VirtualHost *:443>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/app/bedrock/web

        LogLevel warn
        ErrorLog /var/log/apache2/error-ssl.log
        CustomLog /var/log/apache2/access-ssl.log cloudwatch

        RewriteEngine On
        RewriteOptions Inherit

        <Directory /var/www/app/bedrock/web>
            Options -Indexes
            AllowOverride All
            Require all granted
            <IfModule mod_rewrite.c>
                RewriteEngine On
                RewriteBase /
                RewriteRule ^index.php$ - [L]
                RewriteCond %{REQUEST_FILENAME} !-f
                RewriteCond %{REQUEST_FILENAME} !-d
                RewriteRule . /index.php [L]
            </IfModule>
        </Directory>

        AddType application/x-httpd-php .php
        AddType application/x-httpd-php phtml pht php

        # self-signed cert
        # real cert is managed by the ELB
        SSLEngine on
        SSLCertificateFile /etc/ssl/certs/apache-selfsigned.crt
        SSLCertificateKeyFile /etc/ssl/private/apache-selfsigned.key

        php_value memory_limit 128M
        php_value post_max_size 100M
        php_value upload_max_filesize 100M
</VirtualHost>
EOF

a2ensite wordpress

# apache2 will be enabled / started on boot
systemctl disable apache2

# AMI hardening

# Update the AMI tools before using them
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/building-shared-amis.html#public-amis-update-ami-tools
# More details
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/set-up-ami-tools.html
# http://www.dowdandassociates.com/blog/content/howto-install-aws-cli-amazon-elastic-compute-cloud-ec2-ami-tools/
mkdir -p /tmp/aws
mkdir -p /opt/aws
curl https://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip -o /tmp/aws/ec2-ami-tools.zip
unzip -d /tmp/aws /tmp/aws/ec2-ami-tools.zip
mv /tmp/aws/ec2-ami-tools-* /opt/aws/ec2-ami-tools
rm -f /tmp/aws/ec2-ami-tools.zip
cat <<'EOF' > /etc/profile.d/ec2-ami-tools.sh
export EC2_AMITOOL_HOME=/opt/aws/ec2-ami-tools
export PATH=$PATH:$EC2_AMITOOL_HOME/bin
EOF
cat <<'EOF' >> /etc/bash.bashrc

# https://askubuntu.com/a/1139138
if [ -d /etc/profile.d ]; then
  for i in /etc/profile.d/*.sh; do
    if [ -r $i ]; then
      . $i
    fi
  done
  unset i
fi
EOF

# Disable password-based remote logins for root
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/building-shared-amis.html#public-amis-disable-password-logins-for-root
# install ssh...
apt-get -y install ssh
# Default in Ubuntu already is PermitRootLogin prohibit-password...

# Disable local root access
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/building-shared-amis.html#restrict-root-access
passwd -l root

# Remove SSH host key pairs
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/building-shared-amis.html#remove-ssh-host-key-pairs
shred -u /etc/ssh/*_key /etc/ssh/*_key.pub

# Install public key credentials
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/building-shared-amis.html#public-amis-install-credentials
# Default in Ubuntu already does this...

# Disabling sshd DNS checks (optional)
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/building-shared-amis.html#public-amis-disable-ssh-dns-lookups
# Default in Ubuntu already is UseDNS no

# AWS Marketplace Security Checklist
# https://docs.aws.amazon.com/marketplace/latest/userguide/product-and-ami-policies.html#security
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# remove python2.7
apt-get -y remove --purge python2.7
apt-get -y autoremove
ln -s /usr/bin/python3 /usr/bin/python

# apt cleanup
apt-get -y autoremove
apt-get -y update

# https://aws.amazon.com/articles/how-to-share-and-use-public-amis-in-a-secure-manner/
find / -name "authorized_keys" -exec rm -f {} \;
