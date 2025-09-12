region = "us-east-1"
vpc_id = "vpc-0c6781da1e3098582"
private_subnet_ids = [
  "subnet-05d4e1497d4c92999",
  "subnet-044e65ebeca04ffc7",
  "subnet-0d5abc2715e416f7a",
]
cluster_name  = "spring-dev-eks"
node_count    = 4
instance_type = "t3.micro"

# Tags
tags = {
  Environment = "dev"
  Project     = "spring-dev"
  Terraform   = "true"
}