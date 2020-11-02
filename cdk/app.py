#!/usr/bin/env python3

import os
from aws_cdk import core

from wordpress.wordpress_stack import WordPressStack

# OE AWS Marketplace Patterns Dev
# arn:aws:organizations::440643590597:account/o-kqeqlsvu0w/992593896645
# ~/.aws/config
# [profile oe-patterns-dev]
# region=us-east-1
# role_arn=arn:aws:iam::992593896645:role/OrganizationAccountAccessRole
# source_profile=oe-prod
env_oe_patterns_dev_us_east_1 = core.Environment(account="992593896645", region="us-east-1")

app = core.App()
WordPressStack(app, "oe-patterns-wordpress-{}".format(os.environ['USER']), env=env_oe_patterns_dev_us_east_1)

app.synth()
