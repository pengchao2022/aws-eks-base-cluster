# Manual node group for Ubuntu nodes (not using ASG)
resource "aws_eks_node_group" "ubuntu_nodes" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "ubuntu-manual-nodes"
  node_role_arn   = aws_iam_role.karpenter_node.arn
  subnet_ids      = var.private_subnets

  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_count
    max_size     = var.node_count
  }

  ami_type       = "CUSTOM"
  instance_types = [var.node_instance_type]

  # Use the specified Ubuntu AMI
  launch_template {
    id      = aws_launch_template.ubuntu_node.id
    version = "$Latest"
  }

  depends_on = [
    module.eks
  ]

  tags = merge(var.tags, {
    "karpenter.sh/discovery" = var.cluster_name
  })
}

resource "aws_launch_template" "ubuntu_node" {
  name_prefix   = "ubuntu-node-${var.cluster_name}-"
  image_id      = var.ubuntu_ami_id
  instance_type = var.node_instance_type

  # 不指定密钥对，使用 SSM Session Manager 进行访问
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.tags, {
      Name                                        = "ubuntu-node-${var.cluster_name}"
      "karpenter.sh/discovery"                    = var.cluster_name
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(var.tags, {
      Name                                        = "ubuntu-node-${var.cluster_name}"
      "karpenter.sh/discovery"                    = var.cluster_name
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    })
  }

  user_data = base64encode(<<-EOT
#!/bin/bash
set -ex

# Install required packages
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg

# Add Kubernetes apt repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install kubelet, kubeadm, kubectl
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Configure kubelet
echo "KUBELET_EXTRA_ARGS=--node-ip=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)" > /etc/default/kubelet

systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet
EOT
  )

  tags = var.tags
}