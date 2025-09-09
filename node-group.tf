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

# 创建启动模板来指定Ubuntu AMI，并通过用户数据设置主机名
resource "aws_launch_template" "ubuntu_eks" {
  name_prefix   = "${var.cluster_name}-ubuntu-"
  image_id      = "ami-0c02fb55956c7d316" # Ubuntu 20.04 LTS us-east-1
  instance_type = var.instance_type

  # 用户数据脚本，用于动态设置主机名
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -ex
    
    # 获取实例的私有IP最后一位作为序号
    IP=$(hostname -I | awk '{print $1}')
    SEQUENCE=$(echo $IP | awk -F. '{print $4}')
    
    # 设置主机名
    hostnamectl set-hostname ${var.cluster_name}-$SEQUENCE
    
    # 更新/etc/hosts
    echo "127.0.0.1 ${var.cluster_name}-$SEQUENCE" >> /etc/hosts
    echo "$IP ${var.cluster_name}-$SEQUENCE" >> /etc/hosts
    
    # 确保EKS bootstrap脚本仍然执行
    /etc/eks/bootstrap.sh ${var.cluster_name}
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Environment = "dev"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Environment = "dev"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 创建单个Nodegroup，包含所有4个实例
resource "aws_eks_node_group" "python_dev_nodes" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "python-dev-nodegroup"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.private_subnet_ids

  # 使用启动模板
  launch_template {
    id      = aws_launch_template.ubuntu_eks.id
    version = aws_launch_template.ubuntu_eks.latest_version
  }

  scaling_config {
    desired_size = var.node_count
    max_size     = var.node_count
    min_size     = var.node_count
  }

  labels = {
    environment = "dev"
    node-type   = "python-dev"
  }

  tags = merge(var.tags, {
    Name        = "python-dev-nodegroup"
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

# 创建EC2实例名称的null资源（用于输出）
resource "null_resource" "instance_names" {
  count = var.node_count

  triggers = {
    instance_name = "${var.cluster_name}-${count.index + 1}"
  }
}