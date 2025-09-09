output "cluster_id" {
  description = "EKS集群ID"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "EKS集群端点"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS集群名称"
  value       = module.eks.cluster_name
}

output "oidc_provider_arn" {
  description = "OIDC身份提供者ARN"
  value       = module.eks.oidc_provider_arn
}

output "kubectl_config" {
  description = "kubectl配置命令"
  value       = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region}"
}

output "karpenter_iam_role_arn" {
  description = "Karpenter IAM角色ARN"
  value       = module.karpenter_irsa.iam_role_arn
}

output "node_iam_role_arn" {
  description = "节点IAM角色ARN"
  value       = aws_iam_role.eks_node_role.arn
}