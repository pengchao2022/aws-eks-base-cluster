region             = "us-east-1"
cluster_name       = "dev-eks-cls-2"
node_count         = 4
node_ami           = "ami-0fc5d935ebf8bc3bc"
node_instance_type = "t3.micro"
vpc_id             = "vpc-0dd60e0efc5baa3af"
private_subnet_ids = [
  "subnet-0db3ff0a8f70ef7d2",
  "subnet-0b5e211de50e7f448",
  "subnet-0625f2efa2c32ba44",
]


