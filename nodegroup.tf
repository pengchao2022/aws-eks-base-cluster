# 使用正确的Ubuntu EKS优化AMI查询
data "aws_ami" "ubuntu_eks" {
  most_recent = true
  owners      = ["099720109477"] # Canonical的官方Owner ID

  filter {
    name   = "name"
    values = ["ubuntu-eks/k8s_${replace(var.cluster_version, ".", "")}/*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# 如果上面的查询仍然失败，使用备用方案：最新的Ubuntu 22.04 AMI
data "aws_ami" "ubuntu_backup" {
  count = length(data.aws_ami.ubuntu_eks.id) > 0 ? 0 : 1

  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 选择可用的AMI
locals {
  node_ami = length(data.aws_ami.ubuntu_eks.id) > 0 ? data.aws_ami.ubuntu_eks.id : data.aws_ami.ubuntu_backup[0].id
}

resource "aws_launch_template" "ubuntu_lt" {
  name_prefix   = "ubuntu-eks-node-"
  image_id      = local.node_ami
  instance_type = var.node_instance_type
  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -ex
    # 安装EKS需要的组件
    apt-get update
    apt-get install -y apt-transport-https curl
    # 这里可以添加其他必要的初始化脚本
  EOT
  )

  block_device_mappings {
    device_name = "/dev/sda1"

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

  tag_specifications {
    resource_type = "volume"
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

  # 使用启动模板
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