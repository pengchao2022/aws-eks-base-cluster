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

  cluster_addons = {
    coredns = {
      most_recent = true
    }
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

# 使用本地执行器来安装 Karpenter，而不是使用 provider 配置
resource "null_resource" "install_karpenter" {
  triggers = {
    cluster_endpoint = module.eks.cluster_endpoint
    cluster_ca_cert  = module.eks.cluster_certificate_authority_data
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}
      helm repo add karpenter https://charts.karpenter.sh
      helm repo update
      helm upgrade --install karpenter karpenter/karpenter \
        --namespace karpenter \
        --create-namespace \
        --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${module.karpenter_irsa.iam_role_arn} \
        --set clusterName=${var.cluster_name} \
        --set clusterEndpoint=${module.eks.cluster_endpoint} \
        --set aws.defaultInstanceProfile=${aws_iam_instance_profile.karpenter.name} \
        --version 0.32.1
    EOT
  }

  depends_on = [module.eks, module.karpenter_irsa, aws_iam_instance_profile.karpenter]
}

# 使用本地执行器来创建 Karpenter 资源
resource "null_resource" "create_karpenter_resources" {
  triggers = {
    karpenter_installed = null_resource.install_karpenter.id
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

  depends_on = [null_resource.install_karpenter]
}