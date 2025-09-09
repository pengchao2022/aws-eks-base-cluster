# IAM角色 for Node Group
resource "aws_iam_role" "node_group" {
  name = "${var.cluster_name}-node-group-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

# 创建启动模板来指定Ubuntu AMI
resource "aws_launch_template" "ubuntu_eks" {
  name_prefix   = "${var.cluster_name}-ubuntu-"
  image_id      = "ami-0c02fb55956c7d316" # Ubuntu 20.04 LTS us-east-1
  instance_type = var.instance_type

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name        = "${var.cluster_name}-ubuntu-node"
      Environment = "dev"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name        = "${var.cluster_name}-ubuntu-volume"
      Environment = "dev"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 创建指定数量的节点
resource "aws_eks_node_group" "python_dev_nodes" {
  count = var.node_count

  cluster_name    = module.eks.cluster_name
  node_group_name = "python-dev-node${count.index + 1}"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.private_subnet_ids

  # 使用启动模板
  launch_template {
    id      = aws_launch_template.ubuntu_eks.id
    version = aws_launch_template.ubuntu_eks.latest_version
  }

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  labels = {
    environment = "dev"
    node-type   = "python-dev"
  }

  tags = merge(var.tags, {
    Name        = "python-dev-node${count.index + 1}"
    Environment = "dev"
  })

  # 确保依赖关系正确
  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly
  ]
}