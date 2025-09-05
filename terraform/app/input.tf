variable "aws_region" {
  type = string
  default = "us-west-2"
}

variable "container_image" {
  type = string
  default = "703110344528.dkr.ecr.us-west-2.amazonaws.com/int/balance-api:latest"
}

variable "service_name" {
  type    = string
  default = "balance-api"
}

variable "infura_ssm_parameter_name" {
  type        = string
  description = "Name of the existing SSM parameter that stores INFURA_PROJECT_ID"
  default     = "/int/infura_project_id"
}

variable "container_image_ssm_parameter_name" {
  type        = string
  description = "SSM parameter name that stores the image digest reference (e.g., repo@sha256:...)"
  default     = "/int/balance-api/image_digest"
}
 