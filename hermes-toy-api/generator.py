"""
Hermes oneshot 调用封装

调用 `hermes -s toy-play-generator -z "prompt"` 生成玩法脚本。
"""
import json
import logging
import os
import re
import subprocess
import tempfile
from typing import Optional

from models import ChatMessage, Explanation, ExplanationStep, ToyApi

logger = logging.getLogger("hermes-toy-api")

# ── 环境 ──
HERMES_BIN = "/home/wisecoach/.local/bin/hermes"


def _build_system_prompt(connected_toys: list[ToyApi]) -> str:
    """构建玩具上下文块（JSON AST 格式）"""
    if not connected_toys:
        return ""

    toys_block = "## 可用的玩具（生成的 JSON AST 必须使用以下确切的 toy ID，不得自创）\n\n"
    for t in connected_toys:
        toys_block += f"`{t.id}` ({t.name})\n"
        if t.api:
            for func, desc in t.api.items():
                toys_block += f"  - `{func}` — {desc}\n"
        toys_block += "\n"
    toys_block += "【铁律】玩具 ID 必须与列表一致，不能自创。\n"
    toys_block += "方法名必须使用具体的驱动方法名（如 rate、fill、read_pressure），不能用 set_intensity 等通用词。\n\n"
    return toys_block


def _build_conversation_prompt(
    user_message: str,
    history: list[ChatMessage],
    connected_toys: list[ToyApi],
    is_first_turn: bool,
) -> str:
    """
    构建发往 Hermes 的完整 prompt，包含：
    - 玩具上下文
    - 对话历史（服务端维护）
    - 当前用户输入
    """
    parts = []

    # 玩具上下文
    toys_block = _build_system_prompt(connected_toys)
    if toys_block:
        parts.append(toys_block)

    # 对话历史
    if history:
        parts.append("## 对话历史\n")
        for msg in history:
            role_label = "用户" if msg.role == "user" else "你"
            parts.append(f"{role_label}: {msg.content}")
        parts.append("")

    # 当前输入
    parts.append(f"## 当前用户输入\n用户: {user_message}\n")

    if is_first_turn:
        parts.append(
            "请根据以上信息，按 JSON AST 技能规则开始第一轮引导对话。一次只问一个问题。"
        )
    else:
        parts.append(
            "请根据以上信息和对话历史，继续对话。一次只问一个问题。"
            "如果用户的需求已经收集充分，生成 JSON AST 格式的最终玩法方案。"
        )

    return "\n".join(parts)


def _extract_playbook_name(output: str) -> str:
    """从 Hermes 输出中提取玩法名称，多级策略"""
    import re

    # 1. 从 JSON AST 的 name 字段读取
    json_match = re.search(r'```json\s*\n([\s\S]*?)```', output)
    if json_match:
        try:
            data = json.loads(json_match.group(1))
            name = data.get("name", "")
            if name and len(name) <= 20:
                return name
        except json.JSONDecodeError:
            pass

    # 2. 【方案名称】格式
    m = re.search(r'[🔥]?【(.+?)】', output)
    if m:
        name = m.group(1).strip()
        if name and len(name) <= 20:
            return name

    # 3. 玩法名称：xxx
    m = re.search(r'玩法名称[：:]\s*(.+?)[\r\n]', output)
    if m:
        name = m.group(1).strip()
        if name and len(name) <= 20:
            return name

    return "未命名玩法"


def _auto_generate_name(script: str) -> str:
    """根据 JSON AST 或脚本中的玩具 ID 自动生成玩法名称"""
    if not script:
        return "自定义玩法"

    # 优先从 JSON 的 toy_ids 读取
    try:
        data = json.loads(script)
        ids = data.get("toy_ids", [])
        if not ids:
            # 从 body 中嗅探
            for m in re.finditer(r'"toy":\s*"([^"]+)"', json.dumps(data.get("play", {}).get("body", []))):
                if m.group(1) not in ('wait', 'print', 'math'):
                    ids.append(m.group(1))
    except (json.JSONDecodeError, TypeError):
        # 回退到旧式 Lua 嗅探
        ids = []
        for m in re.finditer(r'(?:toy[._\[])?(\w+)(?:\])?:', script):
            tid = m.group(1)
            if tid in ('wait', 'print', 'math'):
                continue
            ids.append(tid)

    has = lambda p: any(p in tid.lower() for tid in ids)
    has_ems = has('ems') or has('shock')
    has_enema = has('enema') or has('pump') or has('plug')
    has_vibe = has('vibe') or has('mast') or has('vibrator') or has('cup')
    has_lock = has('lock')

    if has_ems and has_enema and has_vibe and has_lock:
        return '极限回响'
    if has_ems and has_enema and has_vibe:
        return '潮汐三重奏'
    if has_ems and has_enema:
        return '充盈电击'
    if has_ems and has_vibe:
        return '脉冲共鸣'
    if has_vibe and has_enema:
        return '潮涌震颤'
    if has_lock and (has_ems or has_vibe):
        return '枷锁回响'
    if has_ems or has_vibe:
        return '渐入佳境'
    if has_enema:
        return '充盈'

    return f'{len(ids)}机联动'


def _parse_hermes_output(output: str) -> dict:
    """
    解析 Hermes 输出，判断是中间回复还是最终方案。

    Returns:
        {"type": "message", "content": "..."}  # 中间轮次
        {"type": "playbook", "play_script": "{...}", "explanation": {...}}  # 最终方案
    """
    output = output.strip()
    if not output:
        return {"type": "message", "content": ""}

    # 检测 JSON AST 代码块（最终方案）
    json_block = re.search(r'```json\s*\n([\s\S]*?)```', output)
    has_version = '"version": 2' in output
    has_play = '"play"' in output and '"body"' in output

    if json_block or (has_version and has_play):
        # 提取 JSON AST
        if json_block:
            play_script = json_block.group(1).strip()
        else:
            # 从文本中尝试定位 JSON
            start = output.index('"version":')
            brace_start = output.rindex('{', 0, start)
            depth = 0
            for i in range(brace_start, len(output)):
                if output[i] == '{': depth += 1
                if output[i] == '}': depth -= 1
                if depth == 0:
                    play_script = output[brace_start:i+1]
                    break
            else:
                play_script = output

        # 尝试解析 JSON 获取元数据
        playbook_name = "未命名玩法"
        duration = 0
        steps = []
        try:
            data = json.loads(play_script)
            playbook_name = data.get("name", "未命名玩法")
            duration = data.get("duration_sec", 0)
            raw_steps = data.get("steps", [])
            for s in raw_steps:
                steps.append(ExplanationStep(
                    time=f"{s.get('time_sec', 0)}s",
                    action=s.get("desc", "")
                ))
        except json.JSONDecodeError:
            playbook_name = _extract_playbook_name(output)

        if playbook_name == "未命名玩法":
            playbook_name = _auto_generate_name(play_script)

        return {
            "type": "playbook",
            "playbook_name": playbook_name,
            "play_script": play_script,
            "explanation": {
                "duration_seconds": duration,
                "steps": [s.model_dump() for s in steps],
                "name": playbook_name,
            },
        }

    # 中间回复
    content = output
    content = re.sub(r'^```[\s\S]*?```\s*$', '', content, flags=re.DOTALL).strip()
    return {"type": "message", "content": content}


def hermes_generate(
    user_message: str,
    history: list[ChatMessage],
    connected_toys: list,
    skill_name: str = "toy-play-generator-json",
    timeout: int = 600,
) -> dict:
    """
    调用 Hermes oneshot 生成回复。

    Args:
        user_message: 当前用户输入
        history: 完整对话历史（不含当前输入）
        connected_toys: 已连接玩具列表（可以是 dict 或 ToyApi）
        skill_name: Hermes 技能名
        timeout: 超时秒数

    Returns:
        GenerateResponse 格式的 dict
    """
    # 统一转为 ToyApi 对象
    toys = [ToyApi(**t) if isinstance(t, dict) else t for t in connected_toys]
    is_first_turn = len(history) == 0
    prompt = _build_conversation_prompt(user_message, history, toys, is_first_turn)

    logger.info("Calling Hermes oneshot (skill=%s, history_len=%d, timeout=%ds)",
                skill_name, len(history), timeout)
    logger.debug("Prompt (first 200 chars): %s...", prompt[:200])

    # 写入临时 prompt 文件（避免 shell 转义）
    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False, encoding="utf-8") as f:
        f.write(prompt)
        tmp_path = f.name

    try:
        cmd = [
            HERMES_BIN,
            "-s", skill_name,
            "-z", f"@{tmp_path}",
            "-m", "deepseek-v4-flash",
        ]

        env = os.environ.copy()
        env["HERMES_PROFILE"] = "hentai_coder"
        # 不要覆写 HOME：Hermes profile 会自动处理 HOME 劫持
        # env["HOME"] = _REAL_HOME

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )

        if result.returncode != 0:
            stderr = result.stderr.strip()
            logger.error("Hermes failed (rc=%d): %s", result.returncode, stderr)
            return {
                "success": False,
                "error": f"Hermes 调用失败: {stderr}",
            }

        output = result.stdout.strip()
        logger.info("Hermes output length: %d chars", len(output))
        logger.debug("Output (first 300 chars): %s...", output[:300])

        if not output:
            return {
                "success": False,
                "error": "Hermes 返回空结果",
            }

        parsed = _parse_hermes_output(output)

        if parsed["type"] == "playbook":
            return {
                "success": True,
                "play_script": parsed["play_script"],
                "explanation": parsed["explanation"],
                "playbook_name": parsed["playbook_name"],
            }
        else:
            return {
                "success": True,
                "assistant_message": parsed["content"],
            }

    except subprocess.TimeoutExpired:
        logger.error("Hermes timed out after %ds", timeout)
        return {"success": False, "error": f"Hermes 超时（{timeout}s）"}
    except FileNotFoundError:
        logger.error("Hermes binary not found: %s", HERMES_BIN)
        return {"success": False, "error": f"Hermes 调用失败: 找不到 CLI ({HERMES_BIN})"}
    except Exception as e:
        logger.exception("Hermes call failed")
        return {"success": False, "error": f"Hermes 调用异常: {e}"}
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
