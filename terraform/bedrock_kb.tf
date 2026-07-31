resource "aws_s3vectors_vector_bucket" "kb" {
  vector_bucket_name = "${var.project_name}-vectors"
}

resource "aws_s3vectors_index" "kb" {
  index_name         = "${var.project_name}-kb-index"
  vector_bucket_name = aws_s3vectors_vector_bucket.kb.vector_bucket_name

  data_type       = "float32"
  dimension       = 1024 # Titan Embed Text v2のデフォルト次元数（embedding_model_arnと一致させること）
  distance_metric = "cosine"

  metadata_configuration {
    # チャンク本文(AMAZON_BEDROCK_TEXT)とドキュメントメタデータ(AMAZON_BEDROCK_METADATA)は
    # フィルタ可能メタデータの上限(2048バイト/ベクトル)にすぐ達してしまうため、
    # 両方とも非フィルタ対象にする（除外しないとほぼ全チャンクが取り込み失敗する）
    non_filterable_metadata_keys = ["AMAZON_BEDROCK_TEXT", "AMAZON_BEDROCK_METADATA"]
  }
}

data "aws_iam_policy_document" "kb_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "kb" {
  name               = "${var.project_name}-kb-role"
  assume_role_policy = data.aws_iam_policy_document.kb_trust.json
}

data "aws_iam_policy_document" "kb_permissions" {
  statement {
    sid       = "InvokeEmbeddingModel"
    actions   = ["bedrock:InvokeModel"]
    resources = [var.embedding_model_arn]
  }

  statement {
    sid       = "S3VectorBucketReadAndWritePermission"
    actions   = ["s3vectors:PutVectors", "s3vectors:GetVectors", "s3vectors:DeleteVectors", "s3vectors:QueryVectors", "s3vectors:GetIndex"]
    resources = [aws_s3vectors_index.kb.index_arn]
  }

  statement {
    sid       = "ReadDocumentBucket"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.documents.arn}/*"]
  }

  statement {
    sid       = "ListDocumentBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.documents.arn]
  }
}

resource "aws_iam_role_policy" "kb" {
  name   = "${var.project_name}-kb-policy"
  role   = aws_iam_role.kb.id
  policy = data.aws_iam_policy_document.kb_permissions.json
}

resource "aws_bedrockagent_knowledge_base" "main" {
  name     = "${var.project_name}-kb"
  role_arn = aws_iam_role.kb.arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = var.embedding_model_arn
    }
  }

  storage_configuration {
    type = "S3_VECTORS"

    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.kb.index_arn
    }
  }
}

resource "aws_bedrockagent_data_source" "documents" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id
  name              = "${var.project_name}-documents"

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn = aws_s3_bucket.documents.arn
    }
  }
}
