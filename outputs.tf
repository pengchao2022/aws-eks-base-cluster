output "cluster_id" {
  description = "EKS集群ID"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "EKS集群端点"
  value       = module.eks.cluster_endpoint
}

output "kubectl_config" {
  description = "kubectl配置命令"
  value       = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region}"
}