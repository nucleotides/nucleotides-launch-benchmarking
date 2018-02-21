path = ./vendor/python/bin
aws  = $(path)/aws

ifndef AWS_SSH_KEY_NAME
$(error AWS_SSH_KEY_NAME is not defined)
endif

.SECONDARY:

all:

staging: staging/connect
production: production/launch

%/launch: bin/launch_jobs.sh tmp/%/benchmark_ids.txt tmp/%/instances.json tmp/%/tag
	@./$^ $(AWS_SSH_KEY_NAME)

%/connect: tmp/%/instances.json
	jq '.Reservations[0].Instances[0].PublicDnsName' $< \
	| xargs -o -I {} ssh -o "StrictHostKeyChecking no" -i ~/.ssh/$(AWS_SSH_KEY_NAME).pem ubuntu@{}


tmp/%/tag: tmp/%/instances.json
	@$(aws) ec2 create-tags \
		--resources $(shell jq .Reservations[].Instances[].InstanceId $<) \
		--tags Key=Name,Value=nucleotides-evaluation Key=Stack,Value=nucleotides-evaluation


tmp/%/instances.json: tmp/%/spot-request-fulfilled.json
	@printf $(WIDTH) "  --> Waiting for EC2 instances to become ready."
	@$(aws) ec2 wait instance-status-ok \
		--instance-ids $(shell jq '.SpotInstanceRequests[].InstanceId' $<)
	@$(aws) ec2 describe-instances \
		--instance-ids $(shell jq '.SpotInstanceRequests[].InstanceId' $<) \
		> $@
	@$(OK)


tmp/%/spot-request-fulfilled.json: tmp/%/spot-requests.json
	@printf $(WIDTH) "  --> Waiting for spot instances to be fulfilled."
	@$(aws) ec2 wait \
		spot-instance-request-fulfilled \
		--spot-instance-request-ids $(shell jq '.SpotInstanceRequests[].SpotInstanceRequestId' $<)
	@$(aws) ec2 \
		describe-spot-instance-requests \
		--spot-instance-request-ids $(shell jq '.SpotInstanceRequests[].SpotInstanceRequestId' $<) \
		> $@
	@$(OK)


tmp/%/spot-requests.json: tmp/%/specification.json tmp/environments.json
	@printf $(WIDTH) "  --> Making EC2 spot instance requests."
	@$(aws) ec2 request-spot-instances \
		--spot-price 0.559 \
		--type one-time \
		--instance-count $(shell jq '.$*.ec2_instances' $(lastword $^)) \
		--launch-specification file://$< \
		> $@
	@sleep 10
	@$(OK)

################################################
#
# Build deployment data
#
################################################


tmp/%/benchmark_ids.txt: tmp/%/benchmark_ids.json
	@jq --raw-output '. | map(tostring) | join("\n")' $< > $@

tmp/%/benchmark_ids.json: tmp/environments.json
	@printf $(WIDTH) "  --> Fetching outstanding $* benchmark IDs."
	@mkdir -p $(dir $@)
	@curl --silent $(shell jq '.$*.url' $<)/tasks/show.json > $@
	@$(OK)

# Dynamically build the EC2 specification by combining the environment specific
# details in 'tmp/environments.json' with the AWS configuration layour in
# 'data/specification.json'. The latest AMI ID is pulled seperately from
# 'tmp/ami_id.txt'
tmp/%/specification.json: tmp/environments.json data/specification.json tmp/ami_id.txt
	@printf $(WIDTH) "  --> Building EC2 instance $* oonfiguration"
	@mkdir -p $(dir $@)
	@jq ".$* + .all" $< | \
	jq \
		--arg ami $(shell cat $(lastword $^) | egrep --only-matching 'ami-\w+') \
		--arg key $(AWS_SSH_KEY_NAME) \
		--from-file data/specification.json \
		> $@
	@$(OK)

################################################
#
# Bootstrap required project resources
#
################################################

ami-url := s3://nucleotides-tools/ami-ids/

bootstrap: vendor/python tmp/environments.json tmp/ami_id.txt

tmp/environments.json:
	@printf $(WIDTH) "  --> Fetching AWS environment configurations"
	@mkdir -p tmp
	@rm -f $@
	@$(aws) s3 cp s3://nucleotides-tools/credentials/environments.json $@ &> /dev/null
	@chmod 400 $@
	@$(OK)

# Contains ID for most recent AMI
tmp/ami_id.txt:
	@printf $(WIDTH) "  --> Fetching most recent AMI ID"
	@mkdir -p tmp
	@$(aws) s3 ls $(ami-url) \
		| egrep "^20\d\d" \
		| sort \
		| tail -n 1 \
		| tr -s ' ' \
		| cut -f 4 -d ' ' \
		| xargs -I {} $(aws) s3 cp $(ami-url){} $@ \
		&> /dev/null
	@$(OK)

vendor/python:
	@printf $(WIDTH) "  --> Installing python AWS client"
	@mkdir -p log
	@virtualenv $@ &> log/virtualenv.txt
	@$(path)/pip install awscli==1.10.35 &> log/virtualenv.txt
	@touch $@
	@$(OK)
clean:
	rm -rf tmp/*

################################################
#
# PRETTY COLORS!!!1!
#
################################################

OK=echo " $(GREEN)OK$(END)"
WIDTH="%-70s"

RED="\033[0;31m"
GREEN=\033[0;32m
YELLOW="\033[0;33m"
END=\033[0m
