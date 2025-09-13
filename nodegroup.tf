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

  # 使用自定义 AMI
  ami_type = "CUSTOM"

  # 使用启动模板
  launch_template {
    id      = aws_launch_template.ubuntu_node.id
    version = "$Latest"
  }

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.karpenter_node_worker,
    aws_iam_role_policy_attachment.karpenter_node_cni
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
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==BOUNDARY=="

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
set -ex

# 设置主机名
echo "Setting hostname..."
hostnamectl set-hostname ubuntu-node

# 安装 AWS CLI（如果需要）
apt-get update
apt-get install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# 安装 SSM Agent
apt-get update
apt-get install -y snapd
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent

# 安装容器运行时
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# 安装 kubelet、kubeadm、kubectl
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg

# 添加 Kubernetes 仓库
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet=1.28.0-1.1 kubeadm=1.28.0-1.1 kubectl=1.28.0-1.1
apt-mark hold kubelet kubeadm kubectl

# 配置 kubelet
mkdir -p /etc/systemd/system/kubelet.service.d
cat <<EOF > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS \$KUBELET_KUBEADM_ARGS \$KUBELET_EXTRA_ARGS
EOF

# 获取实例信息
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
REGION=$${AZ:0:$${#AZ}-1}

# 设置节点标签
cat <<EOF > /etc/kubernetes/kubelet.env
KUBELET_EXTRA_ARGS=--node-labels=node.kubernetes.io/instance-type=${var.node_instance_type},topology.kubernetes.io/zone=$$AZ,topology.kubernetes.io/region=$$REGION,kubernetes.io/arch=amd64,kubernetes.io/os=linux,karpenter.sh/provisioner-name=default --register-with-taints= --cloud-provider=aws
EOF

echo 'source /etc/kubernetes/kubelet.env' >> /etc/default/kubelet

systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

--==BOUNDARY==--
EOT
  )

  tags = var.tags
}