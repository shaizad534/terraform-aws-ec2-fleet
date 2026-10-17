# terraform-aws-ec2-fleet

A small, easy-to-read Terraform module that creates a fleet of EC2 servers from
**one map variable**. Each server can have its own instance type, root volume
type, root volume size, and key pair.

- All servers are created with `for_each` from the single `instances` map.
- Servers flagged `protect = true` are guarded with
  `lifecycle { prevent_destroy = true }`.
- Every server is tagged with `Name`, `Environment`, and `Owner`.
- Outputs are maps of `server name -> instance ID` and `server name -> private IP`.

See [NOTES.md](./NOTES.md) for which server is protected and why.

## Folder layout

```
.
├── README.md
├── NOTES.md
├── modules/
│   └── ec2-fleet/          # the reusable module
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── versions.tf
└── examples/
    └── basic/              # a runnable example that uses the module
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── terraform.tfvars
```

## Usage

```hcl
module "ec2_fleet" {
  source = "../../modules/ec2-fleet"

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
cd examples/basic
terraform init
terraform plan
terraform apply
```

## Version pinning

Everything is pinned so nothing changes underneath you:

- **AWS provider** is pinned with `= 5.60.0` in `modules/ec2-fleet/versions.tf`
  and in `examples/basic/main.tf`. The `=` means "only this exact version".
- **The module itself** should be pinned by Git tag when you call it from
  another project. A local folder (`../../modules/ec2-fleet`) cannot have a
  version number in Terraform, so use a Git source with a `ref`:

  ```hcl
  module "ec2_fleet" {
    source = "git::https://github.com/your-org/terraform-aws-ec2-fleet.git//modules/ec2-fleet?ref=v1.0.0"
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
| `ami` | (Optional) AMI ID; defaults to the newest Amazon Linux 2023. |
| `iops` | (Optional) Required for `io1`/`io2` root volumes. |
| `protect` | (Optional) Guard the server against delete. Default `false`. |

## Outputs

| Name | Description |
|------|-------------|
| `instance_ids` | Map of server name to EC2 instance ID. |
| `instance_private_ips` | Map of server name to private IP address. |

## Caveats

- Servers need an existing key pair and (optionally) security groups and a
  subnet; the module does not create them.
- `io1`/`io2` root volumes require `iops`; a variable validation enforces this.
- The 5-server example uses a different root volume type per server
  (`standard`, `gp2`, `gp3`, `io2`, `io1`). `standard` is paired with a
  pre-Nitro `t2.micro` because modern Nitro instance types cannot boot from
  magnetic volumes.
