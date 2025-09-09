# 使用AWS官方提供的EKS优化AMI（Amazon Linux 2）
data "aws_ssm_parameter" "amazon_eks_ami" {
  name = "/aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2/recommended/image_id"
}

resource "aws_launch_template" "amazon_linux_lt" {
  name_prefix   = "amazon-linux-eks-node-"
  image_id      = data.aws_ssm_parameter.amazon_eks_ami.value
  instance_type = var.node_instance_type
  
  # Amazon Linux 2 EKS优化AMI已经包含了所有必要的bootstrap脚本
  # 不需要额外的user_data，AMI会自动加入集群

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "eks-amazon-linux-node"
      Environment = var.environment
      Project     = "eks-karpenter"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name        = "eks-amazon-linux-node"
      Environment = var.environment
      Project     = "eks-karpenter"
    }
  }

  tags = {
    Environment = var.environment
    Project     = "eks-karpenter"
    ManagedBy   = "terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "initial_nodes" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "initial-amazon-linux-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = var.private_subnet_ids

  # 使用启动模板
  launch_template {
    id      = aws_launch_template.amazon_linux_lt.id
    version = aws_launch_template.amazon_linux_lt.latest_version
  }

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  # 添加节点标签
  labels = {
    "node.kubernetes.io/instance-type" = var.node_instance_type
    "environment" = var.environment
  }

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry_readonly,
    kubernetes_config_map.aws_auth
  ]

  tags = {
    Name        = "initial-amazon-linux-node"
    Environment = var.environment
    Project     = "eks-karpenter"
    ManagedBy   = "terraform"
  }
}

# 确保AWS auth configmap存在，让节点能够加入集群
resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = <<-EOT
      - rolearn: ${aws_iam_role.eks_node_role.arn}
        username: system:node:{{EC2PrivateDNSName}}
        groups:
          - system:bootstrappers
          - system:nodes
    EOT
  }

  depends_on = [module.eks]
}