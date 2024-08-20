import os
import subprocess
from aws_cdk import (
    Aws,
    aws_iam,
    CfnCondition,
    CfnMapping,
    CfnParameter,
    CfnOutput,
    Fn,
    Stack
)
from constructs import Construct

from oe_patterns_cdk_common.alb import Alb
from oe_patterns_cdk_common.asg import Asg
from oe_patterns_cdk_common.aurora_cluster import AuroraMysql
from oe_patterns_cdk_common.db_secret import DbSecret
from oe_patterns_cdk_common.dns import Dns
from oe_patterns_cdk_common.efs import Efs
from oe_patterns_cdk_common.secret import Secret
from oe_patterns_cdk_common.ses import Ses
from oe_patterns_cdk_common.util import Util
from oe_patterns_cdk_common.vpc import Vpc

DEFAULT_WORDPRESS_SOURCE_URL="https://ordinary-experts-aws-marketplace-wordpress-pattern-artifacts.s3.amazonaws.com/aws-marketplace-oe-patterns-wordpress-default/refs/tags/6.5.5.zip"
TWO_YEARS_IN_DAYS=731
if 'TEMPLATE_VERSION' in os.environ:
    template_version = os.environ['TEMPLATE_VERSION']
else:
    try:
        template_version = subprocess.check_output(["git", "describe"]).strip().decode('ascii')
    except:
        template_version = "CICD"

# When making a new development AMI:
# 1) $ ave oe-patterns-dev make ami-ec2-build
# 2) $ ave oe-patterns-dev make AMI_ID=ami-fromstep1 ami-ec2-copy
# 3) Copy the code that copy-image generates below

# AMI list generated by:
# make AMI_ID=ami-0f1c0bb91a7301da3 ami-ec2-copy
# on Fri Feb 23 03:38:06 UTC 2024.
AMI_ID="ami-0eb3d7845484cd843"
AMI_NAME="ordinary-experts-patterns-wordpress-1.4.1-21-g01ddb23-20240812-0533"
generated_ami_ids = {
    "us-east-1": "ami-0eb3d7845484cd843"
}
# End generated code block.

# Sanity check: if this fails then make ami-ec2-copy needs to be run...
assert AMI_ID == generated_ami_ids["us-east-1"]

class WordPressStack(Stack):

    def __init__(self, scope: Construct, id: str, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        #
        # INITIALIZATION
        #

        ami_mapping={
            "AMI": {
                "AMI": AMI_NAME
            }
        }
        for region in generated_ami_ids.keys():
            ami_mapping[region] = { "AMI": generated_ami_ids[region] }
        CfnMapping(
            self,
            "AWSAMIRegionMap",
            mapping=ami_mapping
        )

        #
        # PARAMETERS
        #
        self.custom_wp_config_parameter_arn_param = CfnParameter(
            self,
            "CustomWpConfigParameterArn",
            default="",
            description="Optional: ARN of SSM Parameter Store Secure String containing custom PHP code to put into wp-config.php."
        )

        #
        # CONDITIONS
        #
        self.custom_wp_config_parameter_arn_condition = CfnCondition(
            self,
            "CustomWpConfigParameterArnCondition",
            expression=Fn.condition_not(Fn.condition_equals(self.custom_wp_config_parameter_arn_param.value, ""))
        )

        #
        # RESOURCES
        #

        # vpc
        vpc = Vpc(
            self,
            "Vpc"
        )

        dns = Dns(self, "Dns")

        secret = Secret(self, "WordPress")

        asg_update_secret_policy = aws_iam.CfnRole.PolicyProperty(
            policy_document=aws_iam.PolicyDocument(
                statements=[
                    aws_iam.PolicyStatement(
                        effect=aws_iam.Effect.ALLOW,
                        actions=[
                            "secretsmanager:GetSecretValue",
                            "secretsmanager:DescribeSecret",
                            "secretsmanager:UpdateSecret"
                        ],
                        resources=[secret.secret_arn()]
                    )
                ]
            ),
            policy_name="AllowUpdateInstanceSecret"
        )

        asg_read_ssm_parameter_policy = aws_iam.CfnRole.PolicyProperty(
            policy_document=aws_iam.PolicyDocument(
                statements=[
                    aws_iam.PolicyStatement(
                        effect=aws_iam.Effect.ALLOW,
                        actions=[
                            "ssm:GetParameter"
                        ],
                        resources=["ARN_PLACEHOLDER"]
                    )
                ]
            ),
            policy_name="AllowReadSsmParameter"
        )

        ses = Ses(
            self,
            "Ses",
            hosted_zone_name=dns.route_53_hosted_zone_name_param.value_as_string
        )

        # db_secret
        db_secret = DbSecret(
            self,
            "DbSecret"
        )

        db = AuroraMysql(
            self,
            "Db",
            database_name="wordpress",
            db_secret=db_secret,
            vpc=vpc
        )

        with open("wordpress/user_data.sh") as f:
            launch_config_user_data = f.read()
        asg = Asg(
            self,
            "Asg",
            additional_iam_role_policies=[asg_update_secret_policy, asg_read_ssm_parameter_policy],
            deployment_rolling_update = True,
            secret_arns=[db_secret.secret_arn(), ses.secret_arn()],
            use_graviton=False,
            user_data_contents=launch_config_user_data,
            user_data_variables = {
                "CustomWpConfigParameterArn": self.custom_wp_config_parameter_arn_param.value_as_string,
                "DbSecretArn": db_secret.secret_arn(),
                "HostedZoneName": dns.route_53_hosted_zone_name_param.value_as_string,
                "Hostname": dns.hostname(),
                "InstanceSecretName": Aws.STACK_NAME + "/instance/credentials",
                "Prefix": "{}/wordpress/secret".format(Aws.STACK_NAME),
                "SecretArn": secret.secret_arn()
            },
            vpc=vpc
        )
        asg.asg.node.add_dependency(db.db_primary_instance)
        asg.asg.node.add_dependency(ses.generate_smtp_password_custom_resource)

        # update this policy via overrides bc CDK doesn't like wrapping it in an Fn::If
        asg.iam_instance_role.add_property_override(
            f"Policies.5",
            {
                "Fn::If": [
                    "CustomWpConfigParameterArnCondition",
                    {
                        "PolicyDocument": {
                            "Statement": [
                                {
                                    "Action": "ssm:GetParameter",
                                    "Effect": "Allow",
                                    "Resource": {
                                        "Ref": "CustomWpConfigParameterArn"
                                    }
                                }
                            ],
                            "Version": "2012-10-17"
                        },
                        "PolicyName": "AllowReadParameterStoreConfig"
                    },
                    { "Ref": "AWS::NoValue" }
                ]
            }
        )

        Util.add_sg_ingress(db, asg.sg)

        # efs
        efs = Efs(self, "Efs", app_sg=asg.sg, vpc=vpc)

        alb = Alb(self, "Alb", asg=asg, vpc=vpc)
        asg.asg.target_group_arns = [ alb.target_group.ref ]
        dns.add_alb(alb)

        CfnOutput(
            self,
            "FirstUseInstructions",
            description="Instructions for getting started",
            value="Click on the DnsSiteUrlOutput link and follow the instructions for installing the WordPress site."
        )

        parameter_groups = [
            {
                "Label": {
                    "default": "Advanced WordPress Config"
                },
                "Parameters": [
                    self.custom_wp_config_parameter_arn_param.logical_id
                ]
            }
        ]
        parameter_groups += alb.metadata_parameter_group()
        parameter_groups += asg.metadata_parameter_group()
        parameter_groups += db.metadata_parameter_group()
        parameter_groups += db_secret.metadata_parameter_group()
        parameter_groups += dns.metadata_parameter_group()
        parameter_groups += efs.metadata_parameter_group()
        parameter_groups += secret.metadata_parameter_group()
        parameter_groups += ses.metadata_parameter_group()
        parameter_groups += vpc.metadata_parameter_group()

        # AWS::CloudFormation::Interface
        self.template_options.metadata = {
            "OE::Patterns::TemplateVersion": template_version,
            "AWS::CloudFormation::Interface": {
                "ParameterGroups": parameter_groups,
                "ParameterLabels": {
                    self.custom_wp_config_parameter_arn_param.logical_id: {
                        "default": "Custom wp-config.php SSM Parameter ARN"
                    },
                    **alb.metadata_parameter_labels(),
                    **asg.metadata_parameter_labels(),
                    **db.metadata_parameter_labels(),
                    **db_secret.metadata_parameter_labels(),
                    **dns.metadata_parameter_labels(),
                    **efs.metadata_parameter_labels(),
                    **secret.metadata_parameter_labels(),
                    **ses.metadata_parameter_labels(),
                    **vpc.metadata_parameter_labels()
                }
            }
        }
