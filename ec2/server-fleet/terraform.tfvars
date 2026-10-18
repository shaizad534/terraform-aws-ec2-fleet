# Single input variable drives all five instances. Every instance differs in
# instance type, root volume type, root volume size, and key pair.
instances = {
  web-01 = {
    instance_type    = "t2.micro" # pre-Nitro: supports 'standard' (magnetic) root
    root_volume_type = "standard"
    root_volume_size = 8
    key_name         = "dev-key-web"
    ami              = "ami-0b6d9d3d33ba97d99"
  }

  app-01 = {
    instance_type    = "t3.small"
    root_volume_type = "gp2"
    root_volume_size = 30
    key_name         = "dev-key-app"
  }

  cache-01 = {
    instance_type    = "m5.large"
    root_volume_type = "gp3"
    root_volume_size = 40
    key_name         = "dev-key-cache"
  }

  search-01 = {
    instance_type    = "m5.xlarge"
    root_volume_type = "io2" # provisioned-IOPS SSD
    root_volume_size = 100
    key_name         = "dev-key-search"
    iops             = 3000
  }

  db-01 = {
    instance_type    = "r5.xlarge"
    root_volume_type = "io1" # provisioned-IOPS SSD
    root_volume_size = 200
    key_name         = "dev-key-db"
    iops             = 5000
    protect          = true # guarded against destroy (see NOTES.md)
  }
}

# Optional: attach security groups to the fleet.
# security_group_ids = ["sg-0123456789abcdef0"]
