# Unreleased

# 1.4.1

* linting cleanup
* Add additional documentation regarding IAM resources
* ignore plf*.xlsx

# 1.4.0

* New rsync approach for CodeDeploy to minimize downtime
* Upgrade CDK to 2.44.0
* Upgrade MySQL Aurora to 5.7.mysql_aurora.2.11.1
* Switch to OE common CDK constructs
* Switch to Ubuntu 22.04
* SES SMTP email integration
* Upgrade to PHP 8.1
* Upgrade default WP Bedrock install to 6.2.2
* Smaller default instance sizes
* Add PHP intl extension

# 1.3.0

* Lifecycle management support for EFS
* AWS Backup support for EFS
* Parameterize RDS backup retention period
* Use common make targets
* Upgrade CDK to 1.137.0
* Upgrade oe-patterns-cdk-common to 2.0.2
* Upgrade devenv nodejs to 14.x
* Upgrade taskcat to 0.9.29
* Upgrade default WP Bedrock install to 5.8

# 1.2.0

* Updating packages to resolve CVE-2021-3177
* Fix expired cert for dev account

# 1.1.0

* Add AppAsgKeyName for optional SSH access
* Update descriptions and tags
* Add option to restrict IP CIDR on ALB SG

# 1.0.0

* Initial development
* Remove CloudFront
* Remove ElastiCache
* Upgrade CDK to 1.83.0
* Require ACM Certificate
* Taskcat testing setup
