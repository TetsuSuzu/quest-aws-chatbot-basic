# GitHub ActionsからOIDCでAWSに認証してmain/terraformを apply するための
# 前提リソース（tfstate用S3バケット + IAMロール）。ローカルで一度だけ apply する。
# ここで作ったバケット名・ロールARNは、GitHub Actionsワークフローと
# ../versions.tf の backend "s3" 設定に手で渡す。

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.24"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "project_name" {
  type    = string
  default = "quest-basic"
}

variable "github_repository" {
  description = "GitHub Actionsからの認証を許可するリポジトリ（<org-or-user>/<repo>）"
  type        = string
  default     = "TetsuSuzu/quest-aws-chatbot-basic"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# アカウントに既存のGitHub OIDCプロバイダーを再利用する（1アカウントにつき1個までのため新規作成しない）
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # このGitHubアカウントは過去のリネーム等の影響でsubクレームに
    # owner_id/repository_idが付与される形式になっているため、両方のパターンを許可する
    # （実際の値はCloudTrailのAssumeRoleWithWebIdentity失敗イベントで確認した）
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:*",
        "repo:TetsuSuzu@144105005/quest-aws-chatbot-basic@1318833778:*",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
}

# ハンズオン用サンドボックスアカウント想定の権限範囲。本番アカウントで使う場合は
# リソース名プレフィックスでの絞り込みをより厳密にすること
data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    sid = "TerraformState"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
  }

  statement {
    sid = "ManageAppResources"
    actions = [
      "s3:*",
      "s3vectors:*",
      "bedrock:*",
      "lambda:*",
      "apigateway:*",
      "amplify:*",
      "logs:*",
      "iam:GetRole", "iam:CreateRole", "iam:DeleteRole", "iam:TagRole",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies", "iam:PassRole",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${var.project_name}-github-actions-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}

output "tfstate_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
