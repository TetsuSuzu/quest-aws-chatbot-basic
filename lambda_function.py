import json
import os
import uuid

import boto3

bedrock_agent_runtime = boto3.client("bedrock-agent-runtime")
bedrock_runtime = boto3.client("bedrock-runtime")

KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]
MODEL_ARN = os.environ["MODEL_ARN"]

SYSTEM_PROMPT = """あなたはJTB情報管理ツールに関する社内ナレッジチャットボットです。以下の検索結果のみを根拠に、ユーザーの質問に日本語で回答してください。検索結果に答えがない場合は、その旨を伝えてください。

JTB情報管理ツールの手続き・申請フロー・プロセスに関する質問(例:「〜の申請手順は?」「〜の流れを教えて」)の場合は、回答の最後にMermaid記法のフローチャートを ```mermaid ``` のコードブロックで追加してください。単純な事実確認の質問には無理にフローチャートを付けないでください。"""


def _retrieve(question: str) -> list[dict]:
    response = bedrock_agent_runtime.retrieve(
        knowledgeBaseId=KNOWLEDGE_BASE_ID,
        retrievalQuery={"text": question},
        retrievalConfiguration={
            "managedSearchConfiguration": {"numberOfResults": 6},
        },
    )
    return response.get("retrievalResults", [])


def _build_search_results_text(results: list[dict]) -> str:
    blocks = []
    for i, r in enumerate(results, start=1):
        text = r.get("content", {}).get("text", "")
        uri = r.get("location", {}).get("s3Location", {}).get("uri", "")
        blocks.append(f"[検索結果{i}] (出典: {uri})\n{text}")
    return "\n\n".join(blocks) if blocks else "(該当する検索結果はありませんでした)"


def _generate_answer(question: str, search_results_text: str) -> str:
    user_message = f"検索結果:\n{search_results_text}\n\n質問:\n{question}"
    response = bedrock_runtime.converse(
        modelId=MODEL_ARN,
        system=[{"text": SYSTEM_PROMPT}],
        messages=[{"role": "user", "content": [{"text": user_message}]}],
    )
    return response["output"]["message"]["content"][0]["text"]


def ask_knowledge_base(question: str, session_id: str | None) -> dict:
    results = _retrieve(question)
    search_results_text = _build_search_results_text(results)
    answer = _generate_answer(question, search_results_text)

    sources = sorted({
        r["location"]["s3Location"]["uri"]
        for r in results
        if "s3Location" in r.get("location", {})
    })
    return {
        "answer": answer,
        "sources": sources,
        "sessionId": session_id or str(uuid.uuid4()),
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
