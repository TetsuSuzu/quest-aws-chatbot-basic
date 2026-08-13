# 用語集: コード中の略語・命名慣習

`lambda_function.py`や`terraform/`を読んでいると、「知っていれば一瞬で分かるが、知らないと謎」な略語がよく出てくる。ここではハンズオン参加者向けに、このリポジトリの実コードに実際に出てくるものを中心にまとめる。

## 関数の引数・変数でよく使う略語

Pythonでは変数名の付け方に厳密なルールはないが、以下のような略語が広く慣習として定着している。

| 略語 | 元の単語 | 意味 |
|---|---|---|
| `args` | arguments | 位置引数（順番だけで渡す引数）をまとめたもの |
| `kwargs` | keyword arguments | キーワード引数をまとめたもの（下記「補足」参照） |
| `exc` / `err` | exception / error | 例外・エラーオブジェクト |
| `msg` | message | メッセージ文字列 |
| `res` / `resp` | response / result | レスポンス・結果 |
| `req` | request | リクエスト |
| `obj` | object | オブジェクト |
| `val` | value | 値 |
| `idx` | index | 添字・位置番号 |
| `num` | number | 数値 |
| `func` / `fn` | function | 関数 |
| `cls` | class | クラス自身を指す（`self`のクラスメソッド版） |
| `ctx` | context | 文脈・実行コンテキスト |
| `cfg` / `conf` | configuration | 設定 |
| `env` | environment | 環境（環境変数など） |
| `tmp` | temporary | 一時的な |
| `src` | source | 元・ソース |
| `dst` / `dest` | destination | 送り先 |

## Python本体・標準ライブラリの略語

| 略語 | 元の単語 |
|---|---|
| `os` | operating system |
| `sys` | system |
| `re` | regular expression（正規表現モジュール） |
| `repr`（`__repr__`） | representation（デバッグ用の文字列表現） |
| `iter`（`__iter__`） | iterate / iterator |
| `attr`（`getattr`/`setattr`） | attribute（属性） |
| `del`（予約語） | delete |
| `def`（予約語） | define |
| `elif`（予約語） | else if |
| `len()` | length |
| `id()` | identity |
| `str` | string |
| `dict` | dictionary |

## このリポジトリのコードに実際に出てくる略語

| 略語 | 元の単語 | 出てくる場所 |
|---|---|---|
| `kwargs` | keyword arguments | `lambda_function.py`の`_retrieve_and_generate` |
| `exc` | exception | `lambda_function.py`の`except ClientError as exc:` |
| `ARN` | Amazon Resource Name | `MODEL_ARN`・`RERANK_MODEL_ARN`（`lambda_function.py`）、`generation_model_arn`等（`terraform/variables.tf`） |
| `KB` | Knowledge Base | `KNOWLEDGE_BASE_ID`、コメント中で頻出 |
| `IAM` | Identity and Access Management | `aws_iam_role`（`terraform/bedrock_kb.tf`・`terraform/api.tf`） |
| `S3` | Simple Storage Service | バケット全般 |
| `JSON` | JavaScript Object Notation | `import json`（`lambda_function.py`） |
| `API` | Application Programming Interface | API Gateway、`bedrock-agent-runtime`等のAPIクライアント |
| `CORS` | Cross-Origin Resource Sharing | `cors_configuration`（`terraform/api.tf`） |
| `HCL` | HashiCorp Configuration Language | `terraform/`配下の`.tf`ファイルの記法名 |
| `OIDC` | OpenID Connect | GitHub ActionsのAWS認証方式（`.github/workflows/terraform-apply.yml`） |
| `SSE` | Server-Side Encryption | S3バケットの暗号化設定 |
| `VTL` | Velocity Template Language | REST API Gatewayのマッピングテンプレート記法（README.mdのHTTP API比較表参照） |

## 補足: `*args` / `**kwargs`の展開の仕組み

`kwargs`という名前自体はただの慣習（`options`等でも動作は同じ）。意味を持つのは`*`・`**`という記号の方。

```python
# 定義側: 任意個のキーワード引数を1つの辞書として受け取る
def greet(**kwargs):
    print(kwargs)

greet(name="太郎", age=30)
# → {'name': '太郎', 'age': 30}
```

```python
# 呼び出し側: 辞書の中身をキーワード引数として展開する
options = {"name": "太郎", "age": 30}
greet(**options)
# ↑ greet(name="太郎", age=30) と書いたのと全く同じ
```

`lambda_function.py`の`_retrieve_and_generate`では、この「呼び出し側」の使い方で`sessionId`を条件付きで渡している。

```python
kwargs = {}
if session_id:
    kwargs["sessionId"] = session_id
...
bedrock_agent_runtime.retrieve_and_generate(
    input={"text": question},
    **kwargs,  # session_idがあれば sessionId=... が展開され、なければ何も展開されない
)
```

`sessionId=None`と明示的に渡すのと、`sessionId`引数自体を渡さないのとでは意味が違う（Bedrock側は後者を「新規セッション」の合図として扱う）ため、このような条件付きの組み立てが必要になる。

## 関連コードへのGitHubリンク

上表「このリポジトリのコードに実際に出てくる略語」で挙げた各項目が、実際にどのファイル・どの行にあるかへのリンク。

| 略語 | GitHub上の該当箇所 |
|---|---|
| `kwargs` | [lambda_function.py#L24-L27](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/blob/main/lambda_function.py#L24-L27)（`_retrieve_and_generate`） |
| `exc` | [lambda_function.py#L67](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/blob/main/lambda_function.py#L67)（`except ClientError as exc:`） |
| `ARN` | [lambda_function.py#L9-L11](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/blob/main/lambda_function.py#L9-L11)、[terraform/variables.tf#L13-L29](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/blob/main/terraform/variables.tf#L13-L29) |
| `KB` | [lambda_function.py#L9](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/blob/main/lambda_function.py#L9)（`KNOWLEDGE_BASE_ID`） |
| `IAM` | [terraform/bedrock_kb.tf#L31](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/blob/main/terraform/bedrock_kb.tf#L31)、[terraform/api.tf#L41](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/blob/main/terraform/api.tf#L41) |
| `S3` | [terraform/s3.tf#L3](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/blob/main/terraform/s3.tf#L3)（`aws_s3_bucket`） |
| `JSON` | [lambda_function.py#L1](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/blob/main/lambda_function.py#L1)（`import json`） |
| `API` | [terraform/api.tf](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/blob/main/terraform/api.tf)（API Gateway全般） |
| `CORS` | [terraform/api.tf#L81](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/blob/main/terraform/api.tf#L81)（`cors_configuration`） |
| `HCL` | [terraform/](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/tree/main/terraform)（`.tf`ファイル全般） |
| `OIDC` | [.github/workflows/terraform-apply.yml#L12-L13,L36](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/blob/main/.github/workflows/terraform-apply.yml#L12-L36) |
| `SSE` | [terraform/s3.tf#L17](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/blob/main/terraform/s3.tf#L17)（`aws_s3_bucket_server_side_encryption_configuration`） |
| `VTL` | リポジトリ内に該当コードはなし。[README.md](https://github.com/TetsuSuzu/quest-aws-chatbot-basic/blob/main/README.md)の「HTTP API vs REST API」比較表を参照 |
