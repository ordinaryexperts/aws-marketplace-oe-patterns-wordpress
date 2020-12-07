ami-docker-bash: ami-docker-build
	docker-compose run --rm ami bash

ami-docker-build:
	docker-compose build ami

ami-docker-rebuild:
	docker-compose build --no-cache ami

ami-ec2-build: build
	docker-compose run -w /code --rm wordpress bash ./scripts/packer.sh $(TEMPLATE_VERSION)

ami-ec2-copy: build
	docker-compose run -w /code --rm wordpress bash ./scripts/copy-image.sh $(AMI_ID)

bash: build
	docker-compose run -w /code --rm wordpress bash

bootstrap:
	docker-compose run -w /code/cdk --rm wordpress cdk bootstrap aws://992593896645/us-east-1

build:
	docker-compose build wordpress

clean: build
	docker-compose run -w /code --rm wordpress bash ./scripts/cleanup.sh

clean-all-tcat: build
	docker-compose run -w /code --rm wordpress bash ./scripts/cleanup.sh all tcat

clean-all-tcat-all-regions: build
	docker-compose run -w /code --rm wordpress bash ./scripts/cleanup.sh all tcat all

clean-buckets: build
	docker-compose run -w /code --rm wordpress bash ./scripts/cleanup.sh buckets

clean-buckets-tcat: build
	docker-compose run -w /code --rm wordpress bash ./scripts/cleanup.sh buckets tcat

clean-buckets-tcat-all-regions: build
	docker-compose run -w /code --rm wordpress bash ./scripts/cleanup.sh buckets tcat all

clean-logs: build
	docker-compose run -w /code --rm wordpress bash ./scripts/cleanup.sh logs

clean-logs-tcat: build
	docker-compose run -w /code --rm wordpress bash ./scripts/cleanup.sh logs tcat

clean-logs-tcat-all-regions: build
	docker-compose run -w /code --rm wordpress bash ./scripts/cleanup.sh logs tcat all

clean-snapshots: build
	docker-compose run -w /code --rm wordpress bash ./scripts/cleanup.sh snapshots

clean-snapshots-tcat: build
	docker-compose run -w /code --rm wordpress bash ./scripts/cleanup.sh snapshots tcat

clean-snapshots-tcat-all-regions: build
	docker-compose run -w /code --rm wordpress bash ./scripts/cleanup.sh snapshots tcat all

deploy: build
	docker-compose run -w /code/cdk --rm wordpress cdk deploy \
	--require-approval never \
	--parameters CertificateArn=arn:aws:acm:us-east-1:992593896645:certificate/77ba53df-8613-4620-8b45-3d22940059d4 \
	--parameters CloudFrontCertificateArn=arn:aws:acm:us-east-1:992593896645:certificate/77ba53df-8613-4620-8b45-3d22940059d4 \
	--parameters CloudFrontAliases=cdn-oe-patterns-wordpress-${USER}.dev.patterns.ordinaryexperts.com \
	--parameters CloudFrontEnable=false \
	--parameters ElastiCacheEnable=false \
	--parameters InitializeDefaultWordPress=true \
  --parameters PipelineArtifactBucketName=github-user-and-bucket-taskcatbucket-2zppaw3wi3sx \
	--parameters SourceArtifactBucketName=github-user-and-bucket-githubartifactbucket-wl52dae3lyub \
	--parameters SourceArtifactObjectKey=aws-marketplace-oe-patterns-wordpress-example-site/refs/heads/develop.zip \
	--parameters TransferUserName=${USER} \
	--parameters TransferUserSshPublicKey="$(shell cat ~/.ssh/id_rsa.pub)" \
	--parameters VpcId=vpc-00425deda4c835455 \
	--parameters VpcPrivateSubnetId1=subnet-030c94b9795c6cb96 \
	--parameters VpcPrivateSubnetId2=subnet-079290412ce63c4d5 \
	--parameters VpcPublicSubnetId1=subnet-0c2f5d4daa1792c8d \
	--parameters VpcPublicSubnetId2=subnet-060c39a6ded9e89d7

destroy: build
	docker-compose run -w /code/cdk --rm wordpress cdk destroy

diff: build
	docker-compose run -w /code/cdk --rm wordpress cdk diff

gen-plf: build
	docker-compose run -w /code --rm wordpress python3 ./scripts/gen-plf.py $(AMI_ID) $(TEMPLATE_VERSION)

list-all-stacks: build
	docker-compose run -w /code --rm wordpress bash ./scripts/list-all-stacks.sh

lint: build
	docker-compose run -w /code --rm wordpress bash ./scripts/lint.sh

publish: build
	docker-compose run -w /code --rm wordpress bash ./scripts/publish-template.sh $(TEMPLATE_VERSION)

rebuild:
	docker-compose build --no-cache wordpress

synth: build
	docker-compose run -w /code/cdk --rm wordpress cdk synth \
	--version-reporting false \
	--path-metadata false \
	--asset-metadata false

synth-to-file: build
	docker-compose run -w /code --rm wordpress bash -c "cd cdk \
	&& cdk synth \
	--version-reporting false \
	--path-metadata false \
	--asset-metadata false > /code/dist/template.yaml \
	&& echo 'Template saved to dist/template.yaml'"

test-all: build
	docker-compose run -w /code --rm wordpress bash -c "cd cdk \
	&& cdk synth > ../test/template.yaml \
	&& cd ../test \
	&& taskcat test run"

test-main: build
	docker-compose run -w /code --rm wordpress bash -c "cd cdk \
	&& cdk synth > ../test/main-test/template.yaml \
	&& cd ../test/main-test \
	&& taskcat test run"

test-regions: build
	docker-compose run -w /code --rm wordpress bash -c "cd cdk \
	&& cdk synth > ../test/regions-test/template.yaml \
	&& cd ../test/regions-test \
	&& taskcat test run"
