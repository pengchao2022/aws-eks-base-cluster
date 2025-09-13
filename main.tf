module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name                   = var.cluster_name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = true

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets

  # 禁用所有 EKS 管理的插件，包括 CoreDNS
  cluster_addons = {
    coredns = {
      most_recent = false
      preserve    = false
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    # 使用 Amazon Linux 2 作为初始节点组（用于系统工作负载和 Karpenter）
    initial = {
      instance_types = ["t3.medium"]
      ami_type       = "AL2_x86_64" # 必须使用 AL2

      min_size     = 2
      max_size     = 3
      desired_size = 2

      # 确保节点有足够的标签用于 Karpenter 发现
      labels = {
        "karpenter.sh/discovery" = var.cluster_name
      }

      tags = {
        "karpenter.sh/discovery" = var.cluster_name
      }
    }
  }

  tags = merge(var.tags, {
    Environment              = "prod"
    Terraform                = "true"
    "karpenter.sh/discovery" = var.cluster_name
  })
}