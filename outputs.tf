output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = var.cluster_name
}

output "node_count" {
  description = "Number of worker nodes"
  value       = var.node_count
}

output "config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region}"
}