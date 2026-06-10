# 动态情趣玩具玩法脚本框架 · 设计文档

> 版本：v1.0
> 日期：2026-06-10
> 目标：给「役次元（YOKONEX）」玩具 APP 官方做 DEMO

---

## 目录

1. [架构总览](#1-架构总览)
2. [系统组件](#2-系统组件)
3. [通信协议](#3-通信协议)
4. [Agent 技能设计](#4-agent-技能设计)
5. [LuaJ 运行时设计](#5-luaj-运行时设计)
6. [Flutter APP 架构](#6-flutter-app-架构)
7. [ToyDriver 接口定义](#7-toydriver-接口定义)
8. [已支持玩具能力映射](#8-已支持玩具能力映射)
9. [DEMO 开发路线图](#9-demo-开发路线图)
10. [附录：示例完整交互流程](#10-附录示例完整交互流程)

---

## 1. 架构总览

```
┌─────────────────────────────────────────────────────────┐
│                     Flutter APP（手机端）                  │
│                                                         │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │ 对话页面  │───→│ Lua 脚本预览  │───→│ 脚本执行引擎  │  │
│  │ (聊天UI)  │    │ (代码+步骤)   │    │ (LuaJ运行)   │  │
│  └────┬─────┘    └──────────────┘    └──────┬───────┘  │
│       │                                      │          │
│       │ HTTP POST                            │ BLE 写入  │
│       │ /api/generate                        │          │
│       ▼                                      ▼          │
│  ┌──────────────────────────────────────────────────┐  │
│  │ BLE 管理器 + ToyDriver 注册表                   │  │
│  │ (扫描→连接→查询能力→注册到ToyRegistry)          │  │
│  └──────────────────────────────────────────────────┘  │
└──────────────────────┬──────────────────────────────────┘
                       │ HTTP (局域网)
                       ▼
┌─────────────────────────────────────────────────────────┐
│                   本地 Hermes 服务（电脑端）               │
│                                                         │
│  ┌───────────────────┐    ┌──────────────────────────┐ │
│  │ FastAPI 包装服务   │───→│ hermes -z "prompt"       │ │
│  │ POST /generate     │    │ (oneshot模式)            │ │
│  │ POST /explain      │    │ + 玩具技能上下文          │ │
│  └───────────────────┘    └──────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 核心流程

```
用户输入 → HTTP POST → Hermes 生成 Lua → 返回 APP → 用户预览
                                                          ↓
                                                    确认？→ 是 → LuaJ 执行 → BLE 控制玩具
                                                     │
                                                    否 → 修改描述 → 重新生成
```

---

## 2. 系统组件

### 2.1 Flutter APP（你开发）

| 组件 | 职责 |
|------|------|
| **对话页面** | 用户输入自然语言描述玩法需求，展示对话历史 |
| **脚本预览组件** | 展示生成的 Lua 源码 + 步骤化解读（人类可读） |
| **脚本缓存管理器** | 将生成的 Lua 脚本保存到本地，支持重复执行 |
| **LuaJ 运行时** | 嵌入 LuaJ 解释器，执行 Lua 脚本调用 ToyDriver |
| **BLE 管理器** | 扫描→连接→查询能力→注册玩具到运行时 |
| **ToyRegistry** | 统一管理已连接玩具的 ID → ToyDriver 映射 |
| **HTTP 客户端** | 向本地 Hermes 服务发请求，获取生成的 Lua 脚本 |

### 2.2 Hermes API 服务（我帮你搭）

| 组件 | 职责 |
|------|------|
| **FastAPI 服务** | HTTP 接口，接收请求并调用 Hermes one-shot |
| **玩具技能提示词** | 注入玩具能力上下文，让 Agent 正确生成 Lua |
| **脚本后处理** | 解析 Lua 代码为步骤化解读文本 |
| **会话管理** | 简单的 session_id 支持（可选） |

---

## 3. 通信协议

### 3.1 APP → Hermes 服务

```
POST http://<电脑IP>:8765/api/generate
Content-Type: application/json

{
  "user_message": "震动棒先温柔挑逗，然后电击器同步低频脉冲，灌肠机慢慢注水，最后一起高潮",
  "session_id": "session_abc123",       // 可选，用于对话上下文
  "connected_toys": [
    {
      "id": "vibe_1",
      "type": "vibrator_v1",
      "name": "震动棒",
      "api": {
        "rate(motor_a, motor_b, motor_c)": "三马达力度 0-20",
        "set_mode(motor_select, mode_id)": "固定模式",
        "stop()": "停止所有马达"
      }
    },
    {
      "id": "ems_1",
      "type": "ems_v2",
      "name": "电击器二代",
      "api": {
        "set_channel_fixed(channel, mode_id, intensity)": "固定模式, 强度0-276",
        "set_channel_realtime(channel, intensity, frequency, pulse_width)": "自定义EMS参数",
        "set_motor(state)": "内置马达",
        "stop_all()": "停止所有通道"
      }
    },
    {
      "id": "enema_1",
      "type": "enema_v1",
      "name": "灌肠机",
      "api": {
        "fill(seconds)": "注水，时间秒",
        "drain(seconds)": "排水，时间秒",
        "pause()": "暂停所有泵",
        "get_pressure()": "获取压力值",
        "get_battery()": "获取电量"
      }
    }
  ],
  "history": [
    {"role": "user", "content": "我想要一个渐进式的玩法"},
    {"role": "assistant", "content": "...（上一轮生成的脚本）"}
  ]
}
```

### 3.2 Hermes 服务 → APP

```json
{
  "success": true,
  "session_id": "session_abc123",
  "lua_script": "-- 震动棒温柔挑逗\n-- 电击器同步低频脉冲\n-- 灌肠机注水\n-- 最后一起爆发\n\n-- 步骤1：震动棒低速启动\nprint(\"[开始] 启动所有玩具\")\ntoy.vibe_1:rate(8, 0, 3)\ntoy.ems_1:set_channel_fixed(\"A\", 2, 50)\ntoy.ems_1:set_channel_fixed(\"B\", 2, 40)\n\n-- 步骤2：等待5秒后灌肠机开始注水\nwait(5000)\ntoy.enema_1:fill(20)\n\n-- 步骤3：同步加强\nwait(10000)\ntoy.vibe_1:rate(18, 0, 12)\ntoy.ems_1:set_channel_realtime(\"A\", 180, 30, 50)\ntoy.ems_1:set_channel_realtime(\"B\", 150, 25, 40)\n\n-- 步骤4：高潮爆发\nwait(15000)\ntoy.vibe_1:rate(20, 0, 20)\ntoy.ems_1:set_channel_fixed(\"A\", 8, 250)\ntoy.ems_1:set_channel_fixed(\"B\", 8, 220)\n\n-- 步骤5：停止所有\nwait(5000)\nprint(\"[结束] 停止所有玩具\")\ntoy.vibe_1:stop()\ntoy.ems_1:stop_all()\ntoy.enema_1:pause()",
  "explanation": {
    "duration_seconds": 35,
    "steps": [
      { "time": "0s",      "action": "震动棒低速震动（A马达30%），电击器A/B通道轻柔脉冲（强度50/40）" },
      { "time": "5s",      "action": "灌肠机开始注水，持续20秒" },
      { "time": "15s",     "action": "震动棒加强到90%，电击器切换到自定义高频模式（强度180/150）" },
      { "time": "30s",     "action": "⛰️ 高潮阶段：震动棒满速，电击器高强度模式8（强度250/220）" },
      { "time": "35s",     "action": "所有玩具停止" }
    ]
  }
}
```

---

## 4. Agent 技能设计

### 4.1 Hermes 自定义技能

需要在 Hermes 里创建一个专门生成玩法脚本的 **Skill**。每次请求时通过 `-s` 加载，或者在 FastAPI 包装里通过 `@prompt_file` 注入。

技能要点：

```
你是一个情趣玩具玩法脚本生成器。
你根据用户描述和已连接的玩具列表，生成 Lua 脚本。

## 规则

1. 只使用 connected_toys 里声明的玩具 ID 和 API 函数
2. 所有玩具 API 通过 `toy.<id>:<function>(<args>)` 调用
3. 使用 `wait(毫秒)` 来控制时间
4. 不要在 wait 期间让玩具继续做无用操作——wait 前后重新设置状态
5. 生成的脚本必须包含步骤说明注释（中文）
6. 控制强度逐步递增，不要直接满强度
7. 多玩具配合时注意节奏——不同玩具在不同时间点触发
8. 脚本必须包含安全机制：最后必须有停止所有玩具的操作
9. 脚本最大长度不超过 200 行

## 运行环境

- LuaJ 5.2 语法
- 支持 wait(ms)、print(msg)
- 所有玩具函数都是 suspend 异步的
- 默认 5 分钟超时

## 输出格式

先输出 Lua 脚本，然后空一行，再输出步骤化解读。
```

### 4.2 FastAPI 包装服务代码结构

```
hermes-toy-api/
├── main.py              # FastAPI 服务入口
├── generator.py         # 调用 hermes -z 的核心逻辑
├── explainer.py         # Lua → 步骤化解读 的解析
├── prompt_templates.py  # 技能提示词模板
├── requirements.txt     # fastapi, uvicorn
└── run.sh               # 启动脚本
```

核心代码大致这样：

```python
# generator.py
import subprocess, json, tempfile, os
import pwd

_REAL_HOME = pwd.getpwuid(os.getuid()).pw_dir
HERMES_BIN = os.path.join(_REAL_HOME, ".local/bin/hermes")

def generate_lua(user_message: str, connected_toys: list, history: list = []) -> dict:
    prompt = build_prompt(user_message, connected_toys, history)
    
    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
        f.write(prompt)
        tmp_path = f.name
    
    try:
        result = subprocess.run(
            [HERMES_BIN, "-z", f"@{tmp_path}"],
            capture_output=True, text=True, timeout=120,
            env={**os.environ, "HERMES_PROFILE": "hentai_coder"},
        )
        
        if result.returncode != 0:
            return {"success": False, "error": result.stderr}
        
        output = result.stdout.strip()
        lua_script, explanation = parse_output(output)
        
        return {
            "success": True,
            "lua_script": lua_script,
            "explanation": explanation,
        }
    finally:
        os.unlink(tmp_path)
```

---

## 5. LuaJ 运行时设计

### 5.1 Lua API 绑定

LuaJ 通过元表（metatable）把 Kotlin 对象暴露到 Lua 全局命名空间。

```kotlin
// LuaToyBinding.kt
class LuaToyBinding(private val registry: ToyRegistry) {
    
    fun bind(luaRuntime: LuaRuntime) {
        // 注册 toy 全局表
        val toyTable = LuaTable()
        
        // 当 Lua 里写 toy.vibe_1 时，查找注册表
        toyTable.setMetatable(object : LuaTable() {
            override fun get(key: Any?): Any? {
                val toyId = key as? String ?: return null
                val driver = registry.getDriver(toyId) ?: return null
                return ToyLuaProxy(driver)  // 动态代理
            }
        })
        
        luaRuntime.setGlobal("toy", toyTable)
        
        // 注册全局函数
        luaRuntime.setGlobal("wait", WaitFunction())
        luaRuntime.setGlobal("print", PrintFunction())
    }
}

// 动态代理：将 Lua 函数调用转发到 Kotlin 方法
class ToyLuaProxy(private val driver: ToyDriver) : LuaTable() {
    override fun get(key: Any?): Any? {
        val methodName = key as? String ?: return null
        // 返回一个 LuaFunction，调用时反射执行 driver 的同名方法
        return object : LuaFunction() {
            override fun call(arguments: Varargs): Varargs {
                val args = argumentsToList(arguments)
                val method = driver.javaClass.getMethod(methodName, *args.map { it.javaClass }.toTypedArray())
                method.invoke(driver, *args.toTypedArray())
                return LuaValue.NIL
            }
        }
    }
}
```

### 5.2 运行时安全机制

| 机制 | 实现 |
|------|------|
| 超时熔断 | Coroutine + withTimeout(5min) |
| 脚本大小限制 | 执行前检查字符数 < 50KB |
| 紧急停止 | UI 层「停止」按钮 → cancel coroutine |
| BLE 写入限频 | ToyDriver 内部 throttle（最多 20次/秒） |

### 5.3 脚本缓存

```kotlin
// ScriptCacheManager.kt
class ScriptCacheManager(private val context: Context) {
    private val cacheDir = File(context.filesDir, "playbook_cache")
    
    fun save(name: String, script: String, explanation: String) {
        val entry = PlaybookCacheEntry(
            id = UUID.randomUUID().toString(),
            name = name,
            script = script,
            explanation = explanation,
            createdAt = System.currentTimeMillis()
        )
        val file = File(cacheDir, "${entry.id}.json")
        file.writeText(Json.encodeToString(entry))
    }
    
    fun list(): List<PlaybookCacheEntry> {
        return cacheDir.listFiles()
            ?.map { Json.decodeFromString<PlaybookCacheEntry>(it.readText()) }
            ?.sortedByDescending { it.createdAt }
            ?: emptyList()
    }
}

data class PlaybookCacheEntry(
    val id: String,
    val name: String,
    val script: String,
    val explanation: String,
    val createdAt: Long
)
```

---

## 6. Flutter APP 架构

### 6.1 页面路由

```
/                    → 主页面（玩具连接状态 + 已缓存玩法列表）
/chat               → 对话页面（与 Agent 聊天生成玩法）
/preview            → 脚本预览页面（Lua 代码 + 步骤化解读）
/executing          → 执行中页面（实时状态 + 紧急停止按钮）
/playbook-library   → 已缓存的玩法库（可重复执行）
```

### 6.2 对话页面 UI 设计

```
┌──────────────────────────────────────┐
│  🔫 玩法生成                           │
│                                       │
│  ┌─ 当前已连接玩具 ──────────────────┐ │
│  │ 📳 震动棒 (vibe_1)    🟢 已连接  │ │
│  │ ⚡ 电击器二代 (ems_1)  🟢 已连接  │ │
│  │ 💧 灌肠机 (enema_1)   🟢 已连接  │ │
│  └────────────────────────────────────┘ │
│                                       │
│  ┌─ 对话历史 ────────────────────────┐ │
│  │ 你: 我想要一个渐进式的玩法         │ │
│  │ 📜 Agent: 好的，我来设计一个...   │ │
│  │     [预览脚本 ▸]                  │ │
│  │                                   │ │
│  │ 你: 加一点电击脉冲在中间         │ │
│  │ 📜 Agent: 好的，更新方案：       │ │
│  │     [预览脚本 ▸]                  │ │
│  └────────────────────────────────────┘ │
│                                       │
│  ┌────────────────────────────────┐   │
│  │ 输入玩法描述...          [发送]│   │
│  └────────────────────────────────┘   │
└──────────────────────────────────────┘
```

### 6.3 预览页面 UI 设计

```
┌──────────────────────────────────────┐
│  🔮 玩法预览                          │
│                                       │
│  ┌─ 步骤化解读 ────────────────────┐ │
│  │                                   │ │
│  │  ⏱ 总时长：约 35 秒              │ │
│  │                                   │ │
│  │  ① 0-5秒   震动棒低速震动        │ │
│  │             电击器轻柔脉冲        │ │
│  │  ② 5-15秒  灌肠机注水 20秒      │ │
│  │  ③ 15-30秒 震动棒加强到90%      │ │
│  │             电击器高频脉冲        │ │
│  │  ④ 30-35秒 ⛰️ 高潮爆发！        │ │
│  │             震动棒满速            │ │
│  │             电击器高强度          │ │
│  │  ⑤ 35秒    全部停止              │ │
│  └────────────────────────────────────┘ │
│                                       │
│  ┌─ Lua 脚本预览 ──────────────────┐ │
│  │ toy.vibe_1:rate(8, 0, 3)        │ │
│  │ toy.ems_1:set_channel_fixed(...) │ │
│  │ wait(5000)                       │ │
│  │ toy.enema_1:fill(20)            │ │
│  │ ...                              │ │
│  └────────────────────────────────────┘ │
│                                       │
│  玩法名称: [渐进高潮三部曲]           │
│                                       │
│  [▶ 立即执行]  [♻ 重新生成]  [💾 缓存] │
└──────────────────────────────────────┘
```

---

## 7. ToyDriver 接口定义

以下是你 APP 端需要实现的接口。每个玩具型号创建一个 Driver 类。

### 7.1 核心接口

```kotlin
/**
 * 玩具驱动接口 — 所有具体玩具驱动必须实现
 */
interface ToyDriver {
    /** 玩具唯一类型标识 */
    val toyType: ToyType
    
    /** 玩具能力描述（给 Agent 用） */
    val capabilities: ToyCapability
    
    /** BLE 连接后初始化查询设备信息 */
    suspend fun queryDeviceInfo(): DeviceInfo
    
    /** 紧急停止 — 停止所有动作 */
    suspend fun emergencyStop()
    
    /** 获取电池电量 0-100 */
    suspend fun getBattery(): Int
}

/**
 * 玩具注册表
 */
interface ToyRegistry {
    /** 注册一个已连接的玩具 */
    fun register(toyId: String, driver: ToyDriver)
    
    /** 移除断开的玩具 */
    fun unregister(toyId: String)
    
    /** 获取已注册的驱动 */
    fun getDriver(toyId: String): ToyDriver?
    
    /** 获取所有已注册玩具的能力快照（发 Agent 用） */
    fun getCapabilitySnapshot(): List<ConnectedToyInfo>
    
    /** 获取所有已注册 */
    fun getAllDrivers(): Map<String, ToyDriver>
}
```

### 7.2 各玩具特化接口

```kotlin
// ============ 跳蛋/飞机杯 ============
class VibratorDriver(private val bleDevice: BLEDevice) : ToyDriver {
    override val toyType = ToyType.VIBRATOR
    
    /** 速率控制：三马达力度 0-20 */
    suspend fun rate(motorA: Int = 0, motorB: Int = 0, motorC: Int = 0)
    
    /** 固定模式 */
    suspend fun setMode(motorSelect: Int, modeId: Int)
    
    /** 停止所有马达 */
    suspend fun stop()
}

// ============ 电击器一代 ============
class EMSV1Driver(private val bleDevice: BLEDevice) : ToyDriver {
    override val toyType = ToyType.EMS_V1
    
    /** 固定模式控制 */
    suspend fun setChannelFixed(channel: String, modeId: Int, intensity: Int)
    // channel: "A" | "B" | "AB"
    // modeId: 1-16
    // intensity: 0-276
    
    /** 马达控制 */
    suspend fun setMotor(state: Int)
    // state: 0=关闭, 1=开启, 0x11/0x12/0x13=预设频率
    
    /** 停止 */
    suspend fun stopAll()
}

// ============ 电击器二代（更丰富的接口） ============
class EMSV2Driver(private val bleDevice: BLEDevice) : ToyDriver {
    override val toyType = ToyType.EMS_V2
    
    /** 固定模式 */
    suspend fun setChannelFixed(channel: String, modeId: Int, intensity: Int)
    
    /** 实时模式（自定义频率+脉宽） */
    suspend fun setChannelRealtime(channel: String, intensity: Int, frequency: Int, pulseWidth: Int)
    // frequency: 1-100 Hz
    // pulseWidth: 0-100 us
    
    /** 频率模式（复杂时序脉冲序列） */
    suspend fun setChannelFrequencyPattern(channel: String, intensity: Int, pattern: List<Pair<Int, Int>>)
    // pattern: [(freq1, pw1), (freq2, pw2), ...] 最多100步
    
    /** 马达 */
    suspend fun setMotor(state: Int)
    
    /** 计步器 */
    suspend fun setStepCounter(state: Int)
    
    /** 角度传感器 */
    suspend fun setAngleSensor(state: Int)
    
    /** 停止 */
    suspend fun stopAll()
    
    /** 查询状态 */
    suspend fun queryChannelStatus(channel: String): ChannelStatus
    suspend fun queryMotorStatus(): Int
    suspend fun queryStepData(): Int
    suspend fun queryAngleData(): Int
}

// ============ 灌肠机（加密通信） ============
class EnemaDriver(private val bleDevice: BLEDevice) : ToyDriver {
    companion object {
        val AES_KEY = byteArrayOf(
            0xF6, 0x38, 0xBC.toByte(), 0x9C, 0xFA.toByte(),
            0x47, 0x74, 0x80.toByte(), 0xAB.toByte(), 0x32,
            0x42, 0xF6.toByte(), 0xB0.toByte(), 0x45, 0x57, 0xA1.toByte()
        )
    }
    
    override val toyType = ToyType.ENEMA
    
    /** 注水：蠕动泵正转 */
    suspend fun fill(seconds: Int)
    
    /** 排水：抽水泵正转 */
    suspend fun drain(seconds: Int)
    
    /** 暂停所有泵 */
    suspend fun pause()
    
    /** 查询工作状态 */
    suspend fun queryStatus(): EnemaStatus
    
    /** 获取压力值（每200ms自动上报） */
    suspend fun getPressure(): Pair<Int, Int> // (sensorA, sensorB)
}
```

---

## 8. 已支持玩具能力映射

| 玩具型号 | BLE UUID | ToyType | 关键控制 | 特殊能力 |
|---------|---------|---------|---------|---------|
| 跳蛋/飞机杯 | FF40 | VIBRATOR | 3马达速率 0-20 + 固定模式 | - |
| 电击器一代 | FF30 | EMS_V1 | 2通道固定/自定义模式，马达 | - |
| 电击器二代 | FF30 | EMS_V2 | 同上 + 频率模式(100步)，计步，角度 | 陀螺仪，步数追踪 |
| 灌肠机 | FFB0 | ENEMA | 2泵 + AES加密通信 | 压力传感器(200ms) |

> 注意：所有电击器共用 FF30 的 BLE UUID，通过产品型号 ID 区分一代/二代

---

## 9. DEMO 开发路线图

### Phase 1：Hermes API 服务 + Agent Skill（我来搞 ✅）

- [x] 完成架构设计
- [ ] 写 FastAPI 包装服务（`hermes-toy-api/`）
- [ ] 创建 Hermes Skill（生成 Lua 玩法脚本）
- [ ] 测试端到端：输入描述 → 生成 Lua + 解释

### Phase 2：Flutter APP 基础（你搞）

- [ ] BLE 扫描 + 连接 + 设备信息查询
- [ ] 各玩具 ToyDriver 实现（对照第 7 节接口）
- [ ] ToyRegistry 注册表
- [ ] HTTP 客户端 → 调用本地 Hermes 服务

### Phase 3：Flutter UI（你搞）

- [ ] 对话聊天页面（类似 ChatGPT 风格）
- [ ] 脚本预览页面（代码 + 步骤化解读）
- [ ] 执行页面（实时状态 + 紧急停止）
- [ ] 本地玩法缓存库

### Phase 4：LuaJ 集成 + 联调（我俩搞）

- [ ] Flutter 嵌入 LuaJ（通过 platform channel）
- [ ] LuaToyBinding 绑定实现
- [ ] 端到端联调：对话 → 生成 → 预览 → 执行 → 控制玩具

---

## 10. 附录：示例完整交互流程

```
用户打开 APP，BLE 连接了 3 个玩具：
  - 震动棒（vibe_1）
  - 电击器二代（ems_1）
  - 灌肠机（enema_1）

用户在聊天框输入：
  "来一套前戏→高潮→收尾的完整流程，大概5分钟，从轻柔开始"

APP 发送 POST /api/generate（携带 connected_toys）
→ Hermes 生成 Lua 脚本 + 步骤解读
→ APP 展示预览页面

用户看到步骤：
  ⏱ 总时长 4分30秒
  ① 0-60秒    震动棒低速震动 + 电击器极低强度
  ② 60-120秒  逐渐加强
  ③ 120-180秒 灌肠机开始注水，震动棒中速
  ④ 180-240秒 高强度阶段
  ⑤ 240-270秒 ⛰️ 高潮爆发
  ⑥ 270秒     逐渐减弱→停止

用户觉得不错，点「执行」
→ LuaJ 执行脚本
→ BLE 指令依次下发
→ 实时状态显示在 APP 上（当前阶段/剩余时间）
→ 执行完毕或用户点「停止」

用户可以把这套玩法缓存到本地，命名为「我的标准套餐」
下次可以直接从缓存库选择执行，不用再连 Agent。
```

---

## 下一步行动

> 设计文档写完！😎

**你这边可以开始的：**
1. 开始搭 Flutter 工程 + BLE 连接层
2. 实现各玩具的 ToyDriver（对照第 7 节接口）

**我这边马上搞的：**
1. 写出 `hermes-toy-api/` FastAPI 包装服务
2. 写出 Hermes Skill（专门生成玩法 Lua 脚本）
3. 本地跑通：输入描述 → 生成脚本

**确认一下：** 文档里有什么需要调整或者你觉得漏了的？没问题的话我接着就开始撸 Hermes API 服务的代码了 ( ͡° ͜ʖ ͡°)
