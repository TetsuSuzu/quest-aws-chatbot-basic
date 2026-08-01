terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # S3 Vectors関連リソース(aws_s3vectors_*)はv6.24.0以降が必要
      version = "~> 6.24"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # tfstateはS3で管理する（bucket/regionはterraform initの-backend-configで渡す。
  # terraform/bootstrap/で作成したバケットを使う）
  backend "s3" {
    key          = "quest-aws-chatbot-basic/terraform.tfstate"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}
