data "aws_caller_identity" "current" {}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name # 移除引号，正确引用变量
  cluster_version = "1.28"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  cluster_addons = {}

  # 添加 KMS 配置以确保别名符合要求
  create_kms_key = true
  kms_key_aliases = {
    cluster = "alias/${var.cluster_name}-kms" # 确保别名格式正确
  }

  # 或者禁用 KMS key 创建（如果你不需要）
  # create_kms_key = false

  aws_auth_users = [
    {
      userarn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/admin"
      username = "admin"
      groups   = ["system:masters"]
    }
  ]

  tags = {
    Environment = "development"
  }
}