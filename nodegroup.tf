data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_launch_template" "ubuntu_lt" {
  name_prefix   = "ubuntu-eks-node-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.node_instance_type
  key_name      = "" # 生产环境建议使用key pair

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
  node_role_arn   = module.eks.eks_managed_node_groups["initial"].iam_role_arn
  subnet_ids      = var.private_subnet_ids

  # 使用自定义AMI时需要设置为CUSTOM
  ami_type       = "CUSTOM"
  instance_types = [var.node_instance_type]
  disk_size      = 20

  # 通过launch template指定Ubuntu AMI
  launch_template {
    id      = aws_launch_template.ubuntu_lt.id
    version = aws_launch_template.ubuntu_lt.latest_version
  }

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  depends_on = [
    module.eks
  ]

  tags = {
    Name        = "initial-ubuntu-node"
    Environment = "production"
  }
}