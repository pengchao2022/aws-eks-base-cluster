data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

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
    # This node group will be used for system workloads and Karpenter
    initial = {
      instance_types = [var.node_instance_type]
      ami_type       = "AL2_x86_64" # Using AL2 for the initial node group

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

# IAM role for Karpenter controller
resource "aws_iam_role" "karpenter_controller" {
  name = "karpenter-controller-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${module.eks.oidc_provider}:sub" = "system:serviceaccount:karpenter:karpenter"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_ssm" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_ec2" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_eks" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Karpenter node IAM role
resource "aws_iam_role" "karpenter_node" {
  name = "karpenter-node-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ec2" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "karpenter-node-${var.cluster_name}"
  role = aws_iam_role.karpenter_node.name

  tags = var.tags
}

# 安全组规则允许节点间通信
resource "aws_security_group_rule" "node_to_node" {
  description              = "Allow node to node communication"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = module.eks.cluster_primary_security_group_id
  source_security_group_id = module.eks.cluster_primary_security_group_id
  type                     = "ingress"
}