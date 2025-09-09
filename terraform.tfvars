region             = "us-east-1"
cluster_name       = "eks-fy-cluster"
vpc_id             = "vpc-01a168ff311562657"
private_subnet_ids = ["subnet-0a5f0a7603e136990", "subnet-0e6e2312a95a45f7a", "subnet-042a6867c8732efb6"]

# 节点配置
node_instance_type = "t3.micro"
desired_size = 4
min_size = 4
max_size = 6

# Karpenter配置
karpenter_version = "v0.32.1"
