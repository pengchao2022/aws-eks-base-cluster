region = "us-east-1"
vpc_id = "vpc-0f023780707c8b12e"
private_subnet_ids = [
  "subnet-051a38ff0c9e2fe85",
  "subnet-02566e5ee80de2235",
  "subnet-0ece0150b4e3c319a",
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