# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AWS Marketplace pattern that deploys a production-ready WordPress site via CloudFormation/CDK. The product consists of:

1. **Custom AMI** built with Packer (Ubuntu 22.04 with Apache + PHP 8.1 + WordPress pre-installed at `/root/wordpress`)
2. **CDK Infrastructure** (Python) that synthesizes to CloudFormation
3. **Marketplace listing** — currently `plf_config.yaml` (deprecated); new releases should use `marketplace_config.yaml` consumed by `scripts/marketplace.py` in the devenv image (see Upgrade Workflow)

The infrastructure deploys: VPC, ALB, Auto Scaling Group, Aurora MySQL, EFS (shared `wp-content`), SES (msmtp), Route53/ACM, optional NLB-fronted SFTP, and supporting services (IAM, Secrets Manager, SSM).

## Upgrade Workflow

For upgrading the upstream WordPress version, follow [aws-marketplace-utilities/UPGRADE.md](../aws-marketplace-utilities/UPGRADE.md). WordPress-specific notes that supplement that doc:

- Install method is **direct download** (`curl https://wordpress.org/wordpress-$VERSION.zip`) — no Docker base image, no source build. Look up the latest version via the upstream tags: `gh api repos/WordPress/WordPress/tags --jq '.[0:5][].name'` (WordPress doesn't publish GitHub Releases, so use tags).
- The version variable lives in `packer/ubuntu_2204_appinstall.sh` as `WORDPRESS_VERSION=`.
- The packer script removes the `hello.php` plugin, the `akismet` plugin, and the `twentytwentythree` / `twentytwentyfour` themes after extraction. When jumping major WordPress versions, update the bundled-theme deletions to match (e.g., add `twentytwentyfive`).
- WordPress is **baked into the AMI** at `/root/wordpress` and copied to EFS (`/mnt/efs/wordpress`) on first boot if `wp-config.php` doesn't already exist there. Existing deployments are NOT auto-upgraded by an AMI swap — admins must update WordPress through the WP admin UI or by SSH'ing in and running `wp core update`.
- Default WordPress codebase repo: `ordinaryexperts/aws-marketplace-oe-patterns-wordpress-default` (separate repo, default branch `develop`). It still uses Bedrock-style layout from before pattern 2.0.0 dropped Bedrock; the stack's `DEFAULT_WORDPRESS_SOURCE_URL` constant is currently dead code (defined but no `CfnParameter` reads it). Decide per release whether to (a) re-tag the default repo to match the new WP version, (b) wire it up as a parameter like Drupal's `InitializeDefaultDrupal=true` flow, or (c) delete the dead constant entirely.

## Development Environment

All development runs through docker-compose; do not run CDK, Packer, or pip directly on the host.

- `devenv` service — CDK, AWS CLI, Python, taskcat, marketplace.py
- `ami` service — Packer for AMI builds

The `~/.aws` directory is mounted; use `AWS_PROFILE=oe-patterns-dev make <target>` (or export the var).

## Common Commands

### Build / setup
- `make build` / `make rebuild` — devenv Docker image
- `make bash` — interactive shell in devenv
- `make update-common` — pulls `common.mk` from `aws-marketplace-utilities` (currently pinned to `1.6.0` in the Makefile; bump on upgrade)

### CDK
- `make synth` / `make synth-to-file` — emit CloudFormation
- `make diff` / `make deploy` / `make destroy` — dev-account stack lifecycle
- `make lint`

### AMI / Marketplace (after `common.mk` is upgraded to a recent utilities release)
- `AWS_PROFILE=oe-patterns-dev make ami-ec2-build TEMPLATE_VERSION=<v>` — dev AMI
- `AWS_PROFILE=oe-patterns-prod make ami-ec2-build TEMPLATE_VERSION=<v>` — prod AMI for Marketplace ingestion
- `AWS_PROFILE=oe-patterns-prod make marketplace-validate` / `marketplace-submit` / `marketplace-status` — replaces the old PLF flow; requires `marketplace_config.yaml`
- `AWS_PROFILE=oe-patterns-dev make publish TEMPLATE_VERSION=<v>` — publish CFN template to S3
- `AWS_PROFILE=oe-patterns-dev make publish-diagram TEMPLATE_VERSION=<v>`

### Testing
- `make test-main` — taskcat regression run (`test/main-test/.taskcat.yml`, region `us-east-1`)

### Old PLF flow (deprecated, only present in this repo until `marketplace_config.yaml` is introduced)
- `make gen-plf` / `make plf` — Excel/CSV-based product update; superseded by `marketplace.py`

## Architecture

### CDK stack — `cdk/wordpress/wordpress_stack.py`

Composed from `oe_patterns_cdk_common` constructs:

1. `Vpc` — create-or-reference
2. `Dns` — Route53 (parameters required)
3. `Ses` — SES domain identity + SMTP (msmtp on the instance)
4. `Secret` (named `WordPress`) — auth keys/salts; the instance runs `/root/check-secrets.py` on boot to populate any missing salts
5. `DbSecret` + `AuroraMysql` — Aurora MySQL cluster, `database_name="wordpress"`
6. `Asg` — uses `cdk/wordpress/user_data.sh` (rolling update on; not Graviton; default `m5.large`)
7. `Alb` — HTTPS via ACM cert
8. `Efs` — shared mount at `/mnt/efs`; WordPress lives at `/mnt/efs/wordpress`, symlinked into Apache's docroot at `/var/www/wordpress`
9. **Optional SFTP path** — NLB on port 22 + dedicated `wordpress` Linux user (uid 2000) chrooted to `/mnt/efs` via `internal-sftp`. Toggled by the `EnableSftp` parameter; auth uses the same key pair as `AsgKeyName`.

### user_data.sh

Runs on each boot:
1. Writes the CloudWatch agent config and starts it
2. Generates missing WordPress salts via `check-secrets.py`
3. Pulls DB + app secrets from Secrets Manager via SSM parameter store integration
4. Mounts EFS, copies the AMI-baked WordPress into EFS on first boot, symlinks `/var/www/wordpress`
5. Writes / patches `wp-config.php` — including a fenced custom-config block populated from the SSM Parameter referenced by `CustomWpConfigParameterArn`
6. Configures msmtp (SES), self-signed Apache cert, SFTP user authorized_keys
7. Starts Apache, signals CloudFormation

The `CustomWpConfigParameterArn` flow lets users inject PHP into `wp-config.php` via an SSM Secure String. Changes only take effect when `AsgReprovisionString` is bumped (forces ASG instance replacement).

### Default WordPress codebase

`DEFAULT_WORDPRESS_SOURCE_URL` constant at the top of `wordpress_stack.py` references the `aws-marketplace-oe-patterns-wordpress-default` repo's tagged ZIP in S3. **It is not currently wired to any parameter** — the AMI-baked WordPress is what's used. Follow the Drupal pattern (`InitializeDefaultDrupal` + `DefaultDrupalSourceUrl`) if you want to expose this as a customer-facing seed source.

## Patterns / conventions

### Version management
`TEMPLATE_VERSION` env var → `git describe` → `"CICD"` fallback (top of `wordpress_stack.py`).

### Versioned AMI parameter (per utilities UPGRADE.md 2.3.1)
This repo currently uses bare `AsgAmiId`. On the next release, introduce `NEXT_RELEASE_PREFIX = "vXYZ"` (dots stripped) and pass `ami_id_param_name_suffix=NEXT_RELEASE_PREFIX` to the `Asg(...)` construct so customers force a real AMI swap on upgrade. Requires `oe-patterns-cdk-common >= 4.2.6`.

### Secrets management
- WordPress salts → `Secret` construct + `check-secrets.py` self-heals missing keys
- DB credentials → `DbSecret` construct
- SES SMTP password → generated by `lambda_generate_smtp_password.py` in the common library

### Tags / CHANGELOG / Git workflow
- Main branch: **`develop`** (not `main`)
- git-flow: feature → develop → release/X.Y.Z → tags (release branch stays open through Phase 6 of UPGRADE.md)
- AMI ID + comment in `cdk/wordpress/wordpress_stack.py` are updated each release (dev AMI for taskcat on `develop`; prod AMI swapped in temporarily for the Marketplace submit, then dev AMI restored)

## Known repo state to address on next upgrade

- `Dockerfile` pins `ordinaryexperts/aws-marketplace-patterns-devenv:2.5.5` — bump to `:2.8.3` or newer; add `--break-system-packages` to `pip3 install` (PEP 668 on Ubuntu 24.04 base).
- `cdk/setup.py`: `aws-cdk-lib==2.120.0`, `oe-patterns-cdk-common@4.2.4` — bump (Drupal uses `2.225.0` / `4.5.1`).
- `Makefile` `update-common` URL pins utilities `1.6.0` — bump to current.
- Migrate from `plf_config.yaml` to `marketplace_config.yaml` (delivery_option block required for `marketplace-submit`). Keep the old `gen-plf*` Make targets working until the new flow is verified.
- Brand alignment: README / marketplace title still says "Ordinary Experts WordPress Pattern" / "WordPress on AWS Pattern". Target FOSSonCloud branding is **"WordPress on AWS by FOSSonCloud"** (see UPGRADE.md "Brand alignment check").

## Files updated each release

1. `packer/ubuntu_2204_appinstall.sh` — `WORDPRESS_VERSION` and (on devenv major bumps) `SCRIPT_VERSION`
2. `cdk/wordpress/wordpress_stack.py` — `AMI_ID` constant + comment
3. `Makefile` `deploy` target — AMI ID parameter (rename to `AsgAmiIdvXYZ` on first version that introduces the suffix)
4. `cdk/setup.py` — when bumping CDK / common-library pins
5. `CHANGELOG.md`
6. Git tag with the new pattern version
