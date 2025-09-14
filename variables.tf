variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "eks-karpenter-cluster"
}

variable "cluster_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.28"
}

variable "vpc_id" {
  description = "VPC ID where EKS will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "instance_types" {
  description = "Instance types for Karpenter nodes"
  type        = list(string)
  default     = ["t3.micro"]
}

variable "desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 4
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}