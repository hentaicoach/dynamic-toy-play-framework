# 示例玩法脚本：束缚逃脱 · 递增惩罚

> 对应对话日志中用户确认的「束缚逃脱」玩法方案

## 玩具配置

| ID | 类型 | 能力 |
|---|------|------|
| `lock_1` | 电子锁 (BLE) | `lock()`, `unlock()` |
| `enema_1` | 灌肠机（充气肛塞） | `read_pressure()` |
| `ems_1` | 电击器 (FF30) | `set_current(level, waveform)`, `stop()` |
| `mast_1` | 飞机杯 (FF40, 3马达) | `rate(m1, m2, m3)`, `stop()` |

## 对话中确认的参数

| 参数 | 值 | 确认方式 |
|------|----|---------|
| 计时结构 | 30s忍耐 + 60s递增 → 解锁 | 选项B |
| 电击器范围 | 起始20级 → 最终150级 | 选项A |
| 飞机杯模式 | 忍耐期低速 → 电击期同步递进到高速 | 选项B |
| 气压阈值 | 静息气压 +20% | 直接说明 |
| 压力传感器 | 灌肠机FFB0自带（AES解密读pressure field） | 用户确认 |
| 电子锁 | BLE接口占位，待绑定 | 选项C |

## 待定项默认值（用户说"开始实现吧"时的自由裁量）

| 待定项 | 默认值 | 理由 |
|-------|-------|------|
| 电击器通道 | 单通道A | 简单起步，可加双通道迭代 |
| 超时未触发 | 5分钟自动退出并解锁 | 不让玩家无限等待 |
| 失压惩罚（电击期） | 倒扣10秒 + 起始强度+20 | 无代价的维持降低了紧张感 |

## Lua 脚本

```lua
-- 玩法：【束缚逃脱 · 递增惩罚】
-- 生成时间：2026-06-10
-- 总时长：约 90 秒 + 玩家等待时间
-- 玩具数：4（飞机杯/电击器/灌肠机/电子锁）
-- 玩法 ID：playbook_20260610_002

-- ============ 阶段①：绑缚上锁 ============
print("[阶段1] 紧紧锁住")
toy.lock_1:lock()
toy.mast_1:rate(5, 5, 5)

local baseline = toy.enema_1:read_pressure()
local threshold = baseline * 1.2
print("[校准] 静息气压=" .. baseline .. " 阈值=" .. threshold)

-- ============ 阶段②：等待玩家夹紧 ============
print("[阶段2] 想要解脱？夹紧肛塞！")
local wait_ticks = 0
local MAX_WAIT_TICKS = 1000  -- 1000 * 300ms ≈ 5分钟超时

while true do
    local p = toy.enema_1:read_pressure()
    if p >= threshold then
        print("[触发] 阈值突破！惩罚开始")
        break
    end
    wait_ticks = wait_ticks + 1
    if wait_ticks >= MAX_WAIT_TICKS then
        print("[超时] 5分钟未触发，自动退出")
        toy.mast_1:stop()
        toy.lock_1:unlock()
        return
    end
    wait(300)
end

-- ============ 阶段③：忍耐期 30秒 ============
print("[阶段3] 忍耐期... 30秒倒计时")
toy.mast_1:rate(8, 8, 6)

local endure_countdown = 30
while endure_countdown > 0 do
    local p = toy.enema_1:read_pressure()
    if p < threshold then
        print("[失守] 气压不足！忍耐暂停")
        repeat
            wait(300)
            p = toy.enema_1:read_pressure()
        until p >= threshold
        print("[恢复] 忍耐继续")
    end
    wait(1000)
    endure_countdown = endure_countdown - 1
end

print("[忍耐] 时间到！")
print("[启动] 电击惩罚开始！")

-- ============ 阶段④：递增惩罚 60秒 ============
print("[阶段4] 惩罚阶段！60秒")

local MIN_SHOCK = 20
local MAX_SHOCK = 150
local total_ticks = 120  -- 120 * 0.5s = 60s
local tick = 0

while tick < total_ticks do
    -- 失守惩罚
    local p = toy.enema_1:read_pressure()
    if p < threshold then
        print("[严厉] 气压失守！惩罚加重！")
        tick = math.max(0, tick - 20)
        MIN_SHOCK = math.min(MAX_SHOCK, MIN_SHOCK + 20)
        toy.ems_1:set_current(MIN_SHOCK, 1)
        repeat
            wait(300)
            p = toy.enema_1:read_pressure()
        until p >= threshold
    end

    local progress = tick / total_ticks
    local shock_level = math.floor(MIN_SHOCK + (MAX_SHOCK - MIN_SHOCK) * progress)
    local waveform = math.min(8, math.floor(1 + progress * 7))
    toy.ems_1:set_current(shock_level, waveform)

    local mast_speed = math.floor(8 + 12 * progress)
    toy.mast_1:rate(mast_speed, mast_speed, mast_speed - 2)

    if tick % 10 == 0 then
        print("[惩罚] 电击=" .. shock_level .. "级 | 波形=" .. waveform)
    end

    wait(500)
    tick = tick + 1
end

-- ============ 阶段⑤：解脱 ============
print("[阶段5] 解脱！恭喜通关")
toy.ems_1:stop()
toy.mast_1:stop()
toy.lock_1:unlock()
print("[结束] 全部关闭，已解锁")
```

## 步骤解读

```
① 开始        全部锁定 + 就位
               🔒 电子锁 上锁
               🌀 飞机杯 低速待机 (5/5/5)
               💧 灌肠器 读取静息气压 → 设定阈值 (+20%)

② 等待        玩家夹紧肛塞触发
               💧 持续监测气压 (300ms轮询)
               气压 < 阈值 → 等待
               气压 ≥ 阈值 → 进入忍耐期
               超时5分钟 → 自动解锁退出

③ 0s - 30s   忍耐期 (30秒)
               🌀 飞机杯 中速 (8/8/6)
               💧 需维持气压 ≥ 阈值，否则暂停计时
               倒计时结束 → 进入惩罚阶段

④ 30s - 90s  递增惩罚 (60秒)
               ⚡ 电击器 20级→150级 + 波形1→8 线性递进
               🌀 飞机杯 同步 8→20 加速
               💧 气压失守 → 倒扣10秒 + 起始强度+20
               每0.5秒更新一次，平滑无级爬升

⑤ 90s        解脱
               🚫 电击器停止 🚫 飞机杯停止
               🔓 电子锁解锁
```
