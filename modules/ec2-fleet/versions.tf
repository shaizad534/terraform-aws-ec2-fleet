# Which tools this module needs.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Pinned on purpose: "=" locks this exact version so a future release
      # can never change how this module behaves.
      version = "= 6.69.0"
    }
  }
}
