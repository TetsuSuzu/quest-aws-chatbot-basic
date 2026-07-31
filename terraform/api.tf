# オプション: コンソールのテストチャットだけでなく、簡易Webフロントからも
# 質問できるようにするための最小API（Lambda + API Gateway）。
# クエスト本体の必須要件ではないが、検証・デモ用に用意している。

data "archive_file" "base" {
  type        = "zip"
  source_file = "${path.module}/../lambda_function.py"
  output_path = "${path.module}/build/lambda_function.zip"
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "base_lambda" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "base_lambda_logs" {
  role       = aws_iam_role.base_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "base_lambda_permissions" {
  statement {
    sid       = "RetrieveAndGenerate"
    actions   = ["bedrock:RetrieveAndGenerate", "bedrock:Retrieve"]
    resources = [aws_bedrockagent_knowledge_base.main.arn]
  }

  statement {
    sid     = "InvokeGenerationModel"
    actions = ["bedrock:InvokeModel", "bedrock:GetInferenceProfile"]
    resources = [
      var.generation_model_arn,
      "arn:aws:bedrock:*::foundation-model/*",
    ]
  }
}

resource "aws_iam_role_policy" "base_lambda" {
  name   = "${var.project_name}-lambda-policy"
  role   = aws_iam_role.base_lambda.id
  policy = data.aws_iam_policy_document.base_lambda_permissions.json
}

resource "aws_lambda_function" "base" {
  function_name    = "${var.project_name}-ask"
  role             = aws_iam_role.base_lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.base.output_path
  source_code_hash = data.archive_file.base.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.main.id
      MODEL_ARN         = var.generation_model_arn
    }
  }
}

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "base" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.base.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "base" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /ask"
  target    = "integrations/${aws_apigatewayv2_integration.base.id}"
}

resource "aws_lambda_permission" "base_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.base.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
