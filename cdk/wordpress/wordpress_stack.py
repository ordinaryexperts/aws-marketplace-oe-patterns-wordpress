import os
import subprocess
from aws_cdk import (
    Aws,
    aws_ec2,
    aws_elasticloadbalancingv2,
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

AMI_ID="ami-004016a64b67ef08b" # ordinary-experts-patterns-wordpress-2.1.0-20250305-0314

class WordPressStack(Stack):

    def __init__(self, scope: Construct, id: str, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        #
        # PARAMETERS
        #
        self.custom_wp_config_parameter_arn_param = CfnParameter(
            self,
            "CustomWpConfigParameterArn",
            default="",
            description="Optional: ARN of SSM Parameter Store Secure String containing custom PHP code to put into wp-config.php."
        )
        self.enable_sftp_param = CfnParameter(
            self,
            "EnableSftp",
            allowed_values=[ "true", "false" ],
            default="false",
            description="Required: Enable SFTP support via NLB. You also need to specify AsgKeyName parameter to connect."
        )
        self.sftp_ingress_cidr_param = CfnParameter(
            self,
            "SftpIngressCidr",
            allowed_pattern=r"^((\d{1,3})\.){3}\d{1,3}/\d{1,2}$",
            description="Required (only used if Enable SFTP is true): VPC IPv4 CIDR block to restrict access to inbound SFTP connections. Set to '0.0.0.0/0' to allow all access, or set to 'X.X.X.X/32' to restrict to one IP (replace Xs with your IP), or set to another CIDR range."
        )

        #
        # CONDITIONS
        #
        self.custom_wp_config_parameter_arn_condition = CfnCondition(
            self,
            "CustomWpConfigParameterArnCondition",
            expression=Fn.condition_not(Fn.condition_equals(self.custom_wp_config_parameter_arn_param.value, ""))
        )
        self.enable_sftp_condition = CfnCondition(
            self,
            "EnableSftpCondition",
            expression=Fn.condition_equals(self.enable_sftp_param.value, "true")
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
            ami_id=AMI_ID,
            default_instance_type = "m5.large",
            deployment_rolling_update = True,
            secret_arns=[db_secret.secret_arn(), ses.secret_arn()],
            use_graviton=False,
            user_data_contents=launch_config_user_data,
            user_data_variables = {
                "CustomWpConfigParameterArn": self.custom_wp_config_parameter_arn_param.value_as_string,
                "DbSecretArn": db_secret.secret_arn(),
                "HostedZoneName": dns.route_53_hosted_zone_name_param.value_as_string,
                "InstanceSecretName": Aws.STACK_NAME + "/instance/credentials",
                "SecretArn": secret.secret_arn()
            },
            vpc=vpc
        )
        asg.asg.node.add_dependency(db.db_primary_instance)
        asg.asg.node.add_dependency(ses.generate_smtp_password_custom_resource)

        # update this policy via overrides bc CDK doesn't like wrapping it in an Fn::If
        asg.iam_instance_role.add_property_override(
            "Policies.5",
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
        dns.add_alb(alb)

        nlb_sg = aws_ec2.CfnSecurityGroup(
            self,
            "NlbSg",
            group_description="{}/NlbSg".format(Aws.STACK_NAME),
            security_group_egress=[
                aws_ec2.CfnSecurityGroup.EgressProperty(
                    ip_protocol="-1",
                    cidr_ip="0.0.0.0/0",
                    description="all IPv4 egress traffic allowed"
                )
            ],
            vpc_id=vpc.id()
        )
        aws_ec2.CfnSecurityGroupIngress(
            self,
            "NlbSgSftpIngress",
            cidr_ip=self.sftp_ingress_cidr_param.value_as_string,
            description="Allow SFTP traffic to NLB from allowed CIDR block",
            from_port=22,
            group_id=nlb_sg.ref,
            ip_protocol="tcp",
            to_port=22
        )
        aws_ec2.CfnSecurityGroupIngress(
            self,
            "SgAsgIngress",
            description="Allow traffic from Nlb to App",
            from_port=22,
            group_id=asg.sg.ref,
            ip_protocol="tcp",
            source_security_group_id=nlb_sg.ref,
            to_port=22
        )
        nlb = aws_elasticloadbalancingv2.CfnLoadBalancer(
            self,
            "Nlb",
            security_groups=[ nlb_sg.ref ],
            scheme="internet-facing",
            subnets=vpc.public_subnet_ids(),
            type="network"
        )
        nlb.cfn_options.condition = self.enable_sftp_condition
        nlb.add_dependency(alb.http_listener)
        nlb.add_dependency(alb.https_listener)

        sftp_target_group = aws_elasticloadbalancingv2.CfnTargetGroup(
            self,
            "SftpTargetGroup",
            port=22,
            protocol="TCP",
            target_group_attributes=[
                aws_elasticloadbalancingv2.CfnTargetGroup.TargetGroupAttributeProperty(
                    key='deregistration_delay.timeout_seconds',
                    value='10'
                )
            ],
            target_type="instance",
            vpc_id=vpc.id()
        )
        sftp_target_group.cfn_options.condition = self.enable_sftp_condition

        asg.asg.add_override(
            "Properties.TargetGroupARNs",
            Fn.condition_if(
                self.enable_sftp_condition.logical_id,
                [alb.target_group.ref, sftp_target_group.ref],
                [alb.target_group.ref]
            )
        )
        sftp_listener = aws_elasticloadbalancingv2.CfnListener(
            self,
            "SftpListener",
            default_actions=[
                aws_elasticloadbalancingv2.CfnListener.ActionProperty(
                    target_group_arn=sftp_target_group.ref,
                    type="forward"
                )
            ],
            load_balancer_arn=nlb.ref,
            port=22,
            protocol="TCP"
        )
        sftp_listener.cfn_options.condition = self.enable_sftp_condition

        CfnOutput(
            self,
            "FirstUseInstructions",
            description="Instructions for getting started",
            value="Click on the DnsSiteUrlOutput link and follow the instructions for installing the WordPress site."
        )

        CfnOutput(
            self,
            "SftpEndpoint",
            condition=self.enable_sftp_condition,
            description="SFTP DNS Endpoint",
            value=nlb.attr_dns_name
        )

        CfnOutput(
            self,
            "SftpExampleCommand",
            condition=self.enable_sftp_condition,
            description="Example SFTP connection command. Update to use the correct path to the pem file",
            value=f"sftp -i {asg.key_name_param.value_as_string}.pem wordpress@{nlb.attr_dns_name}"
        )

        parameter_groups = [
            {
                "Label": {
                    "default": "Advanced WordPress Config"
                },
                "Parameters": [
                    self.custom_wp_config_parameter_arn_param.logical_id,
                    self.enable_sftp_param.logical_id,
                    self.sftp_ingress_cidr_param.logical_id
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
                    self.enable_sftp_param.logical_id: {
                        "default": "Enable SFTP"
                    },
                    self.sftp_ingress_cidr_param.logical_id: {
                        "default": "SFTP Ingress CIDR Block (only used if Enable SFTP is true)"
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
