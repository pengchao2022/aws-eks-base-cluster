output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "node_groups" {
  description = "Map of node group details"
  value       = aws_eks_node_group.python_dev_nodes[*].node_group_name
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "vpc_id" {
  description = "VPC ID used by the cluster"
  value       = var.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs used by the cluster"
  value       = var.private_subnet_ids
}