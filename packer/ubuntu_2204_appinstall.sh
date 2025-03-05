#!/bin/bash -eux

SCRIPT_VERSION=1.6.0
SCRIPT_PREINSTALL=ubuntu_2204_2404_preinstall.sh
SCRIPT_POSTINSTALL=ubuntu_2204_2404_postinstall.sh

# preinstall steps
curl -O "https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/$SCRIPT_VERSION/packer_provisioning_scripts/$SCRIPT_PREINSTALL"
chmod +x $SCRIPT_PREINSTALL
./$SCRIPT_PREINSTALL --install-efs-utils
rm $SCRIPT_PREINSTALL

# start WordPress specific stuff
apt-get update && apt-get -y upgrade
apt-get install -y --no-install-recommends \
    acl \
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
echo "msmtp msmtp/apparmor boolean false" | debconf-set-selections
apt-get install -y msmtp msmtp-mta

apt-get install -y --no-install-recommends apache2
a2dissite 000-default
rm -rvf /var/www/html
a2dismod mpm_event && a2enmod mpm_prefork

apt-get install -y libapache2-mod-php php-curl php-intl php-mysql php-xml php-zip php-mbstring
apt-get install -y php-imagick php-memcache php-uploadprogress

cat <<EOF > /etc/php/8.1/apache2/conf.d/opcache-recommended.ini
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000
opcache.revalidate_freq=2
opcache.fast_shutdown=1
EOF

cat <<EOF > /etc/php/8.1/apache2/conf.d/error-logging.ini
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

WORDPRESS_VERSION=6.7.2

# download WordPress
curl https://wordpress.org/wordpress-$WORDPRESS_VERSION.zip -o /root/wordpress-$WORDPRESS_VERSION.zip
unzip /root/wordpress-$WORDPRESS_VERSION.zip -d /root
# remove unused plugins
rm /root/wordpress/wp-content/plugins/hello.php
rm -rf /root/wordpress/wp-content/plugins/akismet
# remove unused themes
rm -rf /root/wordpress/wp-content/themes/twentytwentythree
rm -rf /root/wordpress/wp-content/themes/twentytwentyfour
# upgrade folder
mkdir -p /root/wordpress/wp-content/upgrade
chown -R www-data:www-data /root/wordpress

# wp-cli
curl https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /tmp/wp-cli.phar
chmod 755 /tmp/wp-cli.phar
mv /tmp/wp-cli.phar /usr/local/bin/wp

pip install boto3
cat <<EOF > /root/check-secrets.py
#!/usr/bin/env python3

import boto3
import json
import subprocess
import sys
import uuid

region_name = sys.argv[1]
arn = sys.argv[2]

client = boto3.client("secretsmanager", region_name=region_name)
response = client.get_secret_value(
  SecretId=arn
)
current_secret = json.loads(response["SecretString"])
needs_update = False

if 'password' in current_secret:
    needs_update = True
    del current_secret['password']
if 'username' in current_secret:
    needs_update = True
    del current_secret['username']
NEEDED_SECRETS_WITH_SIMILAR_REQUIREMENTS = [
    "AUTH_KEY",
    "SECURE_AUTH_KEY",
    "LOGGED_IN_KEY",
    "NONCE_KEY",
    "AUTH_SALT",
    "SECURE_AUTH_SALT",
    "LOGGED_IN_SALT",
    "NONCE_SALT"
]
for secret in NEEDED_SECRETS_WITH_SIMILAR_REQUIREMENTS:
  if not secret in current_secret:
    needs_update = True
    cmd = "random_value=\$(seed=\$(date +%s%N); tr -dc '[:alnum:]' < /dev/urandom | head -c 32; echo \$seed | sha256sum | awk '{print substr(\$1, 1, 32)}'); echo \$random_value"
    output = subprocess.run(cmd, stdout=subprocess.PIPE, shell=True).stdout.decode('utf-8').strip()
    current_secret[secret] = output
if needs_update:
  client.update_secret(
    SecretId=arn,
    SecretString=json.dumps(current_secret)
  )
else:
  print('Secrets already generated - no action needed.')
EOF
chown root:root /root/check-secrets.py
chmod 744 /root/check-secrets.py

cat <<EOF > /etc/apache2/sites-available/wordpress.conf
LogFormat "{\"time\":\"%{%Y-%m-%d}tT%{%T}t.%{msec_frac}tZ\", \"process\":\"%D\", \"filename\":\"%f\", \"remoteIP\":\"%a\", \"host\":\"%V\", \"request\":\"%U\", \"query\":\"%q\", \"method\":\"%m\", \"status\":\"%>s\", \"userAgent\":\"%{User-agent}i\", \"referer\":\"%{Referer}i\"}" cloudwatch
ErrorLogFormat "{\"time\":\"%{%usec_frac}t\", \"function\":\"[%-m:%l]\", \"process\":\"[pid%P]\", \"message\":\"%M\"}"

<VirtualHost *:80>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/wordpress

        LogLevel warn
        ErrorLog /var/log/apache2/error.log
        CustomLog /var/log/apache2/access.log cloudwatch

        RewriteEngine On
        RewriteOptions Inherit

        <Directory /var/www/wordpress>
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
        DocumentRoot /var/www/wordpress

        LogLevel warn
        ErrorLog /var/log/apache2/error-ssl.log
        CustomLog /var/log/apache2/access-ssl.log cloudwatch

        RewriteEngine On
        RewriteOptions Inherit

        <Directory /var/www/wordpress>
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

# wordpress user
groupadd -g 2000 wordpress
useradd \
  --create-home \
  --home /home/wordpress \
  --comment "WordPress User" \
  --uid 2000 \
  --gid wordpress \
  --shell /bin/bash \
  wordpress

sed -i 's|^Subsystem\s\+sftp\s\+.*|Subsystem sftp internal-sftp|' /etc/ssh/sshd_config
sed -i '/^Subsystem.*internal-sftp/a \
Match User wordpress\n\tChrootDirectory /mnt/efs\n\tForceCommand internal-sftp\n\tX11Forwarding no\n\tAllowTcpForwarding no\n' /etc/ssh/sshd_config

# Add wordpress to www-data group
usermod -aG www-data wordpress

mkdir /home/wordpress/.ssh
chmod 700 /home/wordpress/.ssh
chown wordpress:wordpress /home/wordpress/.ssh

a2ensite wordpress

# apache2 will be enabled / started on boot
systemctl disable apache2

# post install steps
curl -O "https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/$SCRIPT_VERSION/packer_provisioning_scripts/$SCRIPT_POSTINSTALL"
chmod +x "$SCRIPT_POSTINSTALL"
./"$SCRIPT_POSTINSTALL"
rm $SCRIPT_POSTINSTALL
