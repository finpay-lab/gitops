# Terraform scaffold for FinPay Lab cloud bootstrap (FP-26)
# NOTE: this lab runs on a local kind cluster; these modules are the
# production-oriented design for deploying the same workloads to a managed
# Kubernetes (EKS). They are intentionally minimal stubs documenting the
# intended topology, not applied in this environment.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" { type = string; default = "eu-west-1" }
variable "cluster_name" { type = string; default = "finpay-prod" }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  name    = var.cluster_name
  cidr    = "10.8.0.0/16"
  azs     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  private_subnets = ["10.8.1.0/24", "10.8.2.0/24", "10.8.3.0/24"]
  public_subnets  = ["10.8.101.0/24", "10.8.102.0/24", "10.8.103.0/24"]
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.0"
  cluster_name    = var.cluster_name
  cluster_version = "1.30"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets
}

# Argo CD, Postgres, Kafka, OpenSearch, etc. are then provisioned via the
# gitops/ repo (Helm + ApplicationSet) once this cluster exists.
output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
