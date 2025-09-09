provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "eks-karpenter"
      ManagedBy   = "terraform"
    }
  }
}

provider "random" {}