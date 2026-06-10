#!/usr/bin/env bash
# Hermes Toy API 启动脚本
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# 虚拟环境
VENV="$DIR/venv"
if [ ! -d "$VENV" ]; then
    echo "[setup] 创建虚拟环境..."
    python3 -m venv "$VENV"
    echo "[setup] 安装依赖..."
    "$VENV/bin/pip" install -r requirements.txt -q
fi

echo "[start] 启动 Hermes Toy API @ http://0.0.0.0:8765"
echo "[start] Health: http://localhost:8765/api/health"

exec "$VENV/bin/uvicorn" main:app \
    --host 0.0.0.0 \
    --port 8765 \
    --reload \
    --log-level info
