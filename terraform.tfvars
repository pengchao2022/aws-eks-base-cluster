region       = "us-east-1"
cluster_name = "spring-eks-cluster"
vpc_id       = "vpc-0dc967abca0d7d131"
private_subnet_ids = [
  "subnet-0f2411b92105fbda0",
  "subnet-03da79fc5ec691939",
  "subnet-05f5e7f1a3af64705",
]
eks_version        = "1.28"
node_instance_type = "t3.micro"
desired_size       = 4
max_size           = 4
min_size           = 4