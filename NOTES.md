# Notes

## Which instance is protected from deletion

`db-01` (instance type `r5.xlarge`, root volume `io1` 200 GiB) is the instance
that carries `prevent_destroy = true`.

## Why `db-01`

- **Highest blast radius.** It is the fleet's data node. Losing it is the most
  disruptive failure in this group.
- **Stateful + expensive to rebuild.** Its root volume is a provisioned-IOPS
  `io1` volume (5000 IOPS). Recreating it means re-provisioning storage, data
  restore, and re-establishing access, not just relaunching a stateless app box.
- **Most costly mistake.** A stray `terraform destroy` or a refactor that drops
  the instance from state would silently delete production data. The other four
  instances are effectively stateless and cheap to recreate.

The guard is intentionally the smallest possible safety net: it stops the one
delete that actually hurts, without making routine `terraform destroy` require
editing code for the disposable instances.

## How the guard is implemented

`prevent_destroy` in Terraform must be a literal `true`/`false`; it cannot be a
computed expression. The module therefore splits the single `var.instances` map
into two `for_each` resource blocks:

- `aws_instance.this` — all instances with `protect = false`.
- `aws_instance.guarded` — instances with `protect = true`, which carry the
  `lifecycle { prevent_destroy = true }` block.

Everything is still driven by the one `instances` variable; only the lifecycle
attribute lives in a dedicated block. The guarded instance also sets
`disable_api_termination = true` for defense-in-depth at the AWS API level.

## Removing the guard (when you genuinely need to)

1. Set `protect = false` for `db-01` in `terraform.tfvars` and apply, then
2. `terraform state rm` the resource (or apply again) before destroying.

Because `prevent_destroy` is evaluated on the destroy plan, the flag must be
cleared and applied first.
