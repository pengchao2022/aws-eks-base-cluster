module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name                   = var.cluster_name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = true

  # 完全禁用CoreDNS安装，只安装必要的组件
  cluster_addons = {
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    # 注意：这里完全移除了coredns的配置
  }

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # 禁用EKS模块自动创建节点组，我们将手动创建
  eks_managed_node_groups = {}

  # EKS集群安全组
  cluster_security_group_additional_rules = {
    egress_nodes_ephemeral_ports_tcp = {
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  # 启用IAM角色访问配置
  create_aws_auth_configmap = true
  manage_aws_auth_configmap = true

  # OIDC身份提供者配置（Karpenter需要）
  enable_irsa = true

  tags = {
    Environment = "production"
  }

  cluster_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}

# 为Karpenter添加必要的标签到子网
resource "aws_ec2_tag" "karpenter_subnet_tags" {
  for_each    = toset(var.private_subnet_ids)
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

# 为Karpenter添加必要的标签到安全组
resource "aws_ec2_tag" "karpenter_sg_tags" {
  resource_id = module.eks.node_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}