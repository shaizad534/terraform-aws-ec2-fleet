# terraform-aws-ec2-fleet

A small, easy-to-read Terraform module that creates a fleet of EC2 servers from
**one map variable**. Each server can have its own instance type, root volume
type, root volume size, and key pair.

- All servers are created with `for_each` from the single `instances` map.
- Servers flagged `protect = true` are guarded with
  `lifecycle { prevent_destroy = true }`.
- Every server is tagged with `Name`, `Environment`, and `Owner`.
- A validation rule requires **at least one** server to use an `io1`/`io2`
  volume, and any `io1`/`io2` server to set `iops`.
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

Run the example:

```bash
cd ec2/server-fleet
terraform init
terraform plan
terraform apply
```

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

The validation rule enforces two things: **at least one** server must use an
`io1`/`io2` root volume, and every `io1`/`io2` server must set `iops`.

## Outputs

| Name | Description |
|------|-------------|
| `instance_ids` | Map of server name to EC2 instance ID. |
| `instance_private_ips` | Map of server name to private IP address. |

## Caveats

- Servers need an existing key pair and (optionally) security groups and a
  subnet; the module does not create them.
- `io1`/`io2` root volumes require `iops`, and at least one server must use an
  `io1`/`io2` volume; a variable validation enforces both.
- In the 5-server example, `db-01` is the only server using a provisioned-IOPS
  volume (`io1`). The rest use `standard`, `gp2`, and `gp3`. `standard` is
  paired with a pre-Nitro `t2.micro` because modern Nitro instance types cannot
  boot from magnetic volumes.
- `web-01` in the example sets a custom `ami` to show how to override the
  default Amazon Linux 2023 image.
