terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.69.0" # pinned to the same version the module expects
    }
  }
}

provider "aws" {
  region = var.region
}

module "ec2_fleet" {
  # Local folder while you are developing the module.
  source = "../../modules/ec2-fleet-module"

  # In real life you pin a released version of the module by pointing at a
  # Git tag (a local folder cannot carry a version number). Replace the line
  # above with the one below, then bump "ref" when you want to upgrade:
  #
  # source = "git::https://github.com/your-org/terraform-aws-ec2-fleet.git//modules/ec2-fleet-module?ref=v1.0.0"

  environment        = "dev"
  owner              = "platform-team"
  security_group_ids = var.security_group_ids

  instances = var.instances
}
