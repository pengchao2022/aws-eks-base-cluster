# 直接使用已知的Ubuntu 20.04 AMI ID（us-east-1区域）
locals {
  ubuntu_ami = "ami-053b0d53c279acc90" # Ubuntu 20.04 LTS us-east-1
}

resource "aws_launch_template" "ubuntu_lt" {
  name_prefix   = "ubuntu-eks-node-"
  image_id      = local.ubuntu_ami
  instance_type = var.node_instance_type

  # 使用正确的EKS bootstrap脚本
  user_data = base64encode(<<-EOT
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==BOUNDARY=="

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
set -ex

# 设置EKS集群信息
CLUSTER_NAME="${var.cluster_name}"
API_SERVER_URL="${module.eks.cluster_endpoint}"
B64_CLUSTER_CA="${module.eks.cluster_certificate_authority_data}"

# 创建bootstrap配置目录
mkdir -p /etc/eks/bootstrap

# 安装必要的依赖
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg

# 安装AWS CLI
apt-get install -y awscli

# 安装容器运行时（containerd）
apt-get install -y containerd

# 配置containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
systemctl restart containerd

# 安装kubelet、kubeadm、kubectl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet=1.28.* kubeadm=1.28.* kubectl=1.28.*
apt-mark hold kubelet kubeadm kubectl

# 配置kubelet
cat <<EOF > /etc/systemd/system/kubelet.service.d/10-eksclt.alias.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--node-ip=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4) --cloud-provider=aws"
EOF

# 设置系统参数
echo 'net.bridge.bridge-nf-call-iptables=1' >> /etc/sysctl.conf
echo 'net.bridge.bridge-nf-call-ip6tables=1' >> /etc/sysctl.conf
sysctl -p

# 等待EKS控制平面就绪
echo "等待EKS控制平面就绪..."
sleep 30

# 使用EKS引导脚本加入集群
/etc/eks/bootstrap.sh ${var.cluster_name} \
  --b64-cluster-ca ${module.eks.cluster_certificate_authority_data} \
  --apiserver-endpoint ${module.eks.cluster_endpoint}

--==BOUNDARY==--
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
    ManagedBy   = "terraform"
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
    version = "$Latest" # 使用最新版本
  }

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  # 添加必要的标签选择器
  labels = {
    "node.kubernetes.io/instance-type" = var.node_instance_type
    "environment"                      = var.environment
  }

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry_readonly,
    # 等待VPC CNI就绪
    kubernetes_config_map.aws_auth
  ]

  tags = {
    Name        = "initial-ubuntu-node"
    Environment = var.environment
    Project     = "eks-karpenter"
    ManagedBy   = "terraform"
  }
}

# 确保AWS auth configmap存在
resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = <<-EOT
      - rolearn: ${aws_iam_role.eks_node_role.arn}
        username: system:node:{{EC2PrivateDNSName}}
        groups:
          - system:bootstrappers
          - system:nodes
    EOT
  }

  depends_on = [module.eks]
}