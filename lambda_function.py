import json
import os

import boto3
from botocore.exceptions import ClientError

bedrock_agent_runtime = boto3.client("bedrock-agent-runtime")

KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]
MODEL_ARN = os.environ["MODEL_ARN"]

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
            },
        },
        **kwargs,
    )


def ask_knowledge_base(question: str, session_id: str | None) -> dict:
    try:
        response = _retrieve_and_generate(question, session_id)
    except ClientError as exc:
        # セッションが期限切れ・無効な場合は新規セッションとしてやり直す
        if session_id and "session" in str(exc).lower():
            response = _retrieve_and_generate(question, None)
        else:
            raise

    sources = sorted({
        ref["location"]["s3Location"]["uri"]
        for citation in response.get("citations", [])
        for ref in citation.get("retrievedReferences", [])
        if "s3Location" in ref.get("location", {})
    })
    return {
        "answer": response["output"]["text"],
        "sources": sources,
        "sessionId": response["sessionId"],
    }


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
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
