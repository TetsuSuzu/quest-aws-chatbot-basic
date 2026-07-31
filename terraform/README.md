# 検証用Terraform

参加者向け手順書（[../README.md](../README.md)）の内容が実際に機能するかを、運営側が事前に確認するための構成。参加者に配布するものではない。

Knowledge Base本体（S3・S3 Vectors・IAM）に加え、Webフロント（S3静的website hosting）から動作確認できるようLambda・API Gatewayも含めている。

tfstateはローカル管理（S3バックエンド等は使わない）。1人が手元で検証する用途を想定している。

## 使い方

```bash
terraform init
terraform apply
```

適用後、出力される`next_steps`の案内に従ってデータソースを同期する。

```bash
aws bedrock-agent start-ingestion-job --knowledge-base-id <knowledge_base_id> --data-source-id <data_source_id> --region ap-northeast-1
```

同期完了後、Bedrockコンソールの Knowledge Base > テスト画面、または以下のようなスクリプトで動作確認する。

```python
import boto3

client = boto3.client("bedrock-agent-runtime", region_name="ap-northeast-1")
resp = client.retrieve_and_generate(
    input={"text": "在宅勤務は週に何日まで使えますか？"},
    retrieveAndGenerateConfiguration={
        "type": "KNOWLEDGE_BASE",
        "knowledgeBaseConfiguration": {
            "knowledgeBaseId": "<knowledge_base_id>",
            "modelArn": "<region>のinference profile ARN（例: jp.anthropic.claude-sonnet-4-5-...）",
        },
    },
)
print(resp["output"]["text"])
```

## 後片付け

検証が終わったら削除する（サンドボックスアカウントの費用を積み上げないため）。

```bash
terraform destroy
```

## 前提条件

- AWSプロバイダ `~> 6.24` 以降（S3 Vectors関連リソースを使うため）
- `var.embedding_model_arn`と`aws_s3vectors_index.kb`の`dimension`は必ず一致させること（不一致だと同期が失敗する）
- `var.generation_model_arn`はアカウント・リージョン固有のinference profile ARN。他アカウント/リージョンで検証する場合は`aws bedrock list-inference-profiles`で確認してから差し替えること
