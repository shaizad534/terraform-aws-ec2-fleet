# If a server does not name an AMI, use the newest Amazon Linux 2023 image.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

locals {
  # Terraform only lets "prevent_destroy" be a plain true/false, so we split
  # the fleet into two groups: normal servers, and protected servers.
  normal_instances    = { for name, cfg in var.instances : name => cfg if cfg.protect == false }
  protected_instances = { for name, cfg in var.instances : name => cfg if cfg.protect == true }

  # Tags every server gets.
  common_tags = merge(var.tags, {
    Environment = var.environment
    Owner       = var.owner
  })
}

# ---------------------------------------------------------------------------
# One SSH key pair per server, created before the instances.
# ---------------------------------------------------------------------------
resource "tls_private_key" "instance" {
  for_each  = var.instances
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "instance" {
  for_each   = var.instances
  key_name   = "${var.environment}-${each.key}-key"
  public_key = tls_private_key.instance[each.key].public_key_openssh

  tags = merge(local.common_tags, { Name = "${var.environment}-${each.key}-key" })
}

# ---------------------------------------------------------------------------
# The normal servers (no delete protection).
# ---------------------------------------------------------------------------
resource "aws_instance" "normal" {
  for_each = local.normal_instances

  ami                    = coalesce(each.value.ami, data.aws_ami.al2023.id)
  instance_type          = each.value.instance_type
  key_name               = aws_key_pair.instance[each.key].key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids

  root_block_device {
    volume_type = each.value.root_volume_type
    volume_size = each.value.root_volume_size
    iops        = each.value.iops
    encrypted   = true
  }

  tags = merge(local.common_tags, { Name = each.key })
}

# ---------------------------------------------------------------------------
# The protected server(s): Terraform refuses to delete these by accident.
# ---------------------------------------------------------------------------
resource "aws_instance" "protected" {
  for_each = local.protected_instances

  ami                    = coalesce(each.value.ami, data.aws_ami.al2023.id)
  instance_type          = each.value.instance_type
  key_name               = aws_key_pair.instance[each.key].key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids

  # Extra safety: also block deletion through the AWS API.
  disable_api_termination = true

  root_block_device {
    volume_type = each.value.root_volume_type
    volume_size = each.value.root_volume_size
    iops        = each.value.iops
    encrypted   = true
  }

  tags = merge(local.common_tags, { Name = each.key })

  lifecycle {
    prevent_destroy = true
  }
}
