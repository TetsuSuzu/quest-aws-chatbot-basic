import json
import os

import boto3
from botocore.exceptions import ClientError

bedrock_agent_runtime = boto3.client("bedrock-agent-runtime")
s3 = boto3.client("s3")

KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]
MODEL_ARN = os.environ["MODEL_ARN"]
RERANK_MODEL_ARN = os.environ["RERANK_MODEL_ARN"]

# citationのretrievedReferences[].metadataに入っている、出典PDFのページ番号
PAGE_NUMBER_METADATA_KEY = "x-amz-bedrock-kb-document-page-number"
PREVIEW_URL_EXPIRES_IN = 3600

# $output_format_instructions$は出典(citations)を出力させるための必須プレースホルダー
PROMPT_TEMPLATE = """あなたはJTB情報管理ツールに関する社内ナレッジチャットボットです。以下の検索結果のみを根拠に、ユーザーの質問に日本語で回答してください。検索結果に答えがない場合は、その旨を伝えてください。

JTB情報管理ツールの手続き・申請フロー・プロセスに関する質問(例:「〜の申請手順は?」「〜の流れを教えて」)の場合は、回答の最後にMermaid記法のフローチャートを ```mermaid ``` のコードブロックで追加してください。単純な事実確認の質問には無理にフローチャートを付けないでください。

検索結果:
$search_results$

$output_format_instructions$"""


def _retrieve_and_generate(question: str, session_id: str | None):
    kwargs = {}
    if session_id:
        kwargs["sessionId"] = session_id

    return bedrock_agent_runtime.retrieve_and_generate(
        input={"text": question},
        retrieveAndGenerateConfiguration={
            "type": "KNOWLEDGE_BASE",
            "knowledgeBaseConfiguration": {
                "knowledgeBaseId": KNOWLEDGE_BASE_ID,
                "modelArn": MODEL_ARN,
                "generationConfiguration": {
                    "promptTemplate": {"textPromptTemplate": PROMPT_TEMPLATE},
                },
                # このKB(S3 Vectors、customer-managed型)ではvectorSearchConfigurationが正しい。
                # managedSearchConfigurationはAWSが検索設定を丸ごと管理する別タイプのKB専用で、
                # このKBに使うとValidationExceptionになる。
                #
                # 似た項目名を持つ複数の行・複数の資料が混在する表形式データでは、
                # ベクトル類似度だけの上位絞り込みだと本命のチャンクが漏れることがあるため、
                # 候補は広め(20件)に取ってからリランキングモデルで上位10件に絞り込む
                "retrievalConfiguration": {
                    "vectorSearchConfiguration": {
                        "numberOfResults": 20,
                        "rerankingConfiguration": {
                            "type": "BEDROCK_RERANKING_MODEL",
                            "bedrockRerankingConfiguration": {
                                "modelConfiguration": {"modelArn": RERANK_MODEL_ARN},
                                "numberOfRerankedResults": 10,
                            },
                        },
                    },
                },
            },
        },
        **kwargs,
    )


def _preview_url(uri: str, page_number: float) -> str | None:
    # uri: "s3://<bucket>/<key>" -> 事前生成したページ画像は "_page_previews/<key(拡張子抜き)>/page-<N>.png"。
    # x-amz-bedrock-kb-document-page-numberは0始まりのため+1して1始まりのファイル名に合わせる（実機で確認済み）
    bucket, _, key = uri.removeprefix("s3://").partition("/")
    stem = key.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    preview_key = f"_page_previews/{stem}/page-{int(page_number) + 1}.png"
    try:
        return s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": bucket, "Key": preview_key},
            ExpiresIn=PREVIEW_URL_EXPIRES_IN,
        )
    except ClientError:
        return None


def ask_knowledge_base(question: str, session_id: str | None) -> dict:
    try:
        response = _retrieve_and_generate(question, session_id)
    except ClientError as exc:
        # セッションが期限切れ・無効な場合は新規セッションとしてやり直す
        if session_id and "session" in str(exc).lower():
            response = _retrieve_and_generate(question, None)
        else:
            raise

    sources = {}
    for citation in response.get("citations", []):
        for ref in citation.get("retrievedReferences", []):
            location = ref.get("location", {})
            if "s3Location" not in location:
                continue
            uri = location["s3Location"]["uri"]
            page_number = ref.get("metadata", {}).get(PAGE_NUMBER_METADATA_KEY)
            entry = sources.setdefault(
                (uri, page_number),
                {"uri": uri, "page": None, "previewUrl": None},
            )
            if page_number is not None:
                entry["page"] = int(page_number) + 1
                entry["previewUrl"] = _preview_url(uri, page_number)

    return {
        "answer": response["output"]["text"],
        "sources": sorted(sources.values(), key=lambda s: (s["uri"], s["page"] or 0)),
        "sessionId": response["sessionId"],
    }


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json; charset=utf-8",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }


def lambda_handler(event, context):
    body = json.loads(event.get("body") or "{}")
    question = (body.get("question") or "").strip()
    if not question:
        return _response(400, {"error": "question is empty"})

    session_id = body.get("sessionId") or None
    result = ask_knowledge_base(question, session_id)
    return _response(200, result)
