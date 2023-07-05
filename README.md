# Aptos Multi-Region Benchmark Setup


## Benchmark setup

### Clone the repo

This repo uses a git submodule to https://github.com/aptos-labs/aptos-core, so be sure to clone that as well

```
git clone https://github.com/aptos-labs/aptos-multi-region-bench.git --recurse-submodules
cd aptos-multi-region-bench
```

At any point you can update the submodule with:

```
git submodule update --remote
```

### Set up AWS access

Create an AWS project and sign-in with the `aws` CLI. 

For reference:
* Install `aws` CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
* Authenticate with short-term credentials: https://docs.aws.amazon.com/cli/latest/userguide/cli-authentication-short-term.html

```
aws configure
```

### Set up the infrastructure

NOTE: This section may take a while to run through all the steps. A lot of the time will be spent running commands and waiting on cloud infrastructure to come alive.

Each region's infrastructure is deployed separately, via Terraform. Each directory in the top-level `terraform/` directory corresponds to a Terraform project. 

If you are unfamiliar with Terraform, it's highly recommended that you familiarize yourself with Terraform concepts before you get started. This will help you ensure the health of your infrastructure, as well as prevent unnecessary costs. Particularly, these reference documentation links:
* What is Terraform: https://developer.hashicorp.com/terraform/intro
* Terraform backends: https://developer.hashicorp.com/terraform/language/settings/backends/configuration
* Terraform workspaces: https://developer.hashicorp.com/terraform/language/state/workspaces

If there is no pre-existing storage bucket (in our case there is):
Create a storage bucket for storing the Terraform state on Amazon S3. Use the console or this AWS cli to create the bucket. The name of the bucket must be unique. See the S3 documentation here: https://aws.amazon.com/s3/

```
# for example
aws s3api create-bucket --bucket my-bucket --region us-east-1
```

Then, edit main.tf of each region to reference the s3 bucket created in the previous step..

Deploy each region's infrastructure using the following commands. For each of the Terraform project directories in `terraform/`, run the following series of commands:

Because the terraform scripts have not been properly written, we split cluster creation and K8s configuration into discrete plan/apply cycles inspired by [hashicorp/terraform-provider-kubernetes#1078](https://github.com/hashicorp/terraform-provider-kubernetes/pull/1078). First, change main.tf to reference the aws-node-only submodule folder and perform the steps below and then repeat with aws submodule folder using the same workspace.

From personal experience, once the "aws-node-only" part reaches module.aptos-node.aws_eks_addon.aws-ebs-csi-driver, stop it (with Ctlr + C) to save some time. Also, the "aws" part may need a short second iteration because of some dependencies not set correctly.
```
#
# Initialize terraform and its backend.
# This will copy the public reference terraform modules written by Aptos Labs into the .terraform/modules directory
terraform init 

# Initialize your terraform workspaces, one unique workspace name for each directory.
You can skip this step and "default" workspace will be used. (I recommend this since the name of the bucket that exists has been created in the default workspace)
terraform workspace new <WORKSPACE_NAME>
# for example
terraform workspace new bench-asia-east1

# check the infrastructure that will be applied
terraform plan

# apply it
terraform apply
```


After all the infrastructure is created, you can use the `cluster.py` utility to authenticate against all clusters. This will be your primary tool for interacting with each of the cluster's workloads. It is a wrapper around the kube API and familiar `kubectl` commands.

For this to work, update the kubeconfig of the EKS cluster.
```
aws eks update-kubeconfig --region us-west-1 --name aptos-default
```
### Initialize the Network

At this point, most of the required infrastructure has been set up. You must now begin the genesis process and start all the Aptos nodes in each kubernetes cluster. As a quick sanity check, visit this URL to view all your active kubernetes clusters within the project, and confirm that all are in a healthy "green" state. If not, use AWS's tooltips and logs to help debug.

By default, the Terraform modules will also install some baseline Aptos workloads on each of the kubernetes clusters as well (e.g. 1 validator). To check these running workloads, run the following from the project root:

```
./bin/cluster.py kube get pods 
```

These workloads will soon be replaced with the following steps, which initializes the benchmark network.

#### Install `aptos` CLI

Some of the scripts below require the `aptos` CLI to be installed. Install instructions: https://aptos.dev/cli-tools/aptos-cli-tool/

Also ensure that the CLI is available in the `PATH`.

#### Run genesis

In this setup, you will mostly be interacting with `aptos_node_helm_values.yaml` to configure the benchmark network as a whole.

Firstly, start all the validators and fullnodes.

```
# 1. This performs a helm upgrade to all clusters to spin up the validators and fullnodes (this may take a few minutes). The scripts in the next steps expect to have equal number of vfn's else they crash, so also pass the flag --vfn-enabled.
time ./bin/cluster.py upgrade --new --vfn-enabled
```

You will see most pods are in a `ContainerCreating` state. This is because these pods (fullnodes and validators) are waiting for their keys and genesis configurations, which will be done in a later step.


In order to progress to the next steps, check that all LoadBalancers have been provisioned for each validator and fullnode. From the output, check if there are any services that have `<pending>` for their `EXTERNAL-IP`. Wait until all LoadBalancers are brought up before proceeding to the next step.

```
# 1.1. Filter all kubernetes services by LoadBalancer type, checking for pending
./bin/cluster.py kube get svc | grep LoadBalancer

# to continue, this should be zero
./bin/cluster.py kube get svc | grep -c pending
```

To run genesis for the first time, execute the below command. This will generate keys and get the public IP for each of the validators and fullnodes and then generate a genesis blob and waypoint. These will then be uploaded to each node (via kubernetes) for startup
```
./bin/cluster.py genesis create --generate-keys
```

From here onwards, you can use Helm to manage the lifecycle of your nodes. If there is any config change you want to make, you can run `upgrade` again (NOTE: this time, without `--new`). If nothing has changed, running it again should be idempotent:
```
# 4. Upgrade all nodes (this may take a few minutes)
time ./bin/cluster.py upgrade
```

## Scripts Reference

`bin/loadtest.py` - cluster loadtest utility.
`bin/cluster.py` - cluster management utility. Creates genesis, and manages nodes lifecycle

### `loadtest.py`

Submit load test against the network. The root keypair is hardcoded in genesis. The below commands show some cutomization options for the loadtest utility.
To change the load type (e.g from coin-transfer to dexbursty) configure aptos-multi-region-bench/bin/loadtest.py:118 without changing the parameter --coin-transfer of the command below (lazy soluton).
```
# apply the benchmnark loadtest for an hour:
./bin/loadtest.py 0xE25708D90C72A53B400B27FC7602C4D546C7B7469FA6E12544F0EBFB2F16AE19 7 --apply --txn-expiration-time-secs=60 --mempool-backlog=25000 --duration=3600 --only-within-cluster --coin-transfer

# more customizations can be seen here
./bin/loadtest.py --help
```

### `cluster.py`

#### Spin up or down compute, e.g. to save cost by going idle

```
./bin/cluster.py start
./bin/cluster.py stop
```

#### Delete all workloads in each cluster, e.g. a clean wipe

```
./bin/cluster.py delete
```

To bring back the network, you can try: 

```
./bin/cluster.py upgrade --new
```

### Changing number of validator node instances
To spawn more validator node instances (c6i.8xlarge) configure the desired (and potentially maximum) size of the instance pool in submodules/aptos-core/terraform/aptos-node/aws/cluster.tf and re-apply the terraform configuration. This can be done while the cluster is running with no problem.

#### Wipe the network and start from scratch

To wipe the chain, change the chain's "era" in the helm values in `aptos_node_helm_values.yaml`. This tells the kubernetes workloads to switch their underlying volumes, thus starting the chian from scratch. Then, follow the steps above to [Run genesis](#run-genesis)

#### Changing the network size (and starting a new network)
* Edit `CLUSTERS` in `constants.py` to change the number of validators (and VFNs) in each region. Please note the quota in your GCP project.
* Follow above instructions to re-run genesis and wipe the chain.

#### Changing the node deployment configuration
Each node is deployed via `helm` on each cluster. The configuration is controlled by helm values in the file: `aptos_node_helm_values.yaml`. Documentation on which values are available to configure can be found in aptos-core: https://github.com/aptos-labs/aptos-core/tree/main/terraform/helm/aptos-node

For example:
* `imageTag` -- change the image for each validator and VFN
* `chain.era` -- change the chain era and wipe storage
* `validator.config` -- override the [NodeConfig](https://github.com/aptos-labs/aptos-core/blob/main/config/src/config/mod.rs#L63-L98) as YAML, such as tuning execution, consensus, state sync, etc

### Misc

#### Grab the latest aptos-framework for genesis

```
docker run -it aptoslabs/tools:${IMAGE_TAG} bash
docker cp `docker container ls | grep tools:${IMAGE_TAG} | awk '{print $1}'`:/aptos-framework/move/head.mrb genesis/framework.mrb
```



