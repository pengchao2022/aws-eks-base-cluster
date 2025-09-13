# Manual node group for Ubuntu nodes (not using ASG)
resource "aws_eks_node_group" "ubuntu_nodes" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "ubuntu-manual-nodes"
  node_role_arn   = aws_iam_role.karpenter_node.arn
  subnet_ids      = var.private_subnets

  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_count
    max_size     = var.node_count
  }

  ami_type       = "CUSTOM"
  instance_types = [var.node_instance_type]

  # Use the specified Ubuntu AMI
  launch_template {
    id      = aws_launch_template.ubuntu_node.id
    version = "$Latest"
  }

  depends_on = [
    module.eks
  ]

  tags = merge(var.tags, {
    "karpenter.sh/discovery" = var.cluster_name
  })
}

resource "aws_launch_template" "ubuntu_node" {
  name_prefix   = "ubuntu-node-${var.cluster_name}-"
  image_id      = var.ubuntu_ami_id
  instance_type = var.node_instance_type

  # 不指定密钥对，使用 SSM Session Manager 进行访问
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.tags, {
      Name                                        = "ubuntu-node-${var.cluster_name}"
      "karpenter.sh/discovery"                    = var.cluster_name
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(var.tags, {
      Name                                        = "ubuntu-node-${var.cluster_name}"
      "karpenter.sh/discovery"                    = var.cluster_name
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    })
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    cluster_name = var.cluster_name
  }))

  tags = var.tags
}