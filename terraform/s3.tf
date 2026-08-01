data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "documents" {
  bucket = "${var.project_name}-documents-${data.aws_caller_identity.current.account_id}"
}

# 禁止事項: S3バケットの公開設定は行わない
resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

locals {
  # sample-docs配下を再帰的に取り込む（gov/配下の観光庁PDFも含む）。
  # README.md（出典管理用のメタ文書）はRAGデータではないため除外する
  sample_doc_files = setsubtract(
    setunion(
      fileset("${path.module}/../sample-docs", "**/*.md"),
      fileset("${path.module}/../sample-docs", "**/*.pdf"),
    ),
    fileset("${path.module}/../sample-docs", "**/README.md")
  )
}

resource "aws_s3_object" "sample_docs" {
  for_each = local.sample_doc_files

  bucket       = aws_s3_bucket.documents.id
  key          = each.value
  source       = "${path.module}/../sample-docs/${each.value}"
  etag         = filemd5("${path.module}/../sample-docs/${each.value}")
  content_type = endswith(each.value, ".pdf") ? "application/pdf" : "text/markdown"
}
