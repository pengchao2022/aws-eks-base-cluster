terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95.0, < 6.0.0" # 满足 EKS 20.0 的要求
    }
  }
}

provider "aws" {
  region = "us-east-1" # 根据你的需求修改区域
}
