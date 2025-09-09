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

output "node_group_name" {
  description = "Node group name"
  value       = aws_eks_node_group.python_dev_nodes.node_group_name
}

output "node_count" {
  description = "Number of nodes in the node group"
  value       = var.node_count
}

output "instance_names" {
  description = "Expected EC2 instance names"
  value       = [for i in range(1, var.node_count + 1) : "${var.cluster_name}-${i}"]
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}