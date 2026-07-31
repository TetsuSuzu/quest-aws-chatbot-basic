import json
import os

import boto3

bedrock_agent_runtime = boto3.client("bedrock-agent-runtime")

KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]
MODEL_ARN = os.environ["MODEL_ARN"]


def ask_knowledge_base(question: str) -> dict:
    response = bedrock_agent_runtime.retrieve_and_generate(
        input={"text": question},
        retrieveAndGenerateConfiguration={
            "type": "KNOWLEDGE_BASE",
            "knowledgeBaseConfiguration": {
                "knowledgeBaseId": KNOWLEDGE_BASE_ID,
                "modelArn": MODEL_ARN,
            },
        },
    )
    sources = sorted({
        ref["location"]["s3Location"]["uri"]
        for citation in response.get("citations", [])
        for ref in citation.get("retrievedReferences", [])
        if "s3Location" in ref.get("location", {})
    })
    return {"answer": response["output"]["text"], "sources": sources}


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

    result = ask_knowledge_base(question)
    return _response(200, result)
