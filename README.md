# Nucleotides Launch Scripts

A set of scripts to launch the nucleotides benchmarking process across a
cluster of EC2 instances. The Makefile either launches a single EC2 instance
for testing using `make staging`, or a larger cluster of instances using `make
production`. This process works as follows:

  * Fetch the latest AMI ID used to provision the EC2 instances.

  * Fetch the environment configuration details. This contains security details
    that are not committed to the git history. The configuration details also
    vary depending on the environment being provisioned.

  * Build an AWS configuration file. This is used by the AWS command line
    instance to launch the EC2 instances.

  * Fetch the outstanding list of nucleotides benchmark IDs from the
    nucleotides API. The URL for this API is defined in the environment
    configuration file fetched above.

  * Launch AWS spot requests using the AWS command line interface and the
    generated configuration file. Use the AWS CLI to wait for the spot requests
    to be fulfilled, and subsequently the instances to become ready. Finally
    tag these instances.

  * Connect to each instance and start the benchmarking process. Each EC2
    instance is given a subset of the outstanding IDs to evaluate. The
    benchmarking IDs are given to each EC2 instance over ssh using the bash
    script in `bin/launch_jobs.sh`
