-include common.mk

update-common:
	wget -O common.mk https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/1.0.0/common.mk

deploy: build
	docker-compose run -w /code/cdk --rm devenv cdk deploy \
	--require-approval never \
	--parameters AlbCertificateArn=arn:aws:acm:us-east-1:992593896645:certificate/943928d7-bfce-469c-b1bf-11561024580e \
	--parameters AlbIngressCidr=0.0.0.0/0 \
	--parameters AsgDesiredCapacity=1 \
	--parameters AsgReprovisionString=20230307.2 \
	--parameters AsgMaxSize=2 \
	--parameters AsgMinSize=1 \
	--parameters EfsAutomaticBackupsStatus=ENABLED \
	--parameters EfsTransitionToIa=AFTER_14_DAYS \
	--parameters EfsTransitionToPrimaryStorageClass=AFTER_1_ACCESS \
	--parameters InitializeDefaultWordPress=true \
	--parameters PipelineArtifactBucketName=github-user-and-bucket-taskcatbucket-2zppaw3wi3sx \
	--parameters DnsHostname=wordpress-${USER}.dev.patterns.ordinaryexperts.com \
	--parameters DnsRoute53HostedZoneName=dev.patterns.ordinaryexperts.com \
	--parameters SourceArtifactBucketName=github-user-and-bucket-githubartifactbucket-wl52dae3lyub \
	--parameters SourceArtifactObjectKey=wordpress-622.zip \
	--parameters VpcId=vpc-00425deda4c835455 \
	--parameters VpcPrivateSubnet1Id=subnet-030c94b9795c6cb96 \
	--parameters VpcPrivateSubnet2Id=subnet-079290412ce63c4d5 \
	--parameters VpcPublicSubnet1Id=subnet-0c2f5d4daa1792c8d \
	--parameters VpcPublicSubnet2Id=subnet-060c39a6ded9e89d7 \
	--parameters WordPressEnv=production

deploy-demo: build
	docker-compose run -w /code/cdk --rm devenv cdk deploy \
	--require-approval never \
	--parameters CertificateArn=arn:aws:acm:us-east-1:992593896645:certificate/943928d7-bfce-469c-b1bf-11561024580e \
	--parameters InitializeDefaultWordPress=false \
	--parameters PipelineArtifactBucketName=github-user-and-bucket-taskcatbucket-2zppaw3wi3sx \
	--parameters Route53HostedZoneName=dev.patterns.ordinaryexperts.com \
	--parameters SourceArtifactBucketName=ordinary-experts-aws-marketplace-pattern-artifacts \
	--parameters SourceArtifactObjectKey=wordpress-bedrock/demo-site/refs/heads/develop.zip \
	--parameters VpcId=vpc-00425deda4c835455 \
	--parameters VpcPrivateSubnet1Id=subnet-030c94b9795c6cb96 \
	--parameters VpcPrivateSubnet2Id=subnet-079290412ce63c4d5 \
	--parameters VpcPublicSubnet1Id=subnet-0c2f5d4daa1792c8d \
	--parameters VpcPublicSubnet2Id=subnet-060c39a6ded9e89d7 \
	--parameters WordPressHostname=wordpress-${USER}.dev.patterns.ordinaryexperts.com
