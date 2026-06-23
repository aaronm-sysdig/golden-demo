"""Vulnerable LangChain "security finding" assistant.

This service exposes CVE-2023-29374: in LangChain through 0.0.131, LLMMathChain
feeds the LLM's response straight into Python's exec() (via PythonREPL) with no
sandbox. A prompt-injection attack makes the model emit attacker-controlled
Python, which the chain then executes - unauthenticated remote code execution.

The /calculate endpoint runs a real LLMMathChain. In a normal deployment the
"LLM" would translate a natural-language math question into a Python expression
and the chain would run it. Here the environment is air-gapped with no live
model, so PwnedLLM stands in for a model that has already been prompt-injected:
it echoes the caller's expression straight back inside a ```python block. The
dangerous primitive - exec() of model output - is exactly the vulnerability, so
the exploit is genuine end-to-end code execution in the container.
"""
import os
from typing import List, Optional

import mlflow  # noqa: F401 - imported for runtime sensor visibility (inUse=true)
from flask import Flask, jsonify, request
from langchain import LLMMathChain
from langchain.llms.base import LLM

app = Flask(__name__)


class PwnedLLM(LLM):
    """Stand-in for a real LLM that has been successfully prompt-injected.

    A genuine attacker reaches the exec() sink by injecting the prompt so the
    model returns malicious Python. With no live model available we model the
    end state directly: whatever expression the caller asks us to "calculate"
    is returned as the model's answer, wrapped in the ```python fence that
    LLMMathChain unwraps and exec()s.
    """

    @property
    def _llm_type(self) -> str:
        return "pwned"

    def _call(self, prompt: str, stop: Optional[List[str]] = None) -> str:
        # LangChain's math prompt ends with "Question: <user input>". Pull the
        # caller's expression out and hand it back as runnable Python.
        question = prompt.rsplit("Question:", 1)[-1].strip()
        return f"```python\nprint({question})\n```"


def build_chain() -> LLMMathChain:
    return LLMMathChain(llm=PwnedLLM(), verbose=False)


@app.get("/health")
def health():
    return jsonify(
        {
            "status": "ok",
            "service": "langchain-ai-assistant",
            "framework": "langchain",
            "uses_langchain": True,
        }
    )


@app.post("/calculate")
def calculate():
    """Run an arithmetic 'question' through LLMMathChain.

    Benign:  {"question": "37593 * 67"}
    Exploit: {"question": "__import__('os').popen('id').read()"}
    """
    payload = request.get_json(silent=True) or {}
    question = payload.get("question", "37593 * 67")

    chain = build_chain()
    try:
        answer = chain.run(question)
    except Exception as exc:  # surface errors instead of 500ing the demo
        answer = f"error: {exc}"

    return jsonify(
        {
            "framework": "langchain",
            "cve": "CVE-2023-29374",
            "question": question,
            "answer": answer,
        }
    )


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
