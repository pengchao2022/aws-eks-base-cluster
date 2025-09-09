# 获取当前 AWS 账户信息
data "aws_caller_identity" "current" {}

# 创建 EKS 集群
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.28"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids
  cluster_addons = {}

  tags = {
    Environment = "development"
  }
}

# 后续通过其他方式配置用户权限