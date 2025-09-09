# 方法1：使用SSM参数获取最新的EKS优化Ubuntu AMI
data "aws_ssm_parameter" "ubuntu_eks_ami" {
  name = "/aws/service/canonical/ubuntu/eks/20.04/1.28/latest/amd64/hvm/ebs-gp2/ami-id"
}

# 方法2：备用方案 - 使用标准的Ubuntu 20.04 AMI
data "aws_ami" "ubuntu_20_04" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# 选择可用的AMI
locals {
  node_ami = try(data.aws_ssm_parameter.ubuntu_eks_ami.value, data.aws_ami.ubuntu_20_04.id)
}

resource "aws_launch_template" "ubuntu_lt" {
  name_prefix   = "ubuntu-eks-node-"
  image_id      = local.node_ami
  instance_type = var.node_instance_type

  # 添加用户数据以确保节点正确加入集群
  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -ex
    # 等待cloud-init完成
    cloud-init status --wait
    # 安装必要的组件
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl
    # 设置主机名
    hostnamectl set-hostname $(curl -s http://169.254.169.254/latest/meta-data/local-hostname)
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
    ignore_changes        = [image_id]
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

  # 实例类型
  instance_types = [var.node_instance_type]

  # 更新配置
  update_config {
    max_unavailable = 1
  }

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry_readonly
  ]

  tags = {
    Name        = "initial-ubuntu-node"
    Environment = "production"
  }
}