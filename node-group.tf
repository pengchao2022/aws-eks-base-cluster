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

# 创建单个Nodegroup，包含所有4个实例
resource "aws_eks_node_group" "python_dev_nodes" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "spring-dev-nodegroup"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.private_subnet_ids

  ami_type       = "AL2_x86_64"
  capacity_type  = "ON_DEMAND"
  instance_types = [var.instance_type]

  scaling_config {
    desired_size = var.node_count
    max_size     = var.node_count
    min_size     = var.node_count
  }

  labels = {
    environment = "dev"
    node-type   = "spring-dev"
  }

  tags = merge(var.tags, {
    Name        = "spring-dev-nodegroup"
    Environment = "dev"
  })

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly
  ]
}

# 使用null_resource和local-exec来设置实例名称（更可靠）
resource "null_resource" "set_instance_names" {
  triggers = {
    nodegroup_name = aws_eks_node_group.python_dev_nodes.node_group_name
    node_count     = var.node_count
    cluster_name   = var.cluster_name
  }

  provisioner "local-exec" {
    command = <<EOT
      #!/bin/bash
      set -e
      
      # 等待节点创建完成
      echo "Waiting for EKS nodes to be ready..."
      sleep 60
      
      # 获取实例ID
      INSTANCE_IDS=$(aws ec2 describe-instances \
        --region ${var.region} \
        --filters "Name=tag:eks:nodegroup-name,Values=${aws_eks_node_group.python_dev_nodes.node_group_name}" "Name=instance-state-name,Values=running" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text)
      
      echo "Found instances: $INSTANCE_IDS"
      
      # 为每个实例设置名称
      COUNT=1
      for INSTANCE_ID in $INSTANCE_IDS; do
        echo "Setting Name tag for $INSTANCE_ID: ${var.cluster_name}-$COUNT"
        aws ec2 create-tags \
          --region ${var.region} \
          --resources $INSTANCE_ID \
          --tags Key=Name,Value=${var.cluster_name}-$COUNT
        COUNT=$((COUNT+1))
      done
    EOT
  }

  depends_on = [aws_eks_node_group.spring_dev_nodes]
}