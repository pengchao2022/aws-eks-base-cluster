# 直接使用已知的Ubuntu 20.04 AMI ID（us-east-1区域）
locals {
  ubuntu_ami = "ami-053b0d53c279acc90" # Ubuntu 20.04 LTS us-east-1
}

resource "aws_launch_template" "ubuntu_lt" {
  name_prefix   = "ubuntu-eks-node-"
  image_id      = local.ubuntu_ami
  instance_type = var.node_instance_type

  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -ex
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg
    apt-get install -y awscli
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
    echo 'net.bridge.bridge-nf-call-iptables=1' >> /etc/sysctl.conf
    echo 'net.bridge.bridge-nf-call-ip6tables=1' >> /etc/sysctl.conf
    sysctl -p
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
      Environment = var.environment
      Project     = "eks-karpenter"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name        = "eks-ubuntu-node"
      Environment = var.environment
      Project     = "eks-karpenter"
    }
  }

  tags = {
    Environment = var.environment
    Project     = "eks-karpenter"
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

  launch_template {
    id      = aws_launch_template.ubuntu_lt.id
    version = aws_launch_template.ubuntu_lt.latest_version
  }

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  instance_types = [var.node_instance_type]

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
    Environment = var.environment
    Project     = "eks-karpenter"
  }
}