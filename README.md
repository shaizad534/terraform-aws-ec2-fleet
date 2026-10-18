# terraform-aws-ec2-fleet

A small, easy-to-read Terraform module that creates a fleet of EC2 servers from
**one map variable**. Each server can have its own instance type, root volume
type, root volume size, and key pair.

- All servers are created with `for_each` from the single `instances` map.
- Servers flagged `protect = true` are guarded with
  `lifecycle { prevent_destroy = true }`.
- Every server is tagged with `Name`, `Environment`, and `Owner`.
- Validation rules require `root_volume_type` to be a valid value, require
  **every server to use a different root volume type**, and require any
  `io1`/`io2` server to set `iops`.
- Outputs are maps of `server name -> instance ID` and `server name -> private IP`.

See [NOTES.md](./NOTES.md) for which server is protected and why.

## Folder layout

```
.
├── README.md
├── NOTES.md
├── modules/
│   └── ec2-fleet-module/   # the reusable module
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── versions.tf
└── ec2/
    └── server-fleet/       # a runnable example that uses the module
        ├── main.tf
        ├── backend.tf      # S3 remote state + DynamoDB locking
        ├── variables.tf
        ├── outputs.tf
        ├── terraform.tfvars
        └── .terraform.lock.hcl   # committed to pin exact provider builds
```

## Usage

```hcl
module "ec2_fleet" {
  source = "../../modules/ec2-fleet-module"

  environment = "dev"
  owner       = "platform-team"

  instances = {
    web-01 = {
      instance_type    = "t3.small"
      root_volume_type = "gp3"
      root_volume_size = 20
      key_name         = "dev-key-web"
    }
    db-01 = {
      instance_type    = "r5.xlarge"
      root_volume_type = "io1"
      root_volume_size = 200
      key_name         = "dev-key-db"
      iops             = 5000
      protect          = true
    }
  }
}
```

Run the example (after creating the backend bucket/table and editing
`ec2/server-fleet/backend.tf`):

```bash
cd ec2/server-fleet
terraform init
terraform plan
terraform apply
```

## Remote state (S3 + DynamoDB)

`ec2/server-fleet/backend.tf` stores the state file in S3 and uses a DynamoDB
table for locking. The bucket and table must exist before `terraform init`.

### What happens today with local state

- Each engineer keeps their own `terraform.tfstate` on their own machine, so
  everyone has a **separate, diverging copy** of what Terraform thinks exists.
- If two people run `apply` at the same time, both read stale copies, both
  change AWS, and both write their copy back. Nothing coordinates them.
- The result is **last-write-wins**: one person's resources can be created in
  AWS but missing from state (orphaned), or one apply can undo the other's
  changes. No error is raised — it fails silently and you get drift.

### How this backend prevents it

- **S3** makes state **shared and central**, so every engineer reads the same
  file and sees the same resources.
- **DynamoDB** provides **locking**: at the start of an operation Terraform
  writes a lock item. Only one operation can hold it. A second concurrent
  `apply` stops with `Error acquiring the state lock` instead of writing.
- When the first finishes, it releases the lock and writes state to S3; the
  next run then sees the updated state.
- `encrypt = true` keeps the state encrypted at rest (also enable S3
  versioning so you can roll back a bad state write).

To point at your own infrastructure, edit the `bucket`, `region`, and
`dynamodb_table` values in `backend.tf`.

## Version pinning

Everything is pinned so nothing changes underneath you:

- **AWS provider** is pinned with `= 6.69.0` in `modules/ec2-fleet-module/versions.tf`
  and in `ec2/server-fleet/main.tf`. The `=` means "only this exact version".
- The generated `ec2/server-fleet/.terraform.lock.hcl` is committed, so every
  machine resolves the exact same provider build.
- **The module itself** should be pinned by Git tag when you call it from
  another project. A local folder (`../../modules/ec2-fleet-module`) cannot have a
  version number in Terraform, so use a Git source with a `ref`:

  ```hcl
  module "ec2_fleet" {
    source = "git::https://github.com/your-org/terraform-aws-ec2-fleet.git//modules/ec2-fleet-module?ref=v1.0.0"
    # ...
  }
  ```

  `ref=v1.0.0` locks the module to that release. Change `ref` only when you
  mean to upgrade.

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| `instances` | The fleet. Key = server name; value = that server's settings. | `map(object(...))` | yes |
| `environment` | Environment tag applied to every server. | `string` | yes |
| `owner` | Owner tag applied to every server. | `string` | yes |
| `subnet_id` | Subnet to launch into (default subnet if unset). | `string` | no |
| `security_group_ids` | Security groups attached to every server. | `list(string)` | no |
| `tags` | Extra tags merged onto every server. | `map(string)` | no |

### `instances` object

| Field | Description |
|-------|-------------|
| `instance_type` | EC2 instance type. |
| `root_volume_type` | One of `standard`, `gp2`, `gp3`, `io1`, `io2`. |
| `root_volume_size` | Root volume size in GB. |
| `key_name` | EC2 key pair name. |
| `ami` | (Optional) AMI ID; defaults to the newest Amazon Linux 2023. Set this to use a custom AMI. |
| `iops` | (Optional) Required for `io1`/`io2` root volumes. |
| `protect` | (Optional) Guard the server against delete. Default `false`. |

The validation rules enforce three things: `root_volume_type` must be one of
the allowed values, **every** server must use a different `root_volume_type`,
and every `io1`/`io2` server must set `iops`.

## Outputs

| Name | Description |
|------|-------------|
| `instance_ids` | Map of server name to EC2 instance ID. |
| `instance_private_ips` | Map of server name to private IP address. |

## Caveats

- Servers need an existing key pair and (optionally) security groups and a
  subnet; the module does not create them.
- `root_volume_type` must be a valid value, all root volume types must be
  unique, and `io1`/`io2` root volumes require `iops`; variable validations
  enforce all three.
- In the 5-server example, all five root volume types are distinct: `standard`
  (web-01), `gp2` (app-01), `gp3` (cache-01), `io2` (search-01), and `io1`
  (db-01). `standard` is paired with a pre-Nitro `t2.micro` because modern
  Nitro instance types cannot boot from magnetic volumes.
- `web-01` in the example sets a custom `ami` to show how to override the
  default Amazon Linux 2023 image.
