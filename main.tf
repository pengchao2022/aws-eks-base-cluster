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

# 使用 kubectl 安装 Karpenter
resource "null_resource" "install_karpenter" {
  triggers = {
    cluster_endpoint = module.eks.cluster_endpoint
    cluster_ca_cert  = module.eks.cluster_certificate_authority_data
  }

  provisioner "local-exec" {
    command = <<-EOT
      # 更新 kubeconfig
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}
      
      # 创建 Karpenter 命名空间
      kubectl create namespace karpenter --dry-run=client -o yaml | kubectl apply -f -
      
      # 安装 Karpenter（使用特定版本）
      kubectl apply -f https://github.com/aws/karpenter/releases/download/v0.30.0/release.yaml
      
      # 等待 Karpenter 就绪
      kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=karpenter -n karpenter --timeout=300s
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

# 手动安装 CoreDNS
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
      
      # 安装 CoreDNS
      cat <<EOF | kubectl apply -f -
      apiVersion: v1
      kind: ServiceAccount
      metadata:
        name: coredns
        namespace: kube-system
        labels:
          eks.amazonaws.com/component: coredns
          app.kubernetes.io/name: coredns
      ---
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRole
      metadata:
        labels:
          eks.amazonaws.com/component: coredns
          app.kubernetes.io/name: coredns
        name: system:coredns
      rules:
      - apiGroups:
        - ""
        resources:
        - endpoints
        - services
        - pods
        - namespaces
        verbs:
        - list
        - watch
      - apiGroups:
        - discovery.k8s.io
        resources:
        - endpointslices
        verbs:
        - list
        - watch
      ---
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRoleBinding
      metadata:
        annotations:
          rbac.authorization.kubernetes.io/autoupdate: "true"
        labels:
          eks.amazonaws.com/component: coredns
          app.kubernetes.io/name: coredns
        name: system:coredns
      roleRef:
        apiGroup: rbac.authorization.k8s.io
        kind: ClusterRole
        name: system:coredns
      subjects:
      - kind: ServiceAccount
        name: coredns
        namespace: kube-system
      ---
      apiVersion: v1
      data:
        Corefile: |
          .:53 {
              errors
              health {
                  lameduck 5s
              }
              ready
              kubernetes cluster.local in-addr.arpa ip6.arpa {
                  pods insecure
                  fallthrough in-addr.arpa ip6.arpa
                  ttl 30
              }
              prometheus :9153
              forward . /etc/resolv.conf
              cache 30
              loop
              reload
              loadbalance
          }
        kind: ConfigMap
        metadata:
          name: coredns
          namespace: kube-system
          labels:
            eks.amazonaws.com/component: coredns
            app.kubernetes.io/name: coredns
      ---
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: coredns
        namespace: kube-system
        labels:
          eks.amazonaws.com/component: coredns
          app.kubernetes.io/name: coredns
          k8s-app: kube-dns
      spec:
        strategy:
          type: RollingUpdate
          rollingUpdate:
            maxUnavailable: 1
        selector:
          matchLabels:
            eks.amazonaws.com/component: coredns
            app.kubernetes.io/name: coredns
            k8s-app: kube-dns
        template:
          metadata:
            labels:
              eks.amazonaws.com/component: coredns
              app.kubernetes.io/name: coredns
              k8s-app: kube-dns
          spec:
            priorityClassName: system-cluster-critical
            serviceAccountName: coredns
            tolerations:
              - key: "CriticalAddonsOnly"
                operator: "Exists"
            nodeSelector:
              kubernetes.io/os: linux
            affinity:
              podAntiAffinity:
                preferredDuringSchedulingIgnoredDuringExecution:
                - weight: 100
                  podAffinityTerm:
                    labelSelector:
                      matchExpressions:
                      - key: k8s-app
                        operator: In
                        values: ["kube-dns"]
                    topologyKey: kubernetes.io/hostname
            containers:
            - name: coredns
              image: public.ecr.aws/eks/coredns:v1.10.1-eksbuild.4
              imagePullPolicy: IfNotPresent
              resources:
                limits:
                  memory: 170Mi
                requests:
                  cpu: 100m
                  memory: 70Mi
              args: [ "-conf", "/etc/coredns/Corefile" ]
              volumeMounts:
              - name: config-volume
                mountPath: /etc/coredns
                readOnly: true
              ports:
              - containerPort: 53
                name: dns
                protocol: UDP
              - containerPort: 53
                name: dns-tcp
                protocol: TCP
              - containerPort: 9153
                name: metrics
                protocol: TCP
              livenessProbe:
                httpGet:
                  path: /health
                  port: 8080
                  scheme: HTTP
                initialDelaySeconds: 60
                timeoutSeconds: 5
                successThreshold: 1
                failureThreshold: 5
              readinessProbe:
                httpGet:
                  path: /ready
                  port: 8181
                  scheme: HTTP
              securityContext:
                allowPrivilegeEscalation: false
                capabilities:
                  add:
                  - NET_BIND_SERVICE
                  drop:
                  - all
                readOnlyRootFilesystem: true
            dnsPolicy: Default
            volumes:
            - name: config-volume
              configMap:
                name: coredns
                items:
                - key: Corefile
                  path: Corefile
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: kube-dns
        namespace: kube-system
        annotations:
          prometheus.io/port: "9153"
          prometheus.io/scrape: "true"
        labels:
          eks.amazonaws.com/component: coredns
          app.kubernetes.io/name: coredns
          k8s-app: kube-dns
          kubernetes.io/cluster-service: "true"
          kubernetes.io/name: "CoreDNS"
      spec:
        selector:
          eks.amazonaws.com/component: coredns
          app.kubernetes.io/name: coredns
          k8s-app: karpenter
        clusterIP: 10.100.0.10
        ports:
        - name: dns
          port: 53
          protocol: UDP
        - name: dns-tcp
          port: 53
          protocol: TCP
        - name: metrics
          port: 9153
          protocol: TCP
    EOT
  }

  depends_on = [module.eks, null_resource.install_karpenter]
}