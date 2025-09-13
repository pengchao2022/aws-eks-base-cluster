module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = var.vpc_id
  subnet_ids      = var.private_subnets

  # 禁用 CoreDNS
  cluster_addons = {
    coredns = {
      most_recent = false
      preserve    = false
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  # 直接创建4个Amazon Linux 2节点
  eks_managed_node_groups = {
    main = {
      min_size       = var.node_count
      max_size       = var.node_count
      desired_size   = var.node_count
      instance_types = ["t3.micro"]
    }
  }

  tags = {
    Terraform = "true"
  }
}