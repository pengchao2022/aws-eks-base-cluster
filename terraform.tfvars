region = "us-east-1"
vpc_id = "vpc-0dd60e0efc5baa3af"
private_subnet_ids = [
  "subnet-0db3ff0a8f70ef7d2",
  "subnet-0b5e211de50e7f448",
  "subnet-0625f2efa2c32ba44",
]
cluster_name  = "js-dev-eks"
node_count    = 4
instance_type = "t3.micro"

# Tags
tags = {
  Environment = "dev"
  Project     = "js-dev"
  Terraform   = "true"
}