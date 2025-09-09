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

  # 禁用 KMS key 创建
  create_kms_key = false

  # 集群认证配置
  aws_auth_users = [
    {
      userarn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/admin"
      username = "admin"
      groups   = ["system:masters"]
    }
  ]

  cluster_addons = {}

  tags = {
    Environment = "development"
  }
}