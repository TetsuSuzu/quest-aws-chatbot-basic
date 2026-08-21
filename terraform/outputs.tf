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
  value = "https://${aws_amplify_branch.frontend.branch_name}.${aws_amplify_app.frontend.default_domain}"
}

output "next_steps" {
  value = <<-EOT
    1. データソースを同期する:
       aws bedrock-agent start-ingestion-job --knowledge-base-id ${aws_bedrockagent_knowledge_base.main.id} --data-source-id ${aws_bedrockagent_data_source.documents.data_source_id} --region ${var.aws_region}
    2. Bedrockコンソールの Knowledge Base > ${aws_bedrockagent_knowledge_base.main.id} > テスト画面で質問して動作確認する
    3. Webフロント(Amplify Hosting)で確認する: https://${aws_amplify_branch.frontend.branch_name}.${aws_amplify_app.frontend.default_domain}
  EOT
}
