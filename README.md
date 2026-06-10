# YOKONEX Play — 动态情趣玩具玩法框架

> 项目代号：`yokonex-play`
> 目标：为「役次元（YOKONEX）」玩具 APP 官方开发 DEMO，实现 AI 对话设计多玩具配合玩法 → 自动生成 Lua 脚本 → APP 执行控制玩具

---

## 项目结构

```
yokonex-play/
├── flutter_app/                 # Flutter 移动端 APP（待搭建）
├── hermes-toy-api/              # Hermes API 包装服务（待搭建）
├── docs/                        # 设计文档
│   ├── 01-framework-design.md   # 整体框架设计
│   ├── 02-skill-design.md       # Hermes Skill 对话式设计
│   ├── 03-project-structure.md  # 项目目录结构
│   ├── 04-ui-spec.md            # UI 界面规格
│   └── 05-ui-flow.excalidraw    # UI 线框图（拖到 excalidraw.com 打开）
└── skills/
    └── toy-play-generator.md    # Hermes Skill（玩法对话设计师）
```

## 核心流程

```
用户自然语言描述 → Hermes Agent 多轮对话引导
       ↓
确认方案 → 生成 Lua 脚本 + 步骤解读
       ↓
Flutter APP 预览 → 用户确认执行
       ↓
LuaJ 运行时解析脚本 → BLE 指令 → 多个玩具协作控制
```

## 已支持的玩具类型

| 玩具 | BLE 协议 | 核心控制 |
|------|---------|---------|
| 电子锁 | — | 上锁/解锁 |
| 灌肠器（充气肛塞） | TDL_YISKJ-003 + AES-128 | 气压读取/充气/放气/注水/排水 |
| 电击器 | YSKJ_EMS_BLE V1/V2 | 电流强度+波形/频率模式 |
| 飞机杯 | YSKJ_TOY_BLE V1.1 | 旋转/振动/抽气三马达 |
