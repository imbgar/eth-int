terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  backend "s3" {
    bucket       = "int-tf-state-bgar"
    key          = "envs/dev/terraform.tfstate"
    region       = "us-west-2"
    use_lockfile = true
  }
}
provider "aws" {
  region = "us-west-2"
}

data "aws_ssm_parameter" "image_digest" {
  name = var.container_image_ssm_parameter_name
}

