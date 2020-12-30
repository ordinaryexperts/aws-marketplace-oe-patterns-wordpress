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
            "log_group_name": "${WordPressSystemLogGroup}",
            "log_stream_name": "{instance_id}-/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/dpkg.log",
            "log_group_name": "${WordPressSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/dpkg.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/apt/history.log",
            "log_group_name": "${WordPressSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/apt/history.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init.log",
            "log_group_name": "${WordPressSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/cloud-init.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "${WordPressSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/cloud-init-output.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "${WordPressSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/auth.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "${WordPressSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/syslog",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/amazon/ssm/amazon-ssm-agent.log",
            "log_group_name": "${WordPressSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/amazon/ssm/amazon-ssm-agent.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/amazon/ssm/errors.log",
            "log_group_name": "${WordPressSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/amazon/ssm/errors.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/wordpress-cache.log",
            "log_group_name": "${WordPressSystemLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/wordpress-cache.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/apache2/access.log",
            "log_group_name": "${WordPressAccessLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/apache2/access.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/apache2/error.log",
            "log_group_name": "${WordPressErrorLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/apache2/error.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/apache2/access-ssl.log",
            "log_group_name": "${WordPressAccessLogGroup}",
            "log_stream_name": "{instance_id}-/var/log/apache2/access-ssl.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/apache2/error-ssl.log",
            "log_group_name": "${WordPressErrorLogGroup}",
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

# efs
mkdir /mnt/efs
mount -t efs "${AppEfs}":/ /mnt/efs
echo "${AppEfs}:/ /mnt/efs efs _netdev 0 0" >> /etc/fstab
mkdir -p /mnt/efs/wordpress/files
chown www-data /mnt/efs/wordpress/files

mkdir -p /opt/oe/patterns/wordpress

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

# database values
jq -n --arg host "${DbCluster.Endpoint.Address}" --arg port "${DbCluster.Endpoint.Port}" \
   '{host: $host, port: $port}' > /opt/oe/patterns/wordpress/db.json

# db connect helper
cat <<'EOF' > /usr/local/bin/connect-to-db
#!/usr/bin/env bash

host=`jq -r '.host' /opt/oe/patterns/wordpress/db.json`
port=`jq -r '.port' /opt/oe/patterns/wordpress/db.json`
username=`jq -r '.username' /opt/oe/patterns/wordpress/secret.json`
password=`jq -r '.password' /opt/oe/patterns/wordpress/secret.json`

mysql -u $username -P $port -h $host --password=$password wordpress
EOF
chmod 755 /usr/local/bin/connect-to-db

echo "" >> /etc/apache2/envvars

echo "export DB_NAME=wordpress" >> /etc/apache2/envvars
echo "export DB_USER=`jq -r '.username' /opt/oe/patterns/wordpress/secret.json`" >> /etc/apache2/envvars
echo "export DB_PASSWORD=`jq -r '.password' /opt/oe/patterns/wordpress/secret.json`" >> /etc/apache2/envvars
echo "export DB_HOST=${DbCluster.Endpoint.Address}" >> /etc/apache2/envvars

echo "" >> /etc/apache2/envvars

echo "export WP_ENV=production" >> /etc/apache2/envvars
echo "export WP_HOME=${WordPressHome}" >> /etc/apache2/envvars
echo "export WP_SITEURL=${WordPressHome}/wp" >> /etc/apache2/envvars

echo "" >> /etc/apache2/envvars

PREFIX="${Prefix}"
function write_apache_env() {
    KEY="${!PREFIX}_$1"
    VALUE=`aws secretsmanager get-secret-value --secret-id $KEY | jq '.SecretString | fromjson | .value' | sed "s/\"/'/g"`
    echo "export $1=$VALUE" >> /etc/apache2/envvars
}
write_apache_env "AUTH_KEY"
write_apache_env "AUTH_SALT"
write_apache_env "LOGGED_IN_KEY"
write_apache_env "LOGGED_IN_SALT"
write_apache_env "NONCE_KEY"
write_apache_env "NONCE_SALT"
write_apache_env "SECURE_AUTH_KEY"
write_apache_env "SECURE_AUTH_SALT"

# elasticache values
if [[ "${ElastiCacheEnable}" == "true" ]]
then
    jq -n --arg host "${ElastiCacheClusterHost}" --arg port "${ElastiCacheClusterPort}" \
       '{host: $host, port: $port}' > /opt/oe/patterns/wordpress/elasticache.json
fi

# cloudfront values
if [[ "${CloudFrontEnable}" == "true" ]]
then
    jq -n --arg host "${CloudFrontHost}" '{host: $host}' > /opt/oe/patterns/wordpress/cloudfront.json
fi

# apache
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/ssl/private/apache-selfsigned.key \
  -out /etc/ssl/certs/apache-selfsigned.crt \
  -subj '/CN=localhost'
systemctl enable apache2 && systemctl start apache2

cfn-signal --exit-code $? --stack ${AWS::StackName} --resource AppAsg --region ${AWS::Region}
