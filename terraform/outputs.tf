output "documents_bucket" {
  value = aws_s3_bucket.documents.bucket
}

output "knowledge_base_id" {
  value = aws_bedrockagent_knowledge_base.main.id
}

output "data_source_id" {
  value = aws_bedrockagent_data_source.documents.data_source_id
}

output "api_endpoint" {
  value = aws_apigatewayv2_stage.main.invoke_url
}

output "frontend_url" {
  value = aws_s3_bucket_website_configuration.frontend.website_endpoint
}

output "next_steps" {
  value = <<-EOT
    1. データソースを同期する:
       aws bedrock-agent start-ingestion-job --knowledge-base-id ${aws_bedrockagent_knowledge_base.main.id} --data-source-id ${aws_bedrockagent_data_source.documents.data_source_id} --region ${var.aws_region}
    2. Bedrockコンソールの Knowledge Base > ${aws_bedrockagent_knowledge_base.main.id} > テスト画面で質問して動作確認する
    3. Webフロント(S3静的ホスティング)で確認する: http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}
  EOT
}
