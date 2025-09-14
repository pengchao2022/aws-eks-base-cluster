terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_caller_identity" "current" {}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name                   = var.cluster_name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = true

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # EKS Managed Node Group not used (using Karpenter instead)
  eks_managed_node_groups = {}

  # Enable IAM Role for Service Account (IRSA)
  enable_irsa = true

  # 禁用 CoreDNS 自动安装
  cluster_addons = {
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  tags = {
    Environment              = "dev"
    Terraform                = "true"
    "karpenter.sh/discovery" = var.cluster_name
  }
}

# 使用 Helm 安装 Karpenter（包含 CRDs）
resource "null_resource" "install_karpenter" {
  triggers = {
    cluster_endpoint = module.eks.cluster_endpoint
  }

  provisioner "local-exec" {
    command = <<-EOT
      # 更新 kubeconfig
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}
      
      # 创建 Karpenter 命名空间
      kubectl create namespace karpenter --dry-run=client -o yaml | kubectl apply -f -
      
      # 添加和更新 Helm 仓库
      helm repo add karpenter https://charts.karpenter.sh
      helm repo update
      
      # 安装 Karpenter（包含 CRDs）
      helm upgrade --install karpenter karpenter/karpenter \
        --namespace karpenter \
        --version v0.28.1 \
        --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"=${module.karpenter_irsa.iam_role_arn} \
        --set clusterName=${var.cluster_name} \
        --set clusterEndpoint=${module.eks.cluster_endpoint} \
        --set aws.defaultInstanceProfile=${aws_iam_instance_profile.karpenter.name} \
        --set installCRDs=true  # 确保 CRDs 被安装
      
      # 等待 Karpenter 就绪
      for i in {1..10}; do
        echo "Waiting for Karpenter to be ready (attempt $i/10)..."
        if kubectl wait --for=condition=Available deployment/karpenter -n karpenter --timeout=60s; then
          echo "Karpenter is ready!"
          break
        else
          echo "Karpenter not ready yet, checking pod status..."
          kubectl get pods -n karpenter
          if [ $i -eq 10 ]; then
            echo "Karpenter failed to become ready after 10 attempts"
            # 不退出，继续执行，因为 Karpenter 可能在其他资源创建后才会就绪
            break
          fi
          sleep 30
        fi
      done
    EOT
  }

  depends_on = [module.eks, module.karpenter_irsa, aws_iam_instance_profile.karpenter]
}

# 等待 CRDs 就绪
resource "null_resource" "wait_for_crds" {
  triggers = {
    karpenter_installed = null_resource.install_karpenter.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      # 更新 kubeconfig
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}
      
      # 等待 CRDs 就绪
      echo "Waiting for Karpenter CRDs to be ready..."
      for i in {1..10}; do
        if kubectl get crd provisioners.karpenter.sh >/dev/null 2>&1 && \
           kubectl get crd awsnodetemplates.karpenter.k8s.aws >/dev/null 2>&1; then
          echo "Karpenter CRDs are ready!"
          break
        else
          echo "CRDs not ready yet (attempt $i/10)..."
          if [ $i -eq 10 ]; then
            echo "CRDs failed to become ready after 10 attempts"
            exit 1
          fi
          sleep 10
        fi
      done
    EOT
  }

  depends_on = [null_resource.install_karpenter]
}

# 使用本地执行器来创建 Karpenter 资源
resource "null_resource" "create_karpenter_resources" {
  triggers = {
    crds_ready = null_resource.wait_for_crds.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}
      
      # 创建 Provisioner
      cat <<EOF | kubectl apply -f -
      apiVersion: karpenter.sh/v1alpha5
      kind: Provisioner
      metadata:
        name: default
      spec:
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["on-demand"]
          - key: "node.kubernetes.io/instance-type"
            operator: In
            values: ${jsonencode(var.instance_types)}
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
        providerRef:
          name: default
        ttlSecondsAfterEmpty: 30
        limits:
          resources:
            cpu: 1000
        consolidation:
          enabled: true
      EOF
      
      # 创建 AWSNodeTemplate
      cat <<EOF | kubectl apply -f -
      apiVersion: karpenter.k8s.aws/v1alpha1
      kind: AWSNodeTemplate
      metadata:
        name: default
      spec:
        subnetSelector:
          karpenter.sh/discovery: ${var.cluster_name}
        securityGroupSelector:
          karpenter.sh/discovery: ${var.cluster_name}
        tags:
          karpenter.sh/discovery: ${var.cluster_name}
          Environment: "dev"
      EOF
      
      # 创建测试部署
      cat <<EOF | kubectl apply -f -
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: inflate
      spec:
        replicas: ${var.desired_size}
        selector:
          matchLabels:
            app: inflate
        template:
          metadata:
            labels:
              app: inflate
          spec:
            terminationGracePeriodSeconds: 0
            containers:
              - name: inflate
                image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
                resources:
                  requests:
                    cpu: 1
      EOF
    EOT
  }

  depends_on = [null_resource.wait_for_crds]
}

# 使用 Helm 安装 CoreDNS
resource "null_resource" "install_coredns" {
  triggers = {
    cluster_endpoint = module.eks.cluster_endpoint
  }

  provisioner "local-exec" {
    command = <<-EOT
      # 等待集群就绪
      sleep 30
      
      # 更新 kubeconfig
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}
      
      # 使用 Helm 安装 CoreDNS
      helm repo add eks https://aws.github.io/eks-charts
      helm repo update
      
      helm upgrade --install coredns eks/coredns \
        --namespace kube-system \
        --set serviceAccount.name=coredns \
        --set service.annotations."prometheus\\.io/port"=9153 \
        --set service.annotations."prometheus\\.io/scrape"=true \
        --set service.clusterIP=10.100.0.10
    EOT
  }

  depends_on = [module.eks, null_resource.install_karpenter]
}