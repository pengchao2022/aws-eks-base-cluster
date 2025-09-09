aws_account_id = "319998871902"
region         = "us-east-1"
environment    = "development"
cluster_name   = "eks-fly-clsa"
vpc_id         = "vpc-0dd60e0efc5baa3af"
private_subnet_ids = [
  "subnet-0db3ff0a8f70ef7d2",
  "subnet-0b5e211de50e7f448",
  "subnet-0625f2efa2c32ba44",
]

# 节点配置
node_instance_type = "t3.micro"
desired_size       = 4
min_size           = 4
max_size           = 6

# Karpenter配置
karpenter_version = "v0.32.1"
