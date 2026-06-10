"""
Pydantic 模型 — Hermes Toy API 的数据类型
"""
from __future__ import annotations
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


# ── 玩具信息 ──

class ToyApi(BaseModel):
    """玩具的能力函数描述"""
    id: str
    type: str
    name: str
    api: dict[str, str]  # {"函数名(args)": "描述"}


# ── HTTP 请求/响应 ──

class GenerateRequest(BaseModel):
    """POST /api/generate"""
    user_message: str
    connected_toys: list[ToyApi] = []
    session_id: Optional[str] = None
    history: list[ChatMessage] = []


class ChatMessage(BaseModel):
    role: str  # "user" | "assistant"
    content: str


class ExplanationStep(BaseModel):
    time: str
    action: str


class Explanation(BaseModel):
    duration_seconds: int
    steps: list[ExplanationStep] = []
    name: Optional[str] = None


class GenerateResponse(BaseModel):
    success: bool
    session_id: Optional[str] = None
    lua_script: Optional[str] = None
    play_script: Optional[str] = None  # JSON AST
    explanation: Optional[Explanation] = None
    assistant_message: Optional[str] = None  # 非最终轮时：Agent的回复文本
    error: Optional[str] = None


# ── WebSocket 消息 ──

class WSClientMessage(BaseModel):
    """客户端 → 服务端"""
    action: str = "message"  # "start" | "message" | "close"
    content: Optional[str] = None
    connected_toys: list[ToyApi] = []


class WSServerMessage(BaseModel):
    """服务端 → 客户端"""
    type: str = "message"  # "message" | "playbook" | "error"
    content: Optional[str] = None  # 普通回复 / 错误信息
    lua_script: Optional[str] = None
    play_script: Optional[str] = None  # JSON AST
    explanation: Optional[Explanation] = None
    playbook_name: Optional[str] = None
