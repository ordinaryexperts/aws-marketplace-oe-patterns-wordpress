-include common.mk

update-common:
	wget -O common.mk https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/1.10.0/common.mk

deploy: build
	docker compose run -w /code/cdk --rm devenv cdk deploy \
	--require-approval never \
	--parameters AlbCertificateArn=arn:aws:acm:us-east-1:992593896645:certificate/943928d7-bfce-469c-b1bf-11561024580e \
	--parameters AlbIngressCidr=0.0.0.0/0 \
	--parameters AsgAmiIdv300=ami-0f390a711d584012f \
	--parameters AsgDesiredCapacity=1 \
	--parameters AsgKeyName=oe-patterns-dev-dylan-us-east-1 \
	--parameters AsgMaxSize=2 \
	--parameters AsgMinSize=1 \
	--parameters AsgReprovisionString=$(shell date +%Y%m%d.%H%M%S) \
	--parameters CustomWpConfigParameterArn=arn:aws:ssm:us-east-1:992593896645:parameter/oe-patterns-wordpress-dylan-custom-wp-config \
	--parameters DnsHostname=wordpress-${USER}.dev.patterns.ordinaryexperts.com \
	--parameters DnsRoute53HostedZoneName=dev.patterns.ordinaryexperts.com \
	--parameters EnableSftp="true" \
	--parameters SesCreateDomainIdentity="false" \
	--parameters SftpIngressCidr=0.0.0.0/0

# Run the playwright smoke test against the deployed dev stack.
# Override BASE_URL=... to test a different stack.
test-integration: build
	docker compose run -w /code/test/integration --rm \
		-e BASE_URL=https://wordpress-${USER}.dev.patterns.ordinaryexperts.com \
		devenv pytest test_install_and_post.py -v -s
