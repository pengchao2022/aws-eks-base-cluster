module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 18.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = var.vpc_id
  subnet_ids      = var.private_subnet_ids

  # 禁用所有插件
  cluster_addons = {}

  # 禁用EKS托管节点组
  eks_managed_node_groups = {}

  # 启用公共访问
  cluster_endpoint_public_access = true

  # 启用IAM角色服务账户
  enable_irsa = true

  tags = {
    Environment = var.environment
    Project     = "eks-karpenter"
  }
}

# 为Karpenter添加必要的标签到子网
resource "aws_ec2_tag" "karpenter_subnet_tags" {
  for_each = toset(var.private_subnet_ids)

  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

resource "aws_ec2_tag" "karpenter_subnet_env_tags" {
  for_each = toset(var.private_subnet_ids)

  resource_id = each.value
  key         = "Environment"
  value       = var.environment
}