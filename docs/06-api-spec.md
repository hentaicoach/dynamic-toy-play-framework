# API 接口规范

> 定义 Hermes 服务 ↔ Flutter APP 之间的 HTTP 通信接口

---

## Base URL

```
http://<电脑局域网IP>:8765
```

## 1. 生成玩法方案

### 请求

```
POST /api/generate
Content-Type: application/json
```

```json
{
  "user_message": "震动棒先温柔挑逗，然后电击器同步低频脉冲，灌肠机慢慢注水",
  "session_id": "session_abc123",
  "connected_toys": [
    {
      "id": "lock_1",
      "type": "lock",
      "name": "电子锁",
      "api": {
        "lock()": "上锁",
        "unlock()": "解锁"
      }
    },
    {
      "id": "enema_1",
      "type": "enema",
      "name": "灌肠器（充气肛塞）",
      "api": {
        "read_pressure()": "读取气压值（0-100）",
        "inflate(seconds)": "充气",
        "deflate(seconds)": "放气",
        "fill(seconds)": "注水",
        "drain(seconds)": "排水"
      }
    },
    {
      "id": "ems_1",
      "type": "ems",
      "name": "电击器",
      "api": {
        "set_current(intensity, waveform)": "设置电流强度(0-100)和波形(0-16)",
        "stop()": "停止放电"
      }
    },
    {
      "id": "mast_1",
      "type": "masturbator",
      "name": "飞机杯",
      "api": {
        "rotate(speed)": "旋转电机(0-100)",
        "vibrate(speed)": "振动电机(0-100)",
        "suction(speed)": "抽气电机(0-100)",
        "stop()": "停止所有电机"
      }
    }
  ],
  "history": [
    {"role": "user", "content": "我想要一个渐进式的玩法"}
  ]
}
```

### 响应

```json
{
  "success": true,
  "session_id": "session_abc123",
  "lua_script": "-- Lua 脚本内容...",
  "explanation": {
    "name": "枷锁回响 · 赎罪计时",
    "duration_seconds": 90,
    "steps": [
      {"time": "0s", "action": "电子锁上锁，飞机杯启动"},
      {"time": "等待", "action": "夹紧肛塞达气压阈值"},
      {"time": "0-30s", "action": "赎罪计时，飞机杯加速"},
      {"time": "30-90s", "action": "⛰️ 电击惩罚递增"},
      {"time": "90s", "action": "电子锁解锁，全部停止"}
    ]
  },
  "playbook_id": "playbook_20260610_001"
}
```

## 2. 对话迭代（后续轮次）

支持多轮对话，通过 `session_id` 保持上下文。

```
POST /api/generate
```

请求同上，`history` 数组包含之前的全部对话轮次。

## 3. 健康检查

```
GET /health
```

```json
{
  "status": "ok",
  "hermes_version": "2.x",
  "skill_loaded": "toy-play-generator"
}
```
