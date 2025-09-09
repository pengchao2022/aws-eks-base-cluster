resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "https://charts.karpenter.sh"
  chart      = "karpenter"
  version    = var.karpenter_version
  namespace  = "karpenter"

  create_namespace = true

  values = [
    <<-YAML
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter_irsa.iam_role_arn}
    settings:
      clusterName: ${module.eks.cluster_id}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      aws:
        defaultInstanceProfile: ${aws_iam_instance_profile.karpenter.name}
    YAML
  ]

  depends_on = [
    module.eks,
    aws_eks_node_group.initial_nodes
  ]
}