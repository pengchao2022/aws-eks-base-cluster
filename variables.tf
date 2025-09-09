variable "environment" {
  description = "环境类型（development, staging, production）"
  type        = string
  default     = "development"
}

variable "aws_account_id" {
  description = "AWS账户ID"
  type        = string
}

variable "cluster_name" {
  description = "EKS集群名称"
  type        = string
  default     = "development-eks-cluster"
}

variable "cluster_version" {
  description = "Kubernetes版本"
  type        = string
  default     = "1.28"
}

variable "vpc_id" {
  description = "现有VPC的ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "私有子网ID列表"
  type        = list(string)
}

variable "node_instance_type" {
  description = "工作节点实例类型"
  type        = string
  default     = "t3.micro"
}

variable "desired_size" {
  description = "初始节点组期望的节点数量"
  type        = number
  default     = 4
}

variable "min_size" {
  description = "初始节点组最小节点数量"
  type        = number
  default     = 4
}

variable "max_size" {
  description = "初始节点组最大节点数量"
  type        = number
  default     = 6
}

variable "karpenter_version" {
  description = "Karpenter版本"
  type        = string
  default     = "v0.32.1"
}

variable "region" {
  description = "AWS区域"
  type        = string
  default     = "us-east-1"
}