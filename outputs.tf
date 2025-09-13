output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.this.id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_status" {
  description = "EKS cluster status"
  value       = aws_eks_cluster.this.status
}

output "node_group_status" {
  description = "Node group status"
  value       = aws_eks_node_group.nodes.status
}

output "node_security_group_id" {
  description = "Node security group ID"
  value       = aws_security_group.eks_nodes.id
}

output "config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region}"
}