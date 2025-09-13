resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "https://charts.karpenter.sh"
  chart      = "karpenter"
  version    = "v0.32.1"

  values = [
    <<-EOT
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${aws_iam_role.karpenter_controller.arn}
    clusterName: ${module.eks.cluster_name}
    clusterEndpoint: ${module.eks.cluster_endpoint}
    aws:
      defaultInstanceProfile: ${aws_iam_instance_profile.karpenter_node.name}
    EOT
  ]

  depends_on = [
    module.eks,
    aws_eks_node_group.ubuntu_nodes,
    aws_iam_role.karpenter_controller
  ]
}

# Karpenter Provisioner
resource "kubectl_manifest" "karpenter_provisioner" {
  yaml_body = <<YAML
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  requirements:
    - key: kubernetes.io/arch
      operator: In
      values: ["amd64"]
    - key: kubernetes.io/os
      operator: In
      values: ["linux"]
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["on-demand"]
    - key: node.kubernetes.io/instance-type
      operator: In
      values: ["t3.medium", "t3.large", "m5.large", "m5.xlarge"]
  providerRef:
    name: default
  ttlSecondsAfterEmpty: 30
  ttlSecondsUntilExpired: 604800
YAML

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "karpenter_aws_node_template" {
  yaml_body = <<YAML
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
  name: default
spec:
  subnetSelector:
    karpenter.sh/discovery: ${var.cluster_name}
  securityGroupSelector:
    karpenter.sh/discovery: ${var.cluster_name}
  amiFamily: Ubuntu
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 20Gi
        volumeType: gp3
        deleteOnTermination: true
        encrypted: true
YAML

  depends_on = [
    helm_release.karpenter
  ]
}