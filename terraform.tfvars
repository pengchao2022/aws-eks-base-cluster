region          = "us-east-1"
cluster_name    = "spring-eks-cluster"
cluster_version = "1.28"
vpc_id          = "vpc-0c6781da1e3098582"
private_subnets = [
  "subnet-05d4e1497d4c92999",
  "subnet-044e65ebeca04ffc7",
  "subnet-0d5abc2715e416f7a",
]
ubuntu_ami_id      = "ami-0f8e81a3da6e2510a"
node_instance_type = "t3.micro"
node_count         = 4

# Tags
tags = {
  Environment = "dev"
  Project     = "spring-dev"
  Terraform   = "true"
}