#!/bin/bash -eux

PHP_INI_DIR=/usr/local/etc/php

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

a2dissite 000-default
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
        DocumentRoot /var/www/app/bedrock/web

        LogLevel warn
        ErrorLog /var/log/apache2/error-ssl.log
        CustomLog /var/log/apache2/access-ssl.log cloudwatch

        RewriteEngine On
        RewriteOptions Inherit

        <Directory /var/www/app/bedrock/web>
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
