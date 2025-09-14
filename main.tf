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

  eks_managed_node_groups = {}
  enable_irsa             = true

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

# 安装 Karpenter v0.16.3
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

      echo "Waiting for Karpenter deployment to be available..."
      kubectl wait --for=condition=Available deployment/karpenter -n karpenter --timeout=300s

      echo "Waiting for Karpenter pod to be Ready..."
      kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=karpenter -n karpenter --timeout=180s
    EOT
  }

  depends_on = [module.eks, module.karpenter_irsa, aws_iam_instance_profile.karpenter]
}

resource "null_resource" "wait_for_crds" {
  triggers = {
    karpenter_installed = null_resource.install_karpenter.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}
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

resource "null_resource" "create_karpenter_resources" {
  triggers = {
    crds_ready = null_resource.wait_for_crds.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}

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

resource "null_resource" "install_coredns" {
  triggers = {
    cluster_endpoint = module.eks.cluster_endpoint
  }

  provisioner "local-exec" {
    command = <<-EOT
      sleep 30
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}

      helm repo add coredns https://coredns.github.io/helm
      helm repo update

      helm upgrade --install coredns coredns/coredns \
        --namespace kube-system \
        --set serviceAccount.name=coredns \
        --set service.annotations."prometheus\\.io/port"="9153" \
        --set service.annotations."prometheus\\.io/scrape"="true"
    EOT
  }

  depends_on = [module.eks, null_resource.install_karpenter]
}
