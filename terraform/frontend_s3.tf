# フロントエンドはAmplifyではなくS3の静的website hostingで配信する
# （ビルドパイプラインを持たない分、Amplifyより単純・低コスト）。
# ドキュメント用バケット(aws_s3_bucket.documents)とは別バケットにし、
# 公開設定はこのフロント用バケットに限定する。

resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-frontend-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "frontend_public_read" {
  statement {
    sid       = "PublicReadGetObject"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_public_read.json

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

resource "aws_s3_object" "frontend_index" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  content      = replace(file("${path.module}/../frontend/index.html"), "__API_ENDPOINT__", aws_apigatewayv2_stage.main.invoke_url)
  content_type = "text/html; charset=utf-8"
  etag         = md5(replace(file("${path.module}/../frontend/index.html"), "__API_ENDPOINT__", aws_apigatewayv2_stage.main.invoke_url))
  # HTML1枚構成でデプロイのたびに内容が変わりうるため、ブラウザキャッシュによる
  # 「更新したのに古い画面が表示される」を防ぐ
  cache_control = "no-cache, must-revalidate"
}
