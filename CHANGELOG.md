# Unreleased

# 3.0.0

Major modernization release bringing the pattern current with the latest WordPress, devenv tooling, and the Marketplace Catalog API workflow.

**Stack components**

* WordPress 6.9.4 (was 6.7.2)
* Apache 2.4 / PHP 8.1 / Ubuntu 22.04 (unchanged)
* `aws-cdk-lib` 2.225.0 (was 2.120.0)
* `oe-patterns-cdk-common` 4.5.1 (was 4.2.4); EFS elastic throughput defaults from 4.2.4 are retained
* devenv image 2.8.4 (was 2.5.5); requires `--break-system-packages` for pip on Ubuntu 24.04 base
* `aws-marketplace-utilities` packer scripts 1.10.3 (was 1.6.0); fixes silent `--install-efs-utils` failures (rustup PATH under `sudo -E`, missing `cmake` and `golang-go` for `aws-lc-fips-sys` build, explicit `.deb` existence check)

**Breaking changes for existing 2.x deployments**

* AMI parameter renamed `AsgAmiId` → `AsgAmiIdv300`. Existing 2.x stacks cannot be updated in place — a 3.0.0 stack must be deployed fresh.
* Aurora MySQL engine version may be bumped by the upgraded `oe-patterns-cdk-common`; existing stacks should expect a maintenance-window apply.

**New behavior**

* Versioned AMI parameter convention introduced (`NEXT_RELEASE_PREFIX = "v300"`, `ami_id_param_name_suffix` on `Asg`) so each release has a distinct parameter name and CloudFormation can't silently reuse the prior AMI.
* AWS Marketplace submission flow ready for the Catalog API (`make marketplace-validate` / `marketplace-submit` / `marketplace-status`); pattern publishing is no longer driven by the deprecated `plf_config.yaml` spreadsheet flow.
* `test/integration/` playwright scaffold added; `make test-integration` runs an end-to-end smoke test (install wizard → admin login → Gutenberg post → public render) against the deployed dev stack.
* Packer appinstall script now sets `set -eux` explicitly so provisioning failures abort the build instead of silently shipping a broken AMI (packer's `execute_command` invokes the script as `bash <path>`, which treats the shebang as a comment).
* `docker-compose.yml` now mounts `~/.aws` and forwards `AWS_PROFILE`, matching the Mastodon/Drupal patterns; previously this repo required exporting individual `AWS_*` vars.

**Removed / cleanup**

* Dropped dead `DEFAULT_WORDPRESS_SOURCE_URL` constant from `wordpress_stack.py`. The pre-2.0.0 CodePipeline + CodeDeploy + Lambda seed-bucket flow was removed in 2.0.0; the constant lingered but was never read. Pattern install path is now the AMI-baked WordPress copied to EFS at first boot.
* Stripped stale `PipelineArtifactBucketName` / `SourceArtifactBucketName` / `SourceArtifactObjectKey` parameters from `test/.taskcat.yml` and `test/main-test/.taskcat.yml` — leftover from the same pre-2.0.0 pipeline flow.
* Folded the previously unreleased work (WordPress 6.8.1, EFS permission fixes, root volume size increase, oe-patterns-cdk-common 4.2.4) into this release.

# 2.1.0

* Use v4 of upload-artifact github action
* Upgrade to WordPress 6.7.2
* Require DNS Parameters
* Fix loopback errors when restricting ALB CIDR
* Fix tests again
* Upgrade to Docker Compose V2
* Support SFTP via NLB
* Upgrade oe-patterns-cdk-common to 4.2.0
* Add AsgAmiId param for self-service marketplace support

# 2.0.0

* fix region tests
* fix tests
* Upgrade oe-patterns-cdk-common to 3.20.2
* Upgrade MySQL Aurora database to 8.0 *causes downtime during deployment*
* Upgrade OE devenv to 2.5.3 *updates pricing*
* Use stock WordPress instead of Bedrock - moved Bedrock to new pattern
* Use WordPress 6.6.1

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
