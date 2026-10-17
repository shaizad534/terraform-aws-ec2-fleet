# Remote state for this root module.
#
# A backend belongs to the root module you run `terraform init` in, so it lives
# here in the example, NOT inside modules/ec2-fleet-module/ (that module is
# reused by other projects, which should choose their own state settings).
#
# Before running `terraform init`:
#   1. Create the S3 bucket below (recommended: versioning + default encryption).
#   2. Create the DynamoDB table below (partition key "LockID", type String).
#   3. Replace the placeholder bucket / region / table with your own values.
terraform {
  backend "s3" {
    bucket         = "YOUR-ORG-terraform-state" # TODO: your S3 bucket
    key            = "ec2/server-fleet/terraform.tfstate"
    region         = "us-east-1"             # TODO: where the bucket lives
    dynamodb_table = "terraform-state-locks" # TODO: your DynamoDB table
    encrypt        = true
  }
}
