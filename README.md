# Aptos Multi-Region Benchmark Setup

This repo contains deployment configurations, operational scripts, and benchmarks for a multi-region Aptos benchmark on GKE. 
* Each region is deployed separately via open source Terraform modules published by Aptos Labs
* A lightweight wrapper around the kube API and `kubectl` provides a way to form the network and submit load against the network

## Multi-region setup

Google Cloud Inter-Region Latency and Throughput: [link](https://datastudio.google.com/u/0/reporting/fc733b10-9744-4a72-a502-92290f608571/page/70YCB)
* asia-east1 -- Taiwan
* europe-west4 -- Netherlands
* us-west1 -- Oregon

### Raw data

The below latency and throughput stats were pulled from [Google Cloud Inter-Region Latency and Throughput](https://datastudio.google.com/u/0/reporting/fc733b10-9744-4a72-a502-92290f608571/page/70YCB). Raw filtered CSV can be found in the `./data` directory.

Latency (snapshot Dec 5, 2022 - Jan 3, 2023):

|sending_region|receiving_region|milliseconds|
|--------------|----------------|------------|
|asia-east1    |europe-west4    |251.794     |
|asia-east1    |us-west1        |118.553     |
|europe-west4  |asia-east1      |251.777     |
|europe-west4  |us-west1        |133.412     |
|us-west1      |asia-east1      |118.541     |
|us-west1      |europe-west4    |133.435     |


Throughput (snapshot Dec 5, 2022 - Jan 3, 2023):

|sending_region|receiving_region|Gbits/sec|
|--------------|----------------|---------|
|asia-east1    |europe-west4    |9.344    |
|asia-east1    |us-west1        |9.811    |
|europe-west4  |asia-east1      |9.326    |
|europe-west4  |us-west1        |9.815    |
|us-west1      |asia-east1      |9.802    |
|us-west1      |europe-west4    |9.778    |

## Env setup

### Clone the repo

```
git clone https://github.com/aptos-labs/aptos-multi-region-bench.git
cd aptos-multi-region-bench
```

### Set up GCP access

Create a GCP project and sign in with the `gcloud` CLI. Also it will be useful to set the environment variable `GCP_PROJECT_ID` for future use.

For reference:
* Install `gcloud` CLI: https://cloud.google.com/sdk/docs/install
* Create a GCP project: https://cloud.google.com/resource-manager/docs/creating-managing-projects

```
export GCP_PROJECT_ID=<YOUR_GCP_PROJECT_ID>

gcloud auth login --update-adc
gcloud config set project $GCP_PROJECT_ID
```

### Set up the infrastructure

Each region's infrasstructure is deployed separately, via Terraform. Each directory in the top-level `terraform/` directory corresponds to a Terraform project. 

If you are unfamiliar with Terraform, check out these reference docs:
* What is Terraform: https://developer.hashicorp.com/terraform/intro
* Terraform backends: https://developer.hashicorp.com/terraform/language/settings/backends/configuration
* Terraform workspaces: https://developer.hashicorp.com/terraform/language/state/workspaces

Create a storage bucket for storing the Terraform state on Google Cloud Storage. Use the console or this `gcs` command to create the bucket. The name of the bucket must be unique. See the Google Cloud Storage documentation here: https://cloud.google.com/storage/docs/creating-buckets#prereq-cli.

```
gsutil mb gs://BUCKET_NAME
# for example
gsutil mb gs://<project-name>-aptos-terraform-bench
```

Then, edit `terraform/example.backend.tfvars` to reference the gcs bucket created in the previous step. Rename `terraform/example.backend.tfvars` to `terraform/backend.tfvars`.

Deploy each region's infrastructure using the following commands. For each of the Terraform project directories in `terraform/`, run:

```
# Initialize terraform and its backend in each directory
terraform init -backend-config=../backend.tfvars

# This environment variable is used to apply the infrastructure to the GCP project you set up in the previous step
export TF_VAR_project=$GCP_PROJECT_ID

# Initialize your terraform workspaces, one for each directory.
terraform workspace new <WORKSPACE_NAME>
# for example
terraform workspace new bench-asia-east1

# check the infrastructure that will be applied
terraform plan

# apply it
terraform apply
```

After all the infrastructure is created, you can use the `cluster.py` utility to authenticate against all clusters. This will be your primary tool for interacting with each of the cluster's workloads. It is a wrapper around the kube API and familiar `kubectl` commands.

Authenticate with all GKE clusters
```
./bin/cluster.py auth
```

## Scripts

`bin/loadtest.py` - little loadtest utility.
`bin/cluster.py` - cluster management utility. Creates genesis, and manages nodes lifecycle

### `loadtest.py`

Submit load test against the network. The root keypair is hardcoded in genesis. The below commands show some cutomization options for the loadtest utility.

```
# apply a loadtest with a constant target TPS
./bin/loadtest.py 0xE25708D90C72A53B400B27FC7602C4D546C7B7469FA6E12544F0EBFB2F16AE19 4 --apply --target-tps 5000

# apply a loadtest with mempool backlog 50,000 for 1 hour
./bin/loadtest.py 0xE25708D90C72A53B400B27FC7602C4D546C7B7469FA6E12544F0EBFB2F16AE19 4 --apply --duration 3600 --mempool-backlog 50000

# more customizations can be seen here
./bin/loadtest.py --help
```

### `cluster.py`

#### Spin up or down compute, e.g. to save cost by going idle

```
./bin/cluster.py start
./bin/cluster.py stop
```

#### Wipe the network and start from scratch

```
# 1. Changing the chain's era wipes all storage and tells the system to start from scratch
<edit aptos_node_helm_values.yaml with a new chain.era>

# 2. Re-run genesis and set all validator configs. You have a few options here

# a. re-generate keys and re-fetch the external IPs for validator config
yes | ./bin/cluster.py genesis create --generate-keys --set-validator-config
# b. to set validator config without generating new keys
yes | ./bin/cluster.py genesis create --set-validator-config

# 3. Upload genesis configs to each node for startup
./bin/cluster.py genesis upload --apply

# 4. Upgrade all nodes (this may take a few minutes)
# this can be done in parallel with above upload step in another terminal
time ./bin/cluster.py helm-upgrade
```

#### Changing the network size (and starting a new network)
* Edit `CLUSTERS` in `constants.py` to change the number of validators (and VFNs) in each region. Please note the quota
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

#### Individual GKE cluster auth

`./bin/cluster.py auth` authencates across all clusters, but you make want to use the below commands to authenticate and change your kube context manually for each cluster.

Each cluster is deployed in its own region via `terraform/` top-level directory. The `kubectx.sh` script in each will authenticate you against each cluster and set your kubectl context to match.
