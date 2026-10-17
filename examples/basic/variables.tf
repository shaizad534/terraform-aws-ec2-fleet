variable "region" {
  description = "AWS region to deploy the example into."
  type        = string
  default     = "us-east-1"
}

variable "security_group_ids" {
  description = "Security group IDs attached to every instance."
  type        = list(string)
  default     = []
}

variable "instances" {
  description = "Fleet definition passed straight through to the module."
  type = map(object({
    instance_type    = string
    root_volume_type = string
    root_volume_size = number
    key_name         = string
    ami              = optional(string)
    iops             = optional(number)
    protect          = optional(bool, false)
  }))
}
