![Ordinary Experts Logo](https://ordinaryexperts.com/img/logo.png)

# WordPress Bedrock on AWS Pattern

The Ordinary Experts WordPress Bedrock Pattern is an open-source AWS CloudFormation template + custom AMI that offers an easy-to-install AWS infrastructure solution for quickly deploying a WordPress site, using the Bedrock project structure.

* [WordPress](https://wordpress.org/) is open source software you can use to create a beautiful website, blog, or app.
* [Bedrock](https://roots.io/bedrock/) is WordPress boilerplate with modern development tools, easier configuration, and an improved folder structure

## Product Setup

*Prework*

For this pattern to work, you must first:

1. Have an AWS Certificate Manager certificate provisioned

After that you can just launch the CloudFormation stack and fill out the required parameters.

## Technical Details

* Debian 10 (Buster)
* Apache 2.4
* PHP 7.4

The AWS stack uses Amazon Elastic Compute Cloud (Amazon EC2), Amazon Virtual Public Cloud (Amazon VPC), Amazon Aurora, Amazon Elastic File System (Amazon EFS), Amazon Simple Storage System (Amazon S3), AWS CodePipeline, AWS CodeBuild, AWS CodeDeploy, AWS Systems Manager, and Amazon Secrets Manager.

Automatically configured to support auto-scaling through AWS Autoscaling Groups, this solution leverages an EFS file system to share user generated content between application servers. Additionally, our solution includes a CodePipeline which actively monitors a deployment location on AWS S3 making continuous integration and deployment throughout your infrastructure easy.

Direct access to the EC2 instance for maintenance and customizations is possible through AWS Systems Manager Agent which is running as a service on the instance. For access, locate the EC2 instance in the AWS console dashboard, select it and click the "Connect" button, selecting the "Session Manager" option.

Regions supported by Ordinary Experts' stack:

Supported:

* ap-northeast-1 (Tokyo)
* ap-northeast-2 (Seoul)
* ap-south-1 (Mumbai)
* ap-southeast-1 (Singapore)
* ap-southeast-2 (Sydney)
* ca-central-1 (Central)
* eu-central-1 (Frankfurt)
* eu-north-1 (Stockholm)
* eu-west-1 (Ireland)
* eu-west-2 (London)
* eu-west-3 (Paris)
* sa-east-1 (Sao Paolo)
* us-east-1 (N. Virginia)
* us-east-2 (Ohio)
* us-west-1 (N. California)
* us-west-2 (Oregon)

Not Supported:

* af-south-1 (Cape Town)
* ap-east-1 (Hong Kong)
* eu-south-1 (Milan)
* me-south-1 (Bahrain)

Optional configurations include the following:

* Contain your infrastructure in a new VPC, or provide this CloudFormation stack with an existing VPC id and subnets.
* Manage DNS automatically by supplying an AWS Route 53 Hosted Zone to the stack.

## Stack Infrastructure

![Topology Diagram](https://ordinaryexperts.com/img/products/wordpress-pattern/wordpress-architecture-diagram.png)

## Developer Setup

We are following the [3 Musketeers](https://3musketeers.io/) pattern for project layout / setup.

First, install [Docker](https://www.docker.com/), [Docker Compose](https://docs.docker.com/compose/), and [Make](https://www.gnu.org/software/make/).

## Feedback

To post feedback, submit feature ideas, or report bugs, use the [Issues section](https://github.com/ordinaryexperts/aws-marketplace-oe-patterns-wordpress/issues) of this GitHub repo.
