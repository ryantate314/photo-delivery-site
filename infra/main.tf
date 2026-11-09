terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # Remote state: never committed.
  backend "s3" {
    bucket       = "ryantate314-tfstate"
    key          = "workloads/photos/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "aws-infrastructure"
      Workload    = var.workload
      Environment = var.env
      ManagedBy   = "terraform"
    }
  }
}

# CloudFront certificates MUST live in us-east-1, regardless of where the rest runs.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "aws-infrastructure"
      Workload    = var.workload
      Environment = var.env
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # Prefix for NEW resources (env first). Adopted resources keep their existing names.
  name       = "${var.env}-photodeliverysite"
  account_id = data.aws_caller_identity.current.account_id
}
