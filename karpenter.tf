resource "aws_eks_node_group" "dev_nodes" {
  for_each = { for i in range(var.node_count) : "dev-node${i + 1}" => i }

  cluster_name    = module.eks.cluster_name
  node_group_name = each.key
  node_role_arn   = module.eks.cluster_iam_role_arn
  subnet_ids      = var.private_subnet_ids

  ami_type       = "CUSTOM"

  launch_template {
    id      = aws_launch_template.dev_nodes.id
    version = aws_launch_template.dev_nodes.latest_version
  }

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  tags = {
    Name = each.key
  }

  depends_on = [module.eks]
}

resource "aws_launch_template" "dev_nodes" {
  name_prefix   = "dev-node-"
  image_id      = var.node_ami
  instance_type = var.node_instance_type

  tag_specifications {
    resource_type = "instance"
    tags = {
      Environment = "development"
    }
  }
}

# 其他 karpenter 配置保持不变...
module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                          = "karpenter-controller"
  attach_karpenter_controller_policy = true
  karpenter_controller_cluster_id    = module.eks.cluster_id

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile"
  role = module.eks.cluster_iam_role_name
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = "karpenter"
  create_namespace = true
  repository       = "https://charts.karpenter.sh"
  chart            = "karpenter"
  version          = "v0.30.0"

  values = [
    <<-EOT
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter_irsa.iam_role_arn}
    settings:
      clusterName: ${module.eks.cluster_id}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.eks.cluster_id}
    EOT
  ]

  depends_on = [module.eks, module.karpenter_irsa]
}