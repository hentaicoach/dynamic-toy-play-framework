# YOKONEX 动态玩法框架 · 项目目录结构

> DEMO 项目代号：yokonex-play
>
> 整体结构分为三大部分：
>   1. flutter_app/  — 移动端 APP（Flutter）
>   2. hermes-toy-api/ — 本地 Agent 服务（Python FastAPI）
>   3. docs/ — 设计文档

───────────────────────────────────────────────────────────────
yokonex-play/
│
├── flutter_app/                    # ──── Flutter APP ────
│   ├── lib/
│   │   ├── main.dart               # APP 入口
│   │   ├── app.dart                 # MaterialApp + 路由配置
│   │   │
│   │   ├── config/
│   │   │   ├── constants.dart       # 全局常量（BLE UUID、API 地址等）
│   │   │   └── theme.dart           # 主题配色、字体
│   │   │
│   │   ├── models/                  # 数据模型
│   │   │   ├── toy.dart             # 玩具模型（id, type, name, status）
│   │   │   ├── toy_capability.dart  # 玩具能力描述（接口签名+参数范围）
│   │   │   ├── playbook.dart        # 玩法方案（name, lua, steps, id）
│   │   │   ├── chat_message.dart    # 对话消息模型
│   │   │   └── ble_device.dart      # BLE 设备扫描结果
│   │   │
│   │   ├── services/
│   │   │   ├── ble/
│   │   │   │   ├── ble_manager.dart         # BLE 扫描/连接/断开
│   │   │   │   ├── toy_registry.dart        # 已连接玩具注册表
│   │   │   │   └── drivers/                 # 各玩具 BLE 驱动
│   │   │   │       ├── toy_driver.dart      # ToyDriver 接口基类
│   │   │   │       ├── vibrator_driver.dart  # 飞机杯（旋转/振动/抽气）
│   │   │   │       ├── ems_driver.dart       # 电击器（电流+波形）
│   │   │   │       ├── enema_driver.dart     # 灌肠器（气压/充气/注水）
│   │   │   │       └── lock_driver.dart      # 电子锁（上锁/解锁）
│   │   │   │
│   │   │   ├── lua/
│   │   │   │   ├── lua_runtime.dart     # LuaJ 执行引擎封装
│   │   │   │   ├── lua_binding.dart     # Kotlin ↔ Lua 绑定层
│   │   │   │   └── lua_sandbox.dart     # 执行安全限制（超时/限频）
│   │   │   │
│   │   │   ├── hermes_api.dart          # HTTP 客户端 → Hermes 服务
│   │   │   └── playbook_cache.dart      # 本地玩法脚本缓存
│   │   │
│   │   ├── providers/               # 状态管理（Riverpod）
│   │   │   ├── connection_provider.dart   # BLE 连接状态
│   │   │   ├── chat_provider.dart         # 对话历史 + 消息流
│   │   │   ├── playbook_provider.dart     # 当前方案状态
│   │   │   └── execution_provider.dart    # 脚本执行状态
│   │   │
│   │   ├── pages/                   # ──── 页面 ────
│   │   │   ├── home_page.dart           # 🏠 首页看板
│   │   │   ├── connect_page.dart        # 🔗 BLE 连接管理
│   │   │   ├── chat_page.dart           # 💬 AI 对话设计玩法
│   │   │   ├── preview_page.dart        # 📜 脚本预览（步骤+Lua）
│   │   │   ├── execution_page.dart      # ▶ 执行中（实时状态）
│   │   │   └── library_page.dart        # 📚 已缓存玩法库
│   │   │
│   │   └── widgets/                 # ──── 可复用组件 ────
│   │       ├── toy_card.dart            # 玩具状态卡片
│   │       ├── toy_icon.dart            # 玩具图标（按类型）
│   │       ├── step_timeline.dart       # 步骤时间轴
│   │       ├── chat_bubble.dart         # 对话气泡
│   │       ├── intensity_slider.dart    # 强度滑条
│   │       └── emergency_stop_button.dart # 紧急停止按钮
│   │
│   ├── assets/
│   │   ├── images/                   # 图标、配图
│   │   │   ├── toys/                 # 各玩具图标
│   │   │   │   ├── lock.png / .svg
│   │   │   │   ├── enema.png
│   │   │   │   ├── ems.png
│   │   │   │   └── masturbator.png
│   │   │   └── logo.png
│   │   └── fonts/                    # 自定义字体（可选）
│   │
│   ├── test/
│   │   ├── services/
│   │   │   ├── ble_manager_test.dart
│   │   │   └── lua_runtime_test.dart
│   │   └── pages/
│   │       └── chat_page_test.dart
│   │
│   ├── pubspec.yaml
│   ├── analysis_options.yaml
│   └── README.md
│
├── hermes-toy-api/                  # ──── Hermes 服务端 ────
│   ├── main.py                      # FastAPI 入口
│   ├── config.py                    # 配置（端口、Hermes 路径等）
│   ├── models.py                    # 请求/响应模型（Pydantic）
│   ├── generator.py                 # 调用 hermes -z 的核心
│   ├── explainer.py                 # Lua → 步骤解读的解析器
│   ├── prompt_templates.py          # 提示词模板组装
│   ├── requirements.txt             # fastapi, uvicorn, pydantic
│   └── run.sh                       # 启动脚本
│
├── docs/                            # ──── 设计文档 ────
│   ├── index.md                     # 文档索引
│   ├── 01-framework-design.md       # 整体框架设计
│   ├── 02-skill-design.md           # Skill 对话式设计
│   ├── 03-api-spec.md               # Hermes API 接口规范
│   ├── 04-ui-flow.md                # UI 界面流程
│   └── 05-toy-protocols.md          # 各玩具 BLE 协议参考
│
└── README.md                        # 项目总 README
