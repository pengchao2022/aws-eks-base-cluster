output "cluster_id" {
  description = "EKS集群ID"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "EKS集群端点"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "集群CA证书数据"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_name" {
  description = "EKS集群名称"
  value       = module.eks.cluster_name
}

output "oidc_provider_arn" {
  description = "OIDC身份提供者ARN"
  value       = module.eks.oidc_provider_arn
}

output "node_security_group_id" {
  description = "节点安全组ID"
  value       = module.eks.node_security_group_id
}

output "kubectl_config" {
  description = "kubectl配置命令"
  value       = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region}"
}