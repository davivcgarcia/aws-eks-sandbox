################################################################################
# Input Variables
################################################################################

variable "environment_name" {
  type    = string
  default = "sandbox"
}

variable "k8s_version" {
  type    = string
  default = "1.30"
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "aws_vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "aws_tags" {
  type = map(any)
  default = {
    Owner       = "davivcgarcia"
    Environment = "sandbox"
  }
}

################################################################################
# Local Variables
################################################################################

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}
