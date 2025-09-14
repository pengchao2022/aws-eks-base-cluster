output "cluster_name" {
  description = "EKS cluster name"
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

output "karpenter_node_role_arn" {
  description = "Karpenter node IAM role ARN"
  value       = aws_iam_role.karpenter_node_role.arn
}

output "install_coredns_instructions" {
  description = "Instructions to install CoreDNS manually"
  value       = "After cluster is created, install CoreDNS using: aws eks create-addon --cluster-name ${module.eks.cluster_name} --addon-name coredns --region ${var.region}"
}