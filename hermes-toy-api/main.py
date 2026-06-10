"""
Hermes Toy API — FastAPI 服务

提供：
- POST /api/generate    — HTTP oneshot（用于快速测试）
- WS   /api/chat/ws     — WebSocket 多轮对话（正式使用）

启动：uvicorn main:app --host 0.0.0.0 --port 8765
"""
from __future__ import annotations

import json
import logging
import os
import uuid
from typing import Optional

import httpx
import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from models import (
    ChatMessage,
    GenerateRequest,
    GenerateResponse,
    WSClientMessage,
    WSServerMessage,
)
from generator import hermes_generate, logger as gen_logger

# ── 日志 ──
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s %(message)s",
)
logger = logging.getLogger("hermes-toy-api")

# ── App ──
app = FastAPI(title="Hermes Toy API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ══════════════════════════════════════════
# HTTP 端点 — 快速测试用
# ══════════════════════════════════════════

@app.post("/api/generate", response_model=GenerateResponse)
async def http_generate(req: GenerateRequest):
    """一次性生成玩法方案（仅用于测试，实际使用走 WebSocket）"""
    session_id = req.session_id or f"http_{uuid.uuid4().hex[:8]}"

    result = hermes_generate(
        user_message=req.user_message,
        history=req.history,
        connected_toys=req.connected_toys,
    )

    return GenerateResponse(
        success=result.get("success", False),
        session_id=session_id,
        lua_script=result.get("lua_script"),
        play_script=result.get("play_script"),
        explanation=result.get("explanation"),
        assistant_message=result.get("assistant_message"),
        error=result.get("error"),
    )


@app.get("/api/health")
async def health():
    return {"status": "ok"}


# ══════════════════════════════════════════
# Playbooks 管理端点
# ══════════════════════════════════════════

PLAYBOOKS_DIR = os.path.join(os.path.dirname(__file__), "playbooks")


def _load_playbook_registry() -> list[dict]:
    """读取 playbooks/registry.json"""
    registry_path = os.path.join(PLAYBOOKS_DIR, "registry.json")
    if not os.path.exists(registry_path):
        return []
    try:
        with open(registry_path, encoding="utf-8") as f:
            data = json.load(f)
        return data.get("playbooks", [])
    except Exception as e:
        logger.warning("Failed to load playbook registry: %s", e)
        return []


def _parse_playbook_duration(lua_text: str) -> str:
    """从 Lua 注释中提取时长"""
    import re
    m = re.search(r'总时长[：:]\s*(.+?)(?:\n|$)', lua_text)
    if m:
        return m.group(1).strip()
    return "未知"


def _extract_toys_from_lua(lua_text: str) -> list[str]:
    """从 Lua 脚本中提取用到的玩具 ID"""
    import re
    toys = set()
    for m in re.finditer(r'toy\.(\w+):', lua_text):
        toys.add(m.group(1))
    return sorted(toys)


@app.get("/api/playbooks", response_model=list[dict])
async def list_playbooks():
    """获取所有已注册玩法方案"""
    registry = _load_playbook_registry()
    results = []

    for entry in registry:
        lua_path = os.path.join(PLAYBOOKS_DIR, entry.get("lua_file", ""))
        md_path = os.path.join(PLAYBOOKS_DIR, entry.get("doc_file", ""))

        lua_content = ""
        md_content = ""
        if os.path.exists(lua_path):
            with open(lua_path, encoding="utf-8") as f:
                lua_content = f.read()
        if os.path.exists(md_path):
            with open(md_path, encoding="utf-8") as f:
                md_content = f.read()

        results.append({
            "id": entry["id"],
            "name": entry["name"],
            "description": entry.get("description", ""),
            "toys": _extract_toys_from_lua(lua_content),
            "toys_label": entry.get("toys", []),
            "duration": _parse_playbook_duration(lua_content),
            "lua_script": lua_content,
            "doc_markdown": md_content,
            "tags": entry.get("tags", []),
            "created": entry.get("created", ""),
        })

    return results


@app.get("/api/playbooks/{playbook_id}", response_model=dict)
async def get_playbook(playbook_id: str):
    """获取单个玩法方案详情"""
    playbooks = await list_playbooks()
    for pb in playbooks:
        if pb["id"] == playbook_id:
            return pb
    return {"error": "not found", "id": playbook_id}


def _load_deepseek_key() -> str:
    """从项目本地 .env 读取 DEEPSEEK_API_KEY，找不到再回退到全局 ~/.hermes/.env"""
    # 1. 项目本地 .env
    project_env = os.path.join(os.path.dirname(__file__), ".env")
    try:
        with open(project_env) as f:
            for line in f:
                line = line.strip()
                if line.startswith("DEEPSEEK_API_KEY="):
                    val = line.split("=", 1)[1].strip().strip('"').strip("'")
                    if val:
                        return val
    except Exception:
        pass

    # 2. 回退到全局 Hermes .env
    global_env = "/home/wisecoach/.hermes/.env"
    try:
        with open(global_env) as f:
            for line in f:
                line = line.strip()
                if line.startswith("DEEPSEEK_API_KEY="):
                    val = line.split("=", 1)[1].strip().strip('"').strip("'")
                    if val:
                        return val
    except Exception:
        pass
    return ""


@app.get("/api/config")
async def get_config():
    """返回 Hermes 配置（DeepSeek key、模型等）"""
    return {
        "deepseek_api_key": _load_deepseek_key(),
        "deepseek_model": "deepseek-v4-flash",
        "deepseek_base_url": "https://api.deepseek.com/v1",
        "hermes_host": "192.168.1.119",
        "hermes_port": 8765,
    }


@app.get("/api/debug/generate")
async def debug_generate():
    """调试：直接调用 generator 看结果"""
    from generator import hermes_generate
    result = hermes_generate(
        user_message="你好，请帮我设计一个玩法",
        history=[],
        connected_toys=[],
    )
    return result


# ══════════════════════════════════════════
# WebSocket 端点 — 多轮对话
# ══════════════════════════════════════════

class ChatSession:
    """单个 WebSocket 连接上的对话会话"""

    def __init__(self, ws_id: str):
        self.ws_id = ws_id
        self.history: list[ChatMessage] = []
        self.connected_toys: list = []
        self.playbook_generated = False


# 会话存储（简单内存，重启即丢）
_sessions: dict[str, ChatSession] = {}


@app.websocket("/api/chat/ws")
async def websocket_chat(websocket: WebSocket):
    await websocket.accept()
    ws_id = uuid.uuid4().hex[:12]
    session = ChatSession(ws_id)
    _sessions[ws_id] = session

    logger.info("WebSocket connected: %s", ws_id)

    try:
        while True:
            raw = await websocket.receive_text()
            data = json.loads(raw)
            client_msg = WSClientMessage(**data)

            if client_msg.action == "close":
                logger.info("Session %s: client closed", ws_id)
                break

            if client_msg.action == "start":
                # 初始化：设置已连接玩具，发送欢迎消息
                session.connected_toys = client_msg.connected_toys
                initial_prompt = "你好！请帮我设计一个情趣玩具玩法。"
                result = hermes_generate(
                    user_message=initial_prompt,
                    history=[],
                    connected_toys=session.connected_toys,
                )
                logger.info("Session %s: init result keys=%s", ws_id, list(result.keys()))

                if result.get("success"):
                    msg = result.get("assistant_message", "欢迎！请描述你想要的感觉？")
                    session.history.append(ChatMessage(role="assistant", content=msg))

                    # 发送欢迎消息
                    await websocket.send_json(
                        WSServerMessage(type="message", content=msg).model_dump()
                    )
                else:
                    await websocket.send_json(
                        WSServerMessage(
                            type="error",
                            content=result.get("error", "初始化失败"),
                        ).model_dump()
                    )
                continue

            if client_msg.action == "message":
                user_content = (client_msg.content or "").strip()
                if not user_content:
                    continue

                logger.info(
                    "Session %s: user_msg=%s... history=%d turns",
                    ws_id, user_content[:50], len(session.history),
                )

                # 保存用户消息
                session.history.append(ChatMessage(role="user", content=user_content))

                # 调 Hermes 生成回复
                result = hermes_generate(
                    user_message=user_content,
                    history=session.history[:-1],  # 不含当前用户消息
                    connected_toys=session.connected_toys,
                )

                if not result.get("success"):
                    await websocket.send_json(
                        WSServerMessage(
                            type="error",
                            content=result.get("error", "生成失败"),
                        ).model_dump()
                    )
                    continue

                # 判断是否生成了玩法方案
                if result.get("play_script") or result.get("lua_script"):
                    session.playbook_generated = True
                    await websocket.send_json(
                        WSServerMessage(
                            type="playbook",
                            lua_script=result.get("lua_script", ""),
                            play_script=result.get("play_script", ""),
                            explanation=result.get("explanation"),
                            playbook_name=result.get("playbook_name"),
                        ).model_dump()
                    )
                    logger.info("Session %s: playbook generated!", ws_id)
                else:
                    # 普通回复
                    msg = result.get("assistant_message", "")
                    session.history.append(ChatMessage(role="assistant", content=msg))
                    await websocket.send_json(
                        WSServerMessage(type="message", content=msg).model_dump()
                    )
                continue

    except WebSocketDisconnect:
        logger.info("WebSocket disconnected: %s", ws_id)
    except Exception as e:
        logger.exception("WebSocket error: %s", ws_id)
        try:
            await websocket.send_json(
                WSServerMessage(type="error", content=f"服务器错误: {e}").model_dump()
            )
        except Exception:
            pass
    finally:
        _sessions.pop(ws_id, None)
        logger.info("Session %s cleaned up", ws_id)


# ══════════════════════════════════════════
# DeepSeek API 代理（绕过手机 DNS 限制）
# ══════════════════════════════════════════

class DeepseekProxyRequest(BaseModel):
    """代理转发到 DeepSeek API 的请求"""
    api_key: str
    base_url: str = "https://api.deepseek.com/v1"
    model: str = "deepseek-v4-flash"
    messages: list[dict] = []
    max_tokens: int = 8192
    temperature: float = 0.7


@app.post("/api/deepseek/proxy")
async def deepseek_proxy(req: DeepseekProxyRequest):
    """手机→本地服务→DeepSeek，绕过手机 DNS"""
    url = f"{req.base_url.rstrip('/')}/chat/completions"
    headers = {
        "Authorization": f"Bearer {req.api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": req.model,
        "messages": req.messages,
        "max_tokens": req.max_tokens,
        "temperature": req.temperature,
    }

    logger.info("DeepSeek proxy: model=%s, messages=%d", req.model, len(req.messages))

    try:
        async with httpx.AsyncClient(timeout=600.0) as client:
            resp = await client.post(url, headers=headers, json=payload)
            data = resp.json()
            logger.info("DeepSeek proxy response: status=%d", resp.status_code)
            return data
    except httpx.TimeoutException:
        logger.error("DeepSeek proxy timed out")
        return {"error": "proxy_timeout", "message": "DeepSeek API 超时"}
    except Exception as e:
        logger.exception("DeepSeek proxy failed")
        return {"error": "proxy_error", "message": str(e)}


# ══════════════════════════════════════════
# 启动入口
# ══════════════════════════════════════════

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8765,
        reload=True,
        log_level="info",
    )
