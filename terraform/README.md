# 検証用Terraform

参加者向け手順書（[../README.md](../README.md)）の内容が実際に機能するかを、運営側が事前に確認するための構成。参加者に配布するものではない。

Knowledge Base本体（S3・S3 Vectors・IAM）に加え、Webフロント（S3静的website hosting）から動作確認できるようLambda・API Gatewayも含めている。

## CI/CD

`main`へのpush（`terraform/**` / `lambda_function*.py` / `frontend/**`変更時）でGitHub Actionsが自動的に`terraform apply`する（`.github/workflows/terraform-apply.yml`）。PRでは`terraform plan`が自動実行される。認証はGitHub OIDCで、長期のAWSアクセスキーは使わない。

tfstateはS3で管理する（`terraform/bootstrap/`で作成した`quest-basic-tfstate-<account_id>`バケット）。

**セットアップ済みのGitHub repo variables**: `AWS_ROLE_ARN` / `AWS_REGION` / `TFSTATE_BUCKET`（`terraform/bootstrap/`のoutputsから設定済み）。

### bootstrap（初回のみ、ローカルで実行）

```bash
cd bootstrap
terraform init
terraform apply
```

作成される`tfstate_bucket`・`github_actions_role_arn`をGitHub repo variablesに設定する（既に設定済み）。bootstrap自体のtfstateはローカル管理でよい（CI/CDの対象外）。

## ローカルでの動作確認

```bash
terraform init \
  -backend-config="bucket=quest-basic-tfstate-691665347318" \
  -backend-config="region=ap-northeast-1"
terraform apply
```

適用後、出力される`next_steps`の案内に従ってデータソースを同期する。

```bash
aws bedrock-agent start-ingestion-job --knowledge-base-id <knowledge_base_id> --data-source-id <data_source_id> --region ap-northeast-1
```

同期完了後、Bedrockコンソールの Knowledge Base > テスト画面、`next_steps`出力の`frontend_url`（Webフロント）、または以下のようなスクリプトで動作確認する。

```python
import boto3

agent_runtime = boto3.client("bedrock-agent-runtime", region_name="ap-northeast-1")

# 本リポジトリのKnowledge Baseはcustomer-managed型（S3 Vectors）のため、
# retrieve_and_generate で検索・生成を1回の呼び出しにまとめられる。
resp = agent_runtime.retrieve_and_generate(
    input={"text": "同行者の氏名はどの画面で入力しますか？"},
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

CI/CD化以降、`main`にコードがある限りリソースは維持される（pushのたびに再applyされる）。完全に削除するには、ワークフローを無効化した上でローカルから`terraform destroy`するか、GitHub Actionsに削除用のworkflow_dispatchジョブを追加する必要がある。サンドボックスアカウントの費用を積み上げないよう、検証が終わったチームのリソースは忘れずに削除すること。

```bash
terraform destroy \
  -backend-config="bucket=quest-basic-tfstate-691665347318" \
  -backend-config="region=ap-northeast-1"
```

## 前提条件

- AWSプロバイダ `~> 6.24` 以降（S3 Vectors関連リソースを使うため）
- `var.embedding_model_arn`と`aws_s3vectors_index.kb`の`dimension`は必ず一致させること（不一致だと同期が失敗する）
- `var.generation_model_arn`はアカウント・リージョン固有のinference profile ARN。他アカウント/リージョンで検証する場合は`aws bedrock list-inference-profiles`で確認してから差し替えること
