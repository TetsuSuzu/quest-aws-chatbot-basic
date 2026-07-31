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

  # 検証用ミニ構成のため、tfstateはローカル管理でよい
  # (本番運用するならquest-aws-chatbot本体と同様にS3バックエンド化すること)
}

provider "aws" {
  region = var.aws_region
}
