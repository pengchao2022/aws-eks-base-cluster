# 获取VPC信息
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# 创建专门的安全组给节点
resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.cluster_name}-nodes-"
  vpc_id      = var.vpc_id

  # 允许所有出站流量
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-nodes-sg"
  }
}

# 允许集群安全组访问节点
resource "aws_security_group_rule" "cluster_to_nodes" {
  description              = "Allow cluster to communicate with nodes"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  type                     = "ingress"
}

# 允许节点间通信
resource "aws_security_group_rule" "nodes_to_nodes" {
  description              = "Allow nodes to communicate with each other"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_security_group.eks_nodes.id
  type                     = "ingress"
}

# 更新节点组配置
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "main-nodes"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.private_subnets

  scaling_config {
    desired_size = 2 # 先减少到2个节点
    min_size     = 2
    max_size     = 2
  }

  ami_type       = "AL2_x86_64"
  instance_types = ["t3.micro"]
  capacity_type  = "ON_DEMAND"
  disk_size      = 20

  # 使用我们自定义的安全组
  remote_access {
    ec2_ssh_key               = null
    source_security_group_ids = [aws_security_group.eks_nodes.id]
  }

  # 添加必要的标签
  labels = {
    environment = "test"
  }

  tags = {
    Name = "${var.cluster_name}-nodes"
  }

  depends_on = [
    aws_iam_role_policy_attachment.nodes_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.nodes_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.nodes_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.nodes_AmazonSSMManagedInstanceCore,
    aws_eks_cluster.this,
  ]
}

# 添加必要的IAM策略
resource "aws_iam_role_policy_attachment" "nodes_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.nodes.name
}