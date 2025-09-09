# 使用正确的Ubuntu EKS优化AMI
data "aws_ami" "ubuntu_eks" {
  most_recent = true
  owners      = ["amazon"] # 使用AWS官方的EKS优化AMI

  filter {
    name   = "name"
    values = ["ubuntu-eks/k8s_${var.cluster_version}/node-*-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_launch_template" "ubuntu_lt" {
  name_prefix   = "ubuntu-eks-node-"
  image_id      = data.aws_ami.ubuntu_eks.id
  instance_type = var.node_instance_type

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
      Name        = "eks-ubuntu-node"
      Environment = "production"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "initial_nodes" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "initial-ubuntu-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = var.private_subnet_ids

  # 使用启动模板而不是直接设置AMI类型
  launch_template {
    id      = aws_launch_template.ubuntu_lt.id
    version = aws_launch_template.ubuntu_lt.latest_version
  }

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  # 确保使用正确的实例类型
  instance_types = [var.node_instance_type]

  depends_on = [
    module.eks
  ]

  tags = {
    Name        = "initial-ubuntu-node"
    Environment = "production"
  }
}