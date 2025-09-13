output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = var.cluster_name
}

output "karpenter_controller_role_arn" {
  description = "Karpenter controller IAM role ARN"
  value       = aws_iam_role.karpenter_controller.arn
}

output "karpenter_node_instance_profile" {
  description = "Karpenter node instance profile name"
  value       = aws_iam_instance_profile.karpenter_node.name
}

output "oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  value       = module.eks.oidc_provider_arn
}

output "node_group_status" {
  description = "Status of the EKS node group"
  value       = aws_eks_node_group.ubuntu_nodes.status
}

output "node_count" {
  description = "Number of worker nodes deployed"
  value       = var.node_count
}

output "ssm_access_info" {
  description = "Information about SSM access to nodes"
  value       = "Nodes can be accessed via AWS Systems Manager Session Manager without SSH keys"
}