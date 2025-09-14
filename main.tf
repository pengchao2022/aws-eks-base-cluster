terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
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

  # Managed Node Group 控制 Node 数量和类型
  eks_managed_node_groups = {
    karpenter_nodes = {
      desired_capacity = var.desired_size
      max_capacity     = var.desired_size
      min_capacity     = var.desired_size
      instance_type    = var.instance_types[0]
      key_name         = null
    }
  }

  enable_irsa = true

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

# 安装 Karpenter Helm Chart v0.16.3
resource "null_resource" "install_karpenter" {
  triggers = {
    cluster_endpoint = module.eks.cluster_endpoint
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}
      kubectl create namespace karpenter --dry-run=client -o yaml | kubectl apply -f -
      helm repo add karpenter https://charts.karpenter.sh
      helm repo update
      helm upgrade --install karpenter karpenter/karpenter \
        --namespace karpenter \
        --version v0.16.3 \
        --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"=${module.karpenter_irsa.iam_role_arn} \
        --set clusterName=${var.cluster_name} \
        --set clusterEndpoint=${module.eks.cluster_endpoint} \
        --set aws.defaultInstanceProfile=${aws_iam_instance_profile.karpenter.name} \
        --set installCRDs=true
      # 等待 Deployment Ready
      for i in {1..20}; do
        if kubectl get deployment karpenter -n karpenter >/dev/null 2>&1; then
          if kubectl wait --for=condition=Available deployment/karpenter -n karpenter --timeout=30s; then
            echo "Karpenter Deployment ready!"
            break
          fi
        fi
        echo "Attempt $i/20: Karpenter Deployment not ready yet..."
        sleep 15
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
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}
      for i in {1..20}; do
        if kubectl get crd provisioners.karpenter.sh >/dev/null 2>&1 && \
           kubectl get crd awsnodetemplates.karpenter.k8s.aws >/dev/null 2>&1; then
          echo "CRDs ready!"
          break
        fi
        echo "Attempt $i/20: CRDs not ready yet..."
        sleep 10
      done
    EOT
  }

  depends_on = [null_resource.install_karpenter]
}

# 创建 Karpenter Provisioner 和 AWSNodeTemplate
resource "null_resource" "create_karpenter_resources" {
  triggers = {
    crds_ready = null_resource.wait_for_crds.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}
      # 等待 Karpenter Pod 就绪
      for i in {1..20}; do
        if kubectl get pods -n karpenter -l app.kubernetes.io/name=karpenter -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
          echo "Karpenter Pod is Running!"
          break
        fi
        echo "Attempt $i/20: Karpenter Pod not ready yet..."
        sleep 15
      done

      # Provisioner
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

      # AWSNodeTemplate
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
    EOT
  }

  depends_on = [null_resource.wait_for_crds]
}
