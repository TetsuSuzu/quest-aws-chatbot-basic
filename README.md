# ① 社内ナレッジAIチャットボット（対応: Aチーム）

社内資料をS3に集約し、低コストなAmazon S3 Vectorsをベクトルストアに用いたAmazon Bedrock Knowledge Basesでベクトル検索可能なAIチャットボットを構築する。Aチームのシステム化案「AIに資料を食わせて、チャットで回答をもらう」をそのまま実現する。**45〜60分**で構築できる最小構成を想定している。

旅行予約・保険といった特定業務ではなく、**社内業務処理（経費精算・在宅勤務規定など）に関する問い合わせに答える汎用の社内ナレッジチャットボット**が題材（`sample-docs/`参照）。

この構成は[quest-aws-chatbot](../quest-aws-chatbot)（Aurora・複数パターン・Amplifyフロントエンドまで作り込んだ発展版）の**Basic共通版**にあたる。まずはこちらで最小構成を体験し、時間が余ったチームは発展版の追加ワーク（パターン①②）に進む想定。

**使用サービス**: Amazon S3 / Amazon S3 Vectors / Amazon Bedrock Knowledge Bases / Titan Embeddings / Claude（Bedrock）/ IAM

**主要手順（概要）**
1. S3バケットを作成し、社内資料（PDF・Word・テキスト）をアップロードする
2. Bedrockコンソールで「ナレッジベース」を新規作成し、データソースにS3バケットを指定する
3. 埋め込みモデル（Titan Embeddings）とベクトルストア（Amazon S3 Vectors）を選択し、同期を実行する
4. Bedrockの「テストチャット」画面でナレッジベースを選び、資料に関する質問を入力して回答を確認する

画面遷移レベルの詳細手順は下記「手順（コンソール操作）」を参照。

### 推奨アーキテクチャ（S3 Vectors版）

```mermaid
flowchart LR
    User["利用者（参加者）"] --> Console["Bedrockコンソール\nKnowledge Base テスト画面"]
    Console --> KB["Amazon Bedrock\nKnowledge Base"]
    KB --> S3V[("S3 Vectors\nベクトルバケット")]
    KB --> Model["基盤モデル\n(Claude等)"]
    S3["Amazon S3\n(ドキュメント格納)"] -- "同期(Sync)" --> KB
```

### 使用するAWSサービス／リソース一覧

| サービス | 役割 | 備考 |
|---|---|---|
| Amazon S3 | 元データ（ドキュメント）の格納 | 公開設定禁止 |
| Amazon S3 Vectors | ベクトルストア（埋め込みベクトルの保存先） | 保存量・クエリ課金で低コスト。OpenSearch Serverlessのような常時起動コストが発生しない |
| Amazon Bedrock Knowledge Base | RAGの中核。Embedding・検索・回答生成を統合 | 最小工数で構築可 |
| 基盤モデル（Claude等） | 回答生成・埋め込み生成 | 事前にモデルアクセスの有効化が必要 |
| IAM ロール | Knowledge BaseがS3・S3 Vectors・基盤モデルを操作するための権限 | 最小権限で付与 |

## 禁止事項（社内ルール／セキュリティ観点）

- ❌ S3バケット・S3 Vectorsバケットの公開設定（パブリックアクセス）
- ❌ 機密度の高い実データ・個人情報のアップロード（デモ用データのみ使用）
- ❌ IAMの過剰権限（`AdministratorAccess`等）の安易な付与
- ❌ サンドボックス環境外のリソースへのアクセス
- ❌ APIキー・認証情報のハードコーディング／外部共有
- ❌ ドキュメント用バケットとベクトルバケットの取り違え（役割を明確に分ける）

## 手順（コンソール操作）

### 1. S3バケットを作成し、ドキュメントをアップロードする

1. S3コンソールでバケットを新規作成する（例: `<チーム名>-documents`）。パブリックアクセスはブロックしたままにする
2. 検索させたい社内ドキュメント（Markdown/PDF/Word等）をアップロードする。サンプルとして本リポジトリの`sample-docs/`を使ってもよい

### 2. S3 Vectorsのベクトルバケット・インデックスを作成する

1. S3コンソールの「Vector buckets」からベクトルバケットを新規作成する
2. 作成したベクトルバケット内に「ベクトルインデックス」を作成する
   - **次元数（dimension）**: 使用する埋め込みモデルに合わせる（下記「補足」参照）
   - **距離指標**: コサイン類似度（cosine）でよい
   - **メタデータ設定**: `non-filterable metadata keys` に `AMAZON_BEDROCK_TEXT` と `AMAZON_BEDROCK_METADATA` の2つを追加する（★詳細は下記トラブルシュート参照。ここを省略すると同期がほぼ全件失敗する）

### 3. Bedrockのモデルアクセスを有効化する

Bedrockコンソール「モデルアクセス」から、埋め込みモデル（Titan Embed Text V2等）と回答生成モデル（Claude等）の両方を有効化する。

### 4. Bedrock Knowledge Baseを作成する

1. Bedrockコンソール「Knowledge Bases」から新規作成
2. データソースに手順1で作成したS3バケットを指定
3. 埋め込みモデルを選択（手順2のベクトルインデックスと同じ次元数のもの）
4. ベクトルストアに「S3 Vectors」を選択し、手順2で作成したベクトルインデックスを指定
5. IAMロールは新規作成（自動的に必要な権限が付与される）を選ぶか、最小権限のロールを手動で用意する

### 5. データソースを同期（Sync）する

Knowledge Base作成後、データソースの詳細画面から「同期」を実行する。ステータスが「完了」になるまで待つ（ドキュメント数が少なければ数十秒程度）。

### 6. テスト画面で動作確認する

Knowledge Baseの「テスト」画面でチャット形式の質問を入力し、アップロードしたドキュメントの内容に基づいて回答が返ることを確認する。回答と一緒に出典（ソースドキュメント）も表示されることを確認する。

## つまづきポイントとヒント

| つまづきポイント | ヒント |
|---|---|
| データをどこに置く？ | まずS3バケットを作成しドキュメントをアップロードする |
| ベクトルの保存先は？ | S3ベクトルバケット（Vector bucket）を作成する |
| ベクトルインデックスは？ | ベクトルバケット内にベクトルインデックスを作成する（次元数は選択する埋め込みモデルに合わせる） |
| 検索させたい | Bedrock Knowledge Baseを作成し、データソースにS3を指定する |
| データソース設定 | データソースにドキュメント用S3バケットを指定する |
| データを反映したい | 作成後「同期（Sync）」を実行してベクトル化・格納する |
| モデルが使えない | 事前にBedrockのモデルアクセス（埋め込み／生成モデル）を有効化する |
| 動作確認したい | Knowledge Baseの「テスト」画面でチャット確認する |
| 権限エラーが出る | IAMロールにS3読み取り＋S3 Vectors操作＋Bedrock実行権限を付与する |
| **同期がほぼ全件失敗する（★重要）** | ベクトルインデックスの`non-filterable metadata keys`に`AMAZON_BEDROCK_TEXT`と`AMAZON_BEDROCK_METADATA`の両方を含めているか確認する。片方だけだと「フィルタ可能メタデータは1ベクトルあたり2048バイトまで」という制限にすぐ達し、ほとんどのチャンクが取り込み失敗する（実機検証で確認済みの実例） |

### 補足: 埋め込みモデルと次元数の対応

ベクトルインデックス作成時に**次元数（dimension）**の指定が必要。ここがKnowledge Base側で選んだ埋め込みモデルの次元数と不一致だと同期に失敗するため、重点的に確認すること。

| 埋め込みモデル例 | 次元数 |
|---|---|
| Amazon Titan Text Embeddings V2 | 1024 / 512 / 256（選択可） |
| Cohere Embed | 1024 |

## 追加ワークの技術補足（時間が余ったチーム向け）

- **パターン①: ナレッジベースの分岐** — Bedrockで複数のKnowledge Baseを用途別（仕様書系／チケット系等）に作成するか、1つのKB内でメタデータフィルタリングにより分岐させる
- **パターン②: データ種別で処理を分岐** — Excel等の構造化データはAmazon Athena／RDS等でSQLクエリ、パワポ・画像等の非構造化データはKnowledge Base（RAG）で検索する。ルーティング判定にはLambdaまたはBedrock Agentを利用する

より作り込んだ実装例（Terraformでの完全自動化・Aurora+Bedrock Agentによる自律ルーティング等）は[quest-aws-chatbot](../quest-aws-chatbot)を参照。

## ディスカッション想定キーワード（運営向け）

「なぜこのままでは本番運用に乗せられないか」を議論する際の想定キーワード。

| 論点 | 想定キーワード |
|---|---|
| データ更新の問題 | 実データはBox等の社内システムに格納されており、手動アップロードが必要 |
| 鮮度の問題 | 新情報の自動連携ができていない |
| コスト | 本構成はS3 Vectorsのため低コストだが、OpenSearch Serverless等を選ぶ場合は常時稼働コストが論点になる |
| セキュリティ／権限 | 誰がアクセスできるかの制御 |
| 解決の方向性 | 自動連携（Box→S3等）の実現には、Box管理者との連携調整が別途発生する |

## オプション: S3でシンプルなWebフロントを追加する

Bedrockコンソールのテストチャットだけでなく、ブラウザからも質問できるようにしたい場合は、**Amplifyではなく、S3の静的website hosting**で配信する軽量なフロントを追加できる（`terraform/`に検証済みで含まれている）。ビルドパイプラインを持たないHTML1枚構成のため、Amplifyより単純・低コスト。

```mermaid
flowchart LR
    User["利用者"] --> S3Front["S3静的website hosting\n(frontend/index.html)"]
    S3Front --> APIGW["API Gateway (HTTP API)"]
    APIGW --> Lambda["Lambda: ask"]
    Lambda --> KB["Bedrock Knowledge Base"]
```

- `frontend/index.html` — プレーンHTML+JS（ビルド不要）のチャット画面
- `lambda_function.py` + API Gateway（`POST /ask`）— Knowledge BaseにRetrieveAndGenerateするだけの薄いLambda
- フロント用S3バケットのみ公開設定（ドキュメント用バケットは非公開のまま）

```bash
curl -X POST https://<api_endpoint>/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "在宅勤務は週に何日まで使えますか？"}'
```

`terraform apply`後の`frontend_url`出力（`http://`を付けてブラウザで開く）から動作確認できる。

## この検証用Terraformについて

`terraform/`には、上記手順（Webフロント含む）が実際に機能することを**運営側が事前検証する**ための構成一式（S3バケット・S3 Vectors・Knowledge Base・IAMロール・Lambda・API Gateway・S3静的website hosting）を用意している。**参加者向けではなく、運営が事前にハンズオンの通り実施可能か確認する用途**。詳細は[terraform/README.md](terraform/README.md)を参照。
