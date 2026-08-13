variable "aws_region" {
  description = "デプロイ先リージョン（Bedrock KB・S3 Vectors・使用モデルが利用可能なリージョンを指定）"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "リソース名のプレフィックス"
  type        = string
  default     = "quest-basic"
}

variable "embedding_model_arn" {
  description = "Knowledge Baseの埋め込みに使うモデルARN。次元数(dimension)はs3vectors_kb.tfのaws_s3vectors_indexと一致させること"
  type        = string
  default     = "arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.titan-embed-text-v2:0"
}

variable "generation_model_arn" {
  description = "回答生成に使うモデルARN（Knowledge Baseのテスト画面用）。アカウント・リージョン固有のinference profile ARNのため、他アカウントで使う場合は `aws bedrock list-inference-profiles` で確認して差し替えること"
  type        = string
  default     = "arn:aws:bedrock:ap-northeast-1:691665347318:inference-profile/jp.anthropic.claude-sonnet-4-5-20250929-v1:0"
}

variable "rerank_model_arn" {
  description = "検索結果の並べ替え（reranking）に使うモデルARN。foundation-model ARNのためアカウント非依存（`aws bedrock list-foundation-models --query \"modelSummaries[?contains(modelId,'rerank')]\"`で確認可能）"
  type        = string
  default     = "arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.rerank-v1:0"
}
