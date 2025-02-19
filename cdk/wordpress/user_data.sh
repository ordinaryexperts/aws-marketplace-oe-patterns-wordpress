#!/bin/bash

# aws cloudwatch
cat <<EOF > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root",
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "metrics": {
    "metrics_collected": {
      "collectd": {
        "metrics_aggregation_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      }
    },
    "append_dimensions": {
      "ImageId": "\${!aws:ImageId}",
      "InstanceId": "\${!aws:InstanceId}",
      "InstanceType": "\${!aws:InstanceType}",
      "AutoScalingGroupName": "\${!aws:AutoScalingGroupName}"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/dpkg.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/dpkg.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/apt/history.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/apt/history.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/cloud-init.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/cloud-init-output.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/auth.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/syslog",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/amazon/ssm/amazon-ssm-agent.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/amazon/ssm/amazon-ssm-agent.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/amazon/ssm/errors.log",
            "log_group_name": "${AsgSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/amazon/ssm/errors.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/wordpress-cache.log",
            "log_group_name": "${AsgAppLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/wordpress-cache.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/apache2/access.log",
            "log_group_name": "${AsgAppLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/apache2/access.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/apache2/error.log",
            "log_group_name": "${AsgAppLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/apache2/error.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/apache2/access-ssl.log",
            "log_group_name": "${AsgAppLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/apache2/access-ssl.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/apache2/error-ssl.log",
            "log_group_name": "${AsgAppLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/apache2/error-ssl.log",
            "timezone": "UTC"
          }
        ]
      }
    },
    "log_stream_name": "{instance_id}"
  }
}
EOF
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

/root/check-secrets.py ${AWS::Region} ${SecretArn}

mkdir -p /opt/oe/patterns/wordpress
aws ssm get-parameter \
    --name "/aws/reference/secretsmanager/${InstanceSecretName}" \
    --with-decryption \
    --query Parameter.Value \
| jq -r . > /opt/oe/patterns/instance.json

ACCESS_KEY_ID=$(cat /opt/oe/patterns/instance.json | jq -r .access_key_id)
SECRET_ACCESS_KEY=$(cat /opt/oe/patterns/instance.json | jq -r .secret_access_key)
SMTP_PASSWORD=$(cat /opt/oe/patterns/instance.json | jq -r .smtp_password)

aws ssm get-parameter \
    --name "/aws/reference/secretsmanager/${InstanceSecretName}" \
    --with-decryption \
    --query Parameter.Value \
| jq -r . > /opt/oe/patterns/instance.json

# secretsmanager
SECRET_ARN="${SecretArn}"
echo $SECRET_ARN >> /opt/oe/patterns/wordpress/secret-arn.txt

SECRET_NAME=$(aws secretsmanager list-secrets --query "SecretList[?ARN=='$SECRET_ARN'].Name" --output text)
echo $SECRET_NAME >> /opt/oe/patterns/wordpress/secret-name.txt

aws ssm get-parameter \
    --name "/aws/reference/secretsmanager/$SECRET_NAME" \
    --with-decryption \
    --query Parameter.Value \
| jq -r . >> /opt/oe/patterns/wordpress/secret.json

DB_SECRET_ARN="${DbSecretArn}"
echo $DB_SECRET_ARN >> /opt/oe/patterns/wordpress/db-secret-arn.txt

DB_SECRET_NAME=$(aws secretsmanager list-secrets --query "SecretList[?ARN=='$DB_SECRET_ARN'].Name" --output text)
echo $DB_SECRET_NAME >> /opt/oe/patterns/wordpress/db-secret-name.txt

aws ssm get-parameter \
    --name "/aws/reference/secretsmanager/$DB_SECRET_NAME" \
    --with-decryption \
    --query Parameter.Value \
| jq -r . >> /opt/oe/patterns/wordpress/db-secret.json

# database values
jq -n --arg host "${DbCluster.Endpoint.Address}" --arg port "${DbCluster.Endpoint.Port}" \
   '{host: $host, port: $port}' > /opt/oe/patterns/wordpress/db.json

# efs
mkdir /mnt/efs
echo "${AppEfs}:/ /mnt/efs efs _netdev 0 0" >> /etc/fstab
mount -a

# initialize wordpress copy
if [ ! -f /mnt/efs/wordpress/wp-config.php ]; then
  cp -a /root/wordpress /mnt/efs
  echo "Initial WordPress files copied..."
fi
rm -f /var/www/wordpress
ln -s /mnt/efs/wordpress /var/www/wordpress
echo "WordPress symlink created."

DB_USER=$(jq -r '.username' /opt/oe/patterns/wordpress/db-secret.json)
DB_PASSWORD=$(jq -r '.password' /opt/oe/patterns/wordpress/db-secret.json)
DB_HOST=$(jq -r '.host' /opt/oe/patterns/wordpress/db.json)
DB_PORT=$(jq -r '.port' /opt/oe/patterns/wordpress/db.json)

AUTH_KEY=$(jq -r '.AUTH_KEY' /opt/oe/patterns/wordpress/secret.json)
SECURE_AUTH_KEY=$(jq -r '.SECURE_AUTH_KEY' /opt/oe/patterns/wordpress/secret.json)
LOGGED_IN_KEY=$(jq -r '.LOGGED_IN_KEY' /opt/oe/patterns/wordpress/secret.json)
NONCE_KEY=$(jq -r '.NONCE_KEY' /opt/oe/patterns/wordpress/secret.json)
AUTH_SALT=$(jq -r '.AUTH_SALT' /opt/oe/patterns/wordpress/secret.json)
SECURE_AUTH_SALT=$(jq -r '.SECURE_AUTH_SALT' /opt/oe/patterns/wordpress/secret.json)
LOGGED_IN_SALT=$(jq -r '.LOGGED_IN_SALT' /opt/oe/patterns/wordpress/secret.json)
NONCE_SALT=$(jq -r '.NONCE_SALT' /opt/oe/patterns/wordpress/secret.json)

# custom config
CUSTOM_CONFIG="// no custom config defined"
if [[ "${CustomWpConfigParameterArn}" != "" ]]; then
    CUSTOM_CONFIG_TITLE="// custom config fetched from ${CustomWpConfigParameterArn}"
    CUSTOM_CONFIG_VALUE=$(aws ssm get-parameter --name "${CustomWpConfigParameterArn}" --with-decryption --output text --query Parameter.Value)
    CUSTOM_CONFIG=$(printf "%s\n\n%s" "$CUSTOM_CONFIG_TITLE" "$CUSTOM_CONFIG_VALUE")
fi

WP_CONFIG_FILE="/var/www/wordpress/wp-config.php"

if [ -f "$WP_CONFIG_FILE" ]; then
  # wp-config.php exists, replace the custom config block
  sed -i "/\/\* START: OE PATTERN CUSTOM CONFIG FROM PARAMETER STORE \*/,/\/\* END: OE PATTERN CUSTOM CONFIG FROM PARAMETER STORE \*/c\/* START: OE PATTERN CUSTOM CONFIG FROM PARAMETER STORE */\n$CUSTOM_CONFIG\n/* END: OE PATTERN CUSTOM CONFIG FROM PARAMETER STORE */" "$WP_CONFIG_FILE"
else
  cat <<EOF > "$WP_CONFIG_FILE"
<?php
/**
 * The base configuration for WordPress
 *
 * IMPORTANT: This file is automatically regenerated at first instance boot.
 *
 * This file contains the following configurations:
 *
 * * Database settings
 * * Secret keys
 * * Database table prefix
 * * ABSPATH
 *
 * @link https://developer.wordpress.org/advanced-administration/wordpress/wp-config/
 *
 * @package WordPress
 */

// ** Database settings ** //
/** The name of the database for WordPress */
define( 'DB_NAME', 'wordpress' );

/** Database username */
define( 'DB_USER', '$DB_USER' );

/** Database password */
define( 'DB_PASSWORD', '$DB_PASSWORD' );

/** Database hostname */
define( 'DB_HOST', '$DB_HOST' );

/** Database charset to use in creating database tables. */
define( 'DB_CHARSET', 'utf8' );

/** The database collate type. Don't change this if in doubt. */
define( 'DB_COLLATE', '' );

/**#@+
 * Authentication unique keys and salts.
 *
 * Change these to different unique phrases! You can generate these using
 * the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}.
 *
 * You can change these at any point in time to invalidate all existing cookies.
 * This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
define( 'AUTH_KEY',         '$AUTH_KEY' );
define( 'SECURE_AUTH_KEY',  '$SECURE_AUTH_KEY' );
define( 'LOGGED_IN_KEY',    '$LOGGED_IN_KEY' );
define( 'NONCE_KEY',        '$NONCE_KEY' );
define( 'AUTH_SALT',        '$AUTH_SALT' );
define( 'SECURE_AUTH_SALT', '$SECURE_AUTH_SALT' );
define( 'LOGGED_IN_SALT',   '$LOGGED_IN_SALT' );
define( 'NONCE_SALT',       '$NONCE_SALT' );

/**#@-*/

/**
 * WordPress database table prefix.
 *
 * You can have multiple installations in one database if you give each
 * a unique prefix. Only numbers, letters, and underscores please!
 */
\$table_prefix = 'wp_';

/* START: OE PATTERN CUSTOM CONFIG FROM PARAMETER STORE */
$CUSTOM_CONFIG
/* END: OE PATTERN CUSTOM CONFIG FROM PARAMETER STORE */

/* Add any custom values between this line and the "stop editing" line. */



/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if ( ! defined( 'ABSPATH' ) ) {
        define( 'ABSPATH', __DIR__ . '/' );
}

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';
EOF
fi

# configure sftp key
cp /home/ubuntu/.ssh/authorized_keys /home/wordpress/.ssh/
chmod 600 /home/wordpress/.ssh/authorized_keys
chown wordpress:wordpress /home/wordpress/.ssh/authorized_keys

# Permissions
chown -R www-data:www-data /mnt/efs/wordpress
find /mnt/efs/wordpress -type d -exec chmod 2775 {} \;
find /mnt/efs/wordpress -type f -exec chmod 664 {} \;
find /mnt/efs/wordpress -type d -exec chmod g+s {} \;
setfacl -R -m g:www-data:rwx /mnt/efs/wordpress
setfacl -R -m d:g:www-data:rwx /mnt/efs/wordpress
echo "umask 0002" >> /home/wordpress/.bashrc
grep -qxF 'umask 0002' /etc/apache2/envvars || echo 'umask 0002' >> /etc/apache2/envvars

# db connect helper
cat <<'EOF' > /usr/local/bin/connect-to-db
#!/usr/bin/env bash

host=`jq -r '.host' /opt/oe/patterns/wordpress/db.json`
port=`jq -r '.port' /opt/oe/patterns/wordpress/db.json`
username=`jq -r '.username' /opt/oe/patterns/wordpress/db-secret.json`
password=`jq -r '.password' /opt/oe/patterns/wordpress/db-secret.json`

mysql -u $username -P $port -h $host --password=$password wordpress
EOF
chmod 755 /usr/local/bin/connect-to-db

# apache
DNS_HOSTNAME_TRUNCATED=$(echo "${DnsHostname}" | cut -c1-64)
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/ssl/private/apache-selfsigned.key \
  -out /etc/ssl/certs/apache-selfsigned.crt \
  -subj '/CN=$DNS_HOSTNAME_TRUNCATED'
cp /etc/ssl/certs/apache-selfsigned.crt /usr/local/share/ca-certificates/
update-ca-certificates

# ses msmtp setup
cat <<EOF > /etc/msmtprc
defaults
tls on
tls_starttls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
syslog on

account default
host email-smtp.${AWS::Region}.amazonaws.com
port 587
auth on
user $ACCESS_KEY_ID
password $SMTP_PASSWORD
from no-reply@${HostedZoneName}
EOF

HOST_ENTRY="${DnsHostname}"
if ! grep -q "127.0.0.1.*$HOST_ENTRY" /etc/hosts; then
    sed -i "/127.0.0.1/s/$/ $HOST_ENTRY/" /etc/hosts
fi

systemctl enable apache2 && systemctl start apache2

cfn-signal --exit-code $? --stack ${AWS::StackName} --resource Asg --region ${AWS::Region}
