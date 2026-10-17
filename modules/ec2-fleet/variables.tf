# One map (a named list) that describes every server we want.
# Add or remove a block in this map and the servers change to match.
# No need to copy/paste resource blocks per server.
variable "instances" {
  description = "The fleet. Key = server name; value = that server's settings."
  type = map(object({
    instance_type    = string                # e.g. "t3.micro"
    root_volume_type = string                # standard, gp2, gp3, io1, or io2
    root_volume_size = number                # size of the disk in GB
    key_name         = string                # which SSH key pair unlocks this server
    ami              = optional(string)      # optional: leave out to use the newest Amazon Linux
    iops             = optional(number)      # only needed for io1 / io2 disks
    protect          = optional(bool, false) # true = stop Terraform deleting it
  }))

  # Friendly check: catch typos before we ever talk to AWS.

  validation {
    condition = (
      anytrue([
        for name, cfg in var.instances :
        contains(["io1", "io2"], cfg.root_volume_type)
      ])
      &&
      alltrue([
        for name, cfg in var.instances :
        !contains(["io1", "io2"], cfg.root_volume_type) || cfg.iops != null
      ])
    )

    error_message = "At least one instance must use io1 or io2, and every io1/io2 instance must specify iops."
  }
}

# Stamped onto every server as the "Environment" tag.
variable "environment" {
  description = "Which environment this is, e.g. dev, staging, prod."
  type        = string
}

# Stamped onto every server as the "Owner" tag.
variable "owner" {
  description = "Who owns this fleet, e.g. platform-team."
  type        = string
}

# Where to put the servers. Leave blank to use the default subnet.
variable "subnet_id" {
  description = "Subnet to launch the servers into."
  type        = string
  default     = null
}

# Firewall rules to attach to every server.
variable "security_group_ids" {
  description = "Security group IDs to attach to every server."
  type        = list(string)
  default     = []
}

# Any extra tags you want on every server.
variable "tags" {
  description = "Extra tags to add to every server."
  type        = map(string)
  default     = {}
}
