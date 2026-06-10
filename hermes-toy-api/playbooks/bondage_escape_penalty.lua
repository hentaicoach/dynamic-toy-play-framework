-- 玩法：【束缚逃脱 · 递增惩罚】
-- 生成时间：2026-06-10
-- 总时长：约 90 秒 + 玩家等待时间
-- 玩具数：4（飞机杯/电击器/灌肠机/电子锁）
-- 玩法 ID：playbook_20260610_002
--
-- 配器：
--   mast_1 — 飞机杯 (FF40, 3马达 0-20)
--   ems_1  — 电击器 (FF30, 2通道 276级 + 16模式 + 频率/脉宽)
--   enema_1 — 灌肠机 (FFB0, AES-128-ECB, read_pressure)
--   lock_1 — 电子锁 (BLE, 接口占位)

-- ============ 阶段①：绑缚上锁 ============
print("[阶段1] 紧紧锁住")

-- 锁死
toy.lock_1:lock()

-- 飞机杯就位：低速待机（马达1=5, 马达2=5, 马达3=5）
toy.mast_1:rate(5, 5, 5)

-- 读取静息气压，设定阈值（+20%）
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

    -- 超时检查
    wait_ticks = wait_ticks + 1
    if wait_ticks >= MAX_WAIT_TICKS then
        print("[超时] 5分钟未触发，自动退出")
        toy.mast_1:stop()
        toy.lock_1:unlock()
        print("[结束] 已解锁，下次加油")
        return
    end

    wait(300)  -- 每300ms检测一次
end

-- ============ 阶段③：忍耐期 30秒 ============
print("[阶段3] 忍耐期开始... 30秒倒计时")
toy.mast_1:rate(8, 8, 6)  -- 低速运转

-- 30秒忍耐计时（失守暂停，恢复继续）
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
    if endure_countdown > 0 then
        print("[忍耐] 剩余 " .. endure_countdown .. " 秒")
    end
end

print("[忍耐] 时间到！")
print("[启动] 电击惩罚开始！")

-- ============ 阶段④：递增电击 + 飞机杯加速 60秒 ============
print("[阶段4] 惩罚阶段！总时长60秒")

-- 电击器参数（276级制）
local MIN_SHOCK = 20    -- 起始强度
local MAX_SHOCK = 150   -- 最终强度
local SHOCK_WAVEFORM = 1  -- 波形1（轻柔→逐渐变为波形8）

-- 飞机杯参数（马达 0-20）
local MAST_LOW = 8
local MAST_HIGH = 20

-- 60秒递增：每0.5秒更新一次，平滑爬升
local total_ticks = 120  -- 120 * 0.5s = 60s
local tick = 0
local penalty_remaining = 60

while tick < total_ticks do
    -- 气压检查：失守惩罚
    local p = toy.enema_1:read_pressure()
    if p < threshold then
        print("[严厉惩罚] 气压失守！惩罚加重！")
        -- 惩罚：增加10秒+起始强度+20
        tick = math.max(0, tick - 20)     -- 倒扣10秒
        MIN_SHOCK = math.min(MAX_SHOCK, MIN_SHOCK + 20)
        toy.ems_1:set_current(MIN_SHOCK, SHOCK_WAVEFORM)
        print("[加重] 起始强度提升至" .. MIN_SHOCK .. "，延长时间10秒")

        -- 等待恢复
        repeat
            wait(300)
            p = toy.enema_1:read_pressure()
        until p >= threshold
        print("[恢复] 气压回归，惩罚继续")
    end

    -- 计算当前进度百分比
    local progress = tick / total_ticks  -- 0.0 ~ 1.0

    -- 电击强度线性递增
    local shock_level = MIN_SHOCK + (MAX_SHOCK - MIN_SHOCK) * progress
    shock_level = math.floor(shock_level)
    -- 波形逐步激进
    local waveform = math.floor(1 + progress * 7)  -- 1→8
    if waveform > 8 then waveform = 8 end
    toy.ems_1:set_current(shock_level, waveform)

    -- 飞机杯同步递增
    local mast_speed = MAST_LOW + (MAST_HIGH - MAST_LOW) * progress
    mast_speed = math.floor(mast_speed)
    toy.mast_1:rate(mast_speed, mast_speed, mast_speed - 2)

    -- 每5秒输出状态
    if tick % 10 == 0 then
        print("[惩罚] 剩余 " .. penalty_remaining .. "秒 | 电击=" .. shock_level .. "级 | 波形=" .. waveform .. " | 飞机杯=" .. mast_speed)
    end

    wait(500)
    tick = tick + 1
    penalty_remaining = math.ceil((total_ticks - tick) / 2)
end

-- ============ 阶段⑤：解脱 ============
print("[阶段5] 惩罚结束，恭喜通关！")

toy.ems_1:stop()
toy.mast_1:stop()
toy.lock_1:unlock()

print("[结束] 全部玩具关闭，电子锁已解锁")
