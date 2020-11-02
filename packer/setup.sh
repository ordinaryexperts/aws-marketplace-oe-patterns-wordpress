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

# custom php ppa
add-apt-repository ppa:ondrej/php
apt-get update

# install apache and php
apt-get -y install            \
        apache2               \
        libapache2-mod-php7.4 \
        mysql-client-5.7      \
        mysql-client-core-5.7 \
        nfs-common            \
        php-mysql             \
        php7.4                \
        php7.4-apcu           \
        php7.4-cgi            \
        php7.4-curl           \
        php7.4-dev            \
        php7.4-fpm            \
        php7.4-gd             \
        php7.4-mbstring       \
        php7.4-xml            \
        zlib1g-dev

# memcache
printf "\n" | pecl install memcache
echo "extension=memcache.so" > /etc/php/7.4/apache2/conf.d/20-memcache.ini
echo "extension=memcache.so" > /etc/php/7.4/cli/conf.d/20-memcache.ini

# uploadprogress
printf "\n" | pecl install uploadprogress
echo "extension=uploadprogress.so" > /etc/php/7.4/apache2/conf.d/20-uploadprogress.ini
echo "extension=uploadprogress.so" > /etc/php/7.4/cli/conf.d/20-uploadprogress.ini

# configure apache
a2enmod php7.4
a2enmod rewrite
a2enmod ssl

a2dissite 000-default
mkdir -p /var/www/app/wordpress
cat <<EOF > /etc/apache2/sites-available/wordpress.conf
LogFormat "{\"time\":\"%{%Y-%m-%d}tT%{%T}t.%{msec_frac}tZ\", \"process\":\"%D\", \"filename\":\"%f\", \"remoteIP\":\"%a\", \"host\":\"%V\", \"request\":\"%U\", \"query\":\"%q\", \"method\":\"%m\", \"status\":\"%>s\", \"userAgent\":\"%{User-agent}i\", \"referer\":\"%{Referer}i\"}" cloudwatch
ErrorLogFormat "{\"time\":\"%{%usec_frac}t\", \"function\":\"[%-m:%l]\", \"process\":\"[pid%P]\", \"message\":\"%M\"}"

<VirtualHost *:80>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/app/wordpress

        LogLevel warn
        ErrorLog /var/log/apache2/error.log
        CustomLog /var/log/apache2/access.log cloudwatch

        RewriteEngine On
        RewriteOptions Inherit

        <Directory /var/www/app/wordpress>
            Options Indexes FollowSymLinks MultiViews
            AllowOverride All
            Require all granted
        </Directory>

        AddType application/x-httpd-php .php
        AddType application/x-httpd-php phtml pht php

        php_value memory_limit 128M
        php_value post_max_size 100M
        php_value upload_max_filesize 100M
</VirtualHost>
<VirtualHost *:443>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/app/wordpress

        LogLevel warn
        ErrorLog /var/log/apache2/error-ssl.log
        CustomLog /var/log/apache2/access-ssl.log cloudwatch

        RewriteEngine On
        RewriteOptions Inherit

        <Directory /var/www/app/wordpress>
            Options Indexes FollowSymLinks MultiViews
            AllowOverride All
            Require all granted
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

# apt cleanup
apt-get -y autoremove
apt-get -y update

# https://aws.amazon.com/articles/how-to-share-and-use-public-amis-in-a-secure-manner/
find / -name "authorized_keys" -exec rm -f {} \;
