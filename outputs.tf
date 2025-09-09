output "cluster_id" {
  value = module.eks.cluster_id
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "karpenter_iam_role_arn" {
  value = module.karpenter_irsa.iam_role_arn
}