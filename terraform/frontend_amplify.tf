# フロントエンドはAWS Amplify Hostingで配信する。
# 参加者向け手順(docs/manual_console_setup.md)は
# 「index.htmlを編集してS3にアップロード → Amplifyの手動デプロイ(方式: Amazon S3)で
#  そのバケット/プレフィックスを指定してデプロイ」という運用のため、
# この検証用terraformも同じ流れをCLI(aws amplify start-deployment)で自動化して再現する。
#
# Amplifyコンソールのウィザードで「方式: Amazon S3」を選んだ場合、バケットポリシーは
# ウィザードが自動生成するが、CLI/SDK経由でstart-deploymentを直接呼ぶ場合は自動生成されない
# ため、下記のバケットポリシーを自前で用意する必要がある。
# 参照: https://docs.aws.amazon.com/amplify/latest/userguide/deploy-with-sdks.html

locals {
  frontend_deploy_prefix = "frontend"
}

resource "aws_s3_bucket" "frontend_deploy" {
  bucket = "${var.project_name}-frontend-deploy-${data.aws_caller_identity.current.account_id}"
}

# Amplifyがバケットポリシー経由でのみ読み取るため、バケット自体を公開する必要はない
# (S3静的website hostingと異なり、フロント用バケットも非公開のまま維持できる)
resource "aws_s3_bucket_public_access_block" "frontend_deploy" {
  bucket = aws_s3_bucket.frontend_deploy.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_amplify_app" "frontend" {
  name     = "${var.project_name}-frontend"
  platform = "WEB"
}

resource "aws_amplify_branch" "frontend" {
  app_id      = aws_amplify_app.frontend.id
  branch_name = "main"
}

resource "aws_s3_object" "frontend_index" {
  bucket       = aws_s3_bucket.frontend_deploy.id
  key          = "${local.frontend_deploy_prefix}/index.html"
  content      = replace(file("${path.module}/../frontend/index.html"), "__API_ENDPOINT__", aws_apigatewayv2_stage.main.invoke_url)
  content_type = "text/html; charset=utf-8"
  etag         = md5(replace(file("${path.module}/../frontend/index.html"), "__API_ENDPOINT__", aws_apigatewayv2_stage.main.invoke_url))
}

# 参照(deploy-with-sdks.md)のサンプルポリシーをベースにしている。
# ドキュメントはaws:SourceArnをURLエンコード(パーセントエンコード)した値で比較するよう記載しているが、
# 実機検証の結果それだとAmplify側の実際のリクエストコンテキスト(素のARN文字列)とマッチせず
# InvalidSourceBucketで失敗したため、エンコードせず素のARN文字列で比較する
data "aws_iam_policy_document" "frontend_deploy_amplify_access" {
  statement {
    sid       = "AllowAmplifyToListPrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.frontend_deploy.arn]

    principals {
      type        = "Service"
      identifiers = ["amplify.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_amplify_branch.frontend.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:prefix"
      values   = [""]
    }
  }

  statement {
    sid       = "AllowAmplifyToReadPrefix"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend_deploy.arn}/${local.frontend_deploy_prefix}/*"]

    principals {
      type        = "Service"
      identifiers = ["amplify.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_amplify_branch.frontend.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend_deploy" {
  bucket = aws_s3_bucket.frontend_deploy.id
  policy = data.aws_iam_policy_document.frontend_deploy_amplify_access.json
}

# Gitリポジトリと連携しない手動デプロイのため、S3への配置後にstart-deploymentを
# 明示的に呼び出さない限りAmplify側には反映されない
resource "null_resource" "frontend_deploy" {
  triggers = {
    index_etag  = aws_s3_object.frontend_index.etag
    policy_hash = sha256(data.aws_iam_policy_document.frontend_deploy_amplify_access.json)
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "aws amplify start-deployment --app-id ${aws_amplify_app.frontend.id} --branch-name ${aws_amplify_branch.frontend.branch_name} --source-url s3://${aws_s3_bucket.frontend_deploy.id}/${local.frontend_deploy_prefix}/ --source-url-type BUCKET_PREFIX --region ${var.aws_region}"
  }

  depends_on = [aws_s3_bucket_policy.frontend_deploy, aws_s3_object.frontend_index]
}
