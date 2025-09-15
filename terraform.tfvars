region       = "us-east-1"
cluster_name = "spring-eks-cluster"
vpc_id       = "vpc-0d77bddc15420d1b2"
private_subnet_ids = [
  "subnet-0264259afea746a28",
  "subnet-03a3d08d0bb499791",
  "subnet-0c44e890fac5612b4",
]
eks_version        = "1.28"
node_instance_type = "t3.micro"
desired_size       = 4
max_size           = 4
min_size           = 4