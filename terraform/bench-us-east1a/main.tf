terraform {
  required_version = ">= 1.3.6"
  backend "s3" {
    bucket = "spiders-aptos-east"
    key = "state/testnet"
    region = "us-east-1"

  }
}

locals {
  region  = "us-east-1"
  }


module "aptos-node" {
  source = "../../submodules/aptos-core/terraform/aptos-node/aws"

  manage_via_tf = false # manage via cluster.py tooling instead

  region  = local.region  # Specify the region

  validator_name = "aptos-bench-na-nodes"

  # for naming purposes to avoid name collisions
  chain_name          = "aptos-bench"

  # Toggle these on if you want a per-cluster monitoring and logging setup
  # Otherwise rely on a separate central monitoring and logging setup
  enable_monitoring = false
  enable_logger     = false

  # Autoscaling configuration
  # space for at least 100 k8s worker nodes, assuming 48 vCPU and 192 GB RAM per node
}

# resource "local_file" "kubectx" {
#   filename = "kubectx.sh"
#   content  = <<-EOF
#   #!/bin/bash

#   gcloud container clusters get-credentials aptos-${terraform.workspace} --zone ${local.region}-${local.zone}
#   EOF
# }
