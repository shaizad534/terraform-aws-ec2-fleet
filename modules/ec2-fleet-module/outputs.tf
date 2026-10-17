# Server name -> EC2 instance ID (e.g. "web-01" = "i-0abc123").
output "instance_ids" {
  description = "Map of server name to EC2 instance ID."
  value = merge(
    { for name, instance in aws_instance.normal : name => instance.id },
    { for name, instance in aws_instance.protected : name => instance.id },
  )
}

# Server name -> private IP address.
output "instance_private_ips" {
  description = "Map of server name to private IP address."
  value = merge(
    { for name, instance in aws_instance.normal : name => instance.private_ip },
    { for name, instance in aws_instance.protected : name => instance.private_ip },
  )
}
