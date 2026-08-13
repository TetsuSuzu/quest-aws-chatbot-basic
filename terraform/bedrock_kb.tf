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

  # 画面仕様書PDF(スクリーンショット画像で、テキストレイヤーを持たないPDF)を解析するための
  # マルチモーダルパースに使う。generation_model_arnはクロスリージョンinference profileの
  # ため、profile ARN自体とルーティング先のfoundation-model ARNの両方への権限が必要
  statement {
    sid     = "InvokeMultimodalParsingModel"
    actions = ["bedrock:InvokeModel", "bedrock:GetInferenceProfile"]
    resources = [
      var.generation_model_arn,
      "arn:aws:bedrock:*::foundation-model/*",
    ]
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

  # スキャン画像PDF(テキストレイヤーなし)も取り込めるよう、ビジョン対応モデルで
  # 画像内容をテキスト化してから埋め込む(標準のテキスト抽出だけでは
  # 「no text content found」として無視されてしまう)
  vector_ingestion_configuration {
    parsing_configuration {
      parsing_strategy = "BEDROCK_FOUNDATION_MODEL"

      bedrock_foundation_model_configuration {
        model_arn = var.generation_model_arn

        # 画面仕様書（Excelにスクリーンショットを貼り付けPDFエクスポートしたもの）という
        # 本リポジトリの実際のドキュメント特性に合わせた書き起こし指示。
        # 要約・翻訳をさせず原文どおり日本語で書き起こすことが、検索精度に直結するため重要
        parsing_prompt {
          parsing_prompt_string = "このページは画面仕様書のスクリーンショットを含む日本語の業務文書です。ページに写っているテキストを要約・翻訳・言い換えをせず、原文どおり日本語のまま全て書き起こしてください。画面名・入力項目のラベル・選択肢・ボタン名・注記など、画面上に表示されている文言を漏れなく書き起こしてください。表がある場合は行と列の対応関係が分かる形で書き起こしてください。画面ID(例: SCR-003)など識別子となる番号・記号は省略せず保持してください。"
        }
      }
    }
  }
}
