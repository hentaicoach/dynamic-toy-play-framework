#!/usr/bin/env python3
"""
YOKONEX BLE 玩具 Linux 测试工具

基于 bleak 库，在 Linux 上直接扫描、连接、发送 YOKONEX BLE 协议指令。

用法:
  python3 toy_ble_test.py scan                    # 扫描附近玩具
  python3 toy_ble_test.py test <mac> <type>       # 连接并运行功能测试
    type: vibrator | ems_v1 | ems_v2 | enema | lock
  
  示例:
  python3 toy_ble_test.py scan                    # 扫描附近玩具（无声音）
  python3 toy_ble_test.py query <mac>            # 🔇 静默查灌肠机气压/电量
  python3 toy_ble_test.py test <mac> vibrator    # 测试飞机杯（会震动！）
"""

import asyncio
import struct
import sys
from bleak import BleakScanner, BleakClient
from bleak.backends.characteristic import BleakGATTCharacteristic

# ═══════════════════════════════════════════
# 常量
# ═══════════════════════════════════════════

# YOKONEX BLE Service UUIDs
SERVICE_VIBRATOR = "0000ff40-0000-1000-8000-00805f9b34fb"
SERVICE_EMS      = "0000ff30-0000-1000-8000-00805f9b34fb"
SERVICE_ENEMA    = "0000ffb0-0000-1000-8000-00805f9b34fb"

SERVICE_NAMES = {
    SERVICE_VIBRATOR: "飞机杯/跳蛋 (FF40)",
    SERVICE_EMS:      "电击器 (FF30)",
    SERVICE_ENEMA:    "灌肠机 (FFB0)",
}

# Characteristic UUIDs
CHAR_VIBRATOR_WRITE  = "0000ff41-0000-1000-8000-00805f9b34fb"
CHAR_VIBRATOR_NOTIFY = "0000ff42-0000-1000-8000-00805f9b34fb"
CHAR_EMS_WRITE       = "0000ff31-0000-1000-8000-00805f9b34fb"
CHAR_EMS_NOTIFY      = "0000ff32-0000-1000-8000-00805f9b34fb"
CHAR_ENEMA_WRITE     = "0000ffb1-0000-1000-8000-00805f9b34fb"
CHAR_ENEMA_NOTIFY    = "0000ffb2-0000-1000-8000-00805f9b34fb"

# AES密钥（灌肠机）
AES_KEY = bytes([
    0xF6, 0x38, 0xBC, 0x9C, 0xFA, 0x47, 0x74, 0x80,
    0xAB, 0x32, 0x42, 0xF6, 0xB0, 0x45, 0x57, 0xA1,
])


# ═══════════════════════════════════════════
# 校验和
# ═══════════════════════════════════════════

def checksum(data: bytes) -> int:
    return sum(data) & 0xFF


# ═══════════════════════════════════════════
# 扫描
# ═══════════════════════════════════════════

def _detection_callback(device, advertisement_data):
    """扫描过滤：只显示 YOKONEX 玩具"""
    uuids = advertisement_data.service_uuids
    matched = [SERVICE_NAMES[u] for u in uuids if u in SERVICE_NAMES]
    if matched:
        rssi = advertisement_data.rssi if hasattr(advertisement_data, 'rssi') else 0
        bars = "█" * max(1, min(4, (rssi + 80) // 10))
        name = device.name or "?"
        print(f"  {bars} {device.address}  {name:20s}  {'/'.join(matched):20s}  {rssi:4d} dBm")


async def scan():
    print("🔍 扫描 YOKONEX BLE 设备... (按 Ctrl+C 停止)")
    print(f"{'':─<65}")
    scanner = BleakScanner(detection_callback=_detection_callback)
    await scanner.start()
    try:
        await asyncio.sleep(10)
    except asyncio.CancelledError:
        pass
    finally:
        await scanner.stop()


# ═══════════════════════════════════════════
# FF40 飞机杯/跳蛋
# ═══════════════════════════════════════════

async def test_vibrator(client: BleakClient, write_char: BleakGATTCharacteristic):
    print("\n🧪 测试飞机杯/跳蛋 (FF40)")

    def build_packet(cmd: int, *data: int) -> bytes:
        pkt = bytes([0x35, cmd, *data])
        pkt += bytes([checksum(pkt)])
        return pkt

    # 0x10 查询设备信息
    print("  [0x10] 查询设备信息...")
    await client.write_gatt_char(write_char, build_packet(0x10))
    await asyncio.sleep(0.5)

    # 0x11 固定模式 — A马达模式1
    print("  [0x11] 设置 A马达 模式1...")
    await client.write_gatt_char(write_char, build_packet(0x11, 0x01, 0x01))
    await asyncio.sleep(1)

    # 0x12 速率控制 — 逐渐加速
    for speed in [0, 5, 10, 15, 20, 10, 5, 0]:
        print(f"  [0x12] 速率: motorA={speed}, motorB=0, motorC=0")
        await client.write_gatt_char(write_char, build_packet(0x12, speed, 0, 0))
        await asyncio.sleep(0.5)

    print("  ✅ 飞机杯测试完成")


# ═══════════════════════════════════════════
# FF30 电击器 V1
# ═══════════════════════════════════════════

async def test_ems_v1(client: BleakClient, write_char: BleakGATTCharacteristic):
    print("\n🧪 测试电击器一代 (FF30 V1)")

    def build_packet(*data: int) -> bytes:
        pkt = bytes([0x35, *data])
        pkt += bytes([checksum(pkt)])
        return pkt

    # 0x11 通道控制（10字节）
    # 格式: 0x35, 0x11, channel, on_off, intensityH, intensityL, mode, freq, pw, checksum
    print("  [0x11] A通道 模式3 强度50...")
    await client.write_gatt_char(write_char, build_packet(0x11, 0x01, 0x01, 0x00, 0x32, 0x03, 0x00, 0x00))
    await asyncio.sleep(2)

    print("  [0x11] A通道 实时模式 强度120 50Hz 50us...")
    await client.write_gatt_char(write_char, build_packet(0x11, 0x01, 0x01, 0x00, 0x78, 0x11, 0x32, 0x32))
    await asyncio.sleep(2)

    print("  [0x11] 关闭A通道...")
    await client.write_gatt_char(write_char, build_packet(0x11, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))

    print("  ✅ 电击器一代测试完成")


# ═══════════════════════════════════════════
# FF30 电击器 V2
# ═══════════════════════════════════════════

async def test_ems_v2(client: BleakClient, write_char: BleakGATTCharacteristic):
    print("\n🧪 测试电击器二代 (FF30 V2)")

    def build_packet(*data: int) -> bytes:
        pkt = bytes([0x35, *data])
        pkt += bytes([checksum(pkt)])
        return pkt

    # 固定模式 (0x01): 10字节
    print("  [0x11/0x01] 固定模式 A=50模式3 B=80模式5...")
    await client.write_gatt_char(write_char, build_packet(0x11, 0x01, 0x00, 0x32, 0x03, 0x00, 0x50, 0x05))
    await asyncio.sleep(2)

    # 实时模式 (0x02): 12字节
    print("  [0x11/0x02] 实时模式 A=100 40Hz 60us B=150 60Hz 40us...")
    await client.write_gatt_char(write_char, build_packet(0x11, 0x02, 0x00, 0x64, 0x28, 0x3C, 0x00, 0x96, 0x3C, 0x28))
    await asyncio.sleep(2)

    # 停止
    print("  [0x11/0x01] 停止所有...")
    await client.write_gatt_char(write_char, build_packet(0x11, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))

    # 马达测试
    print("  [0x12] 马达开启...")
    await client.write_gatt_char(write_char, build_packet(0x12, 0x01))
    await asyncio.sleep(1)
    print("  [0x12] 马达关闭...")
    await client.write_gatt_char(write_char, build_packet(0x12, 0x00))

    print("  ✅ 电击器二代测试完成")


# ═══════════════════════════════════════════
# FFB0 灌肠机（AES加密）
# ═══════════════════════════════════════════

async def query_pressure(client: BleakClient, write_char: BleakGATTCharacteristic,
                        notify_char: BleakGATTCharacteristic | None):
    """
    纯静默模式：只连接、只读压力，不触发任何马达/泵/震动 ⚠️ 无声！
    """
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

    print("\n🔇 静默查询模式 — 只读气压，不触发任何动作")

    def encrypt(plain: bytes) -> bytes:
        cipher = Cipher(algorithms.AES(AES_KEY), modes.ECB())
        encryptor = cipher.encryptor()
        return encryptor.update(plain) + encryptor.finalize()

    def decrypt(cipher_bytes: bytes) -> bytes:
        cipher = Cipher(algorithms.AES(AES_KEY), modes.ECB())
        decryptor = cipher.decryptor()
        return decryptor.update(cipher_bytes) + decryptor.finalize()

    def build_enema_packet(cmd: int) -> bytes:
        pkt = bytearray(16)
        pkt[0] = 0xBF; pkt[1] = 0x0F; pkt[2] = 0xA0; pkt[3] = cmd
        for i in range(4, 16):
            pkt[i] = __import__('os').urandom(1)[0]
        return encrypt(bytes(pkt))

    notify_queue: asyncio.Queue[bytes] = asyncio.Queue()
    def notify_handler(sender, data: bytearray):
        notify_queue.put_nowait(bytes(data))

    if notify_char:
        await client.start_notify(notify_char, notify_handler)

    # 查询状态（静默，只会读不会动）
    print("  [0x04] 查询工作状态...")
    await client.write_gatt_char(write_char, build_enema_packet(0x04))

    # 查询电量
    print("  [0x05] 获取电量...")
    await client.write_gatt_char(write_char, build_enema_packet(0x05))

    # 等通知
    await asyncio.sleep(2)
    try:
        got_pressure = False
        got_battery = False
        while True:
            data = await asyncio.wait_for(notify_queue.get(), timeout=2)
            # 设备每200ms自动上报压力，只收16字节的AES密文
            if len(data) != 16:
                continue
            try:
                plain = decrypt(data)
                if len(plain) >= 4 and plain[0] == 0xBF and plain[1] == 0x0F and plain[2] == 0xB0:
                    resp = plain[3]
                    if resp == 0x01:
                        pstat = ["停止", "正转", "反转"][plain[4]] if plain[4] < 3 else f"未知"
                        sstat = ["停止", "正转"][plain[5]] if plain[5] < 2 else f"未知"
                        print(f"  📋 泵状态: 蠕动泵={pstat} 抽水泵={sstat}")
                        got_pressure = True
                    elif resp == 0x02:
                        pa = (plain[4] << 8) | plain[5]
                        pb = (plain[6] << 8) | plain[7]
                        print(f"  📊 压力值: A={pa}  B={pb}")
                    elif resp == 0x03:
                        print(f"  🔋 电量: {plain[4]}%")
                        got_battery = True
                    # 拿齐了就提前退出
                    if got_pressure and got_battery:
                        break
            except Exception:
                pass  # 非AES数据静默跳过
    except asyncio.TimeoutError:
        pass

    if notify_char:
        await client.stop_notify(notify_char)
    print("  ✅ 查询完成（未触发任何物理动作）")


async def query_pressure_enema(mac: str):
    """只连接灌肠机读气压，不出声"""
    print(f"\n🔗 连接 {mac} (灌肠机 FFB0)...")
    async with BleakClient(mac, timeout=20) as client:
        print(f"  ✅ 已连接 MTU={client.mtu_size}")
        for svc in client.services:
            if svc.uuid.lower() == SERVICE_ENEMA.lower():
                write_char = notify_char = None
                for char in svc.characteristics:
                    if char.uuid.lower() == CHAR_ENEMA_WRITE.lower():
                        write_char = char
                    if char.uuid.lower() == CHAR_ENEMA_NOTIFY.lower():
                        notify_char = char
                if write_char:
                    await query_pressure(client, write_char, notify_char)
                break
    print(f"\n🔌 已断开 {mac}")


# ═══════════════════════════════════════════
# 电子锁（基于 FF40 模拟）
# ═══════════════════════════════════════════

async def test_lock(client: BleakClient, write_char: BleakGATTCharacteristic):
    print("\n🧪 测试电子锁 (基于 FF40 协议)")

    def build_packet(cmd: int, *data: int) -> bytes:
        pkt = bytes([0x35, cmd, *data])
        pkt += bytes([checksum(pkt)])
        return pkt

    print("  [0x12] 上锁 (A马达中速)...")
    await client.write_gatt_char(write_char, build_packet(0x12, 10, 0, 0))
    await asyncio.sleep(2)
    await client.write_gatt_char(write_char, build_packet(0x12, 0, 0, 0))

    print("  [0x12] 解锁 (B马达中速)...")
    await client.write_gatt_char(write_char, build_packet(0x12, 0, 10, 0))
    await asyncio.sleep(2)
    await client.write_gatt_char(write_char, build_packet(0x12, 0, 0, 0))

    print("  ✅ 电子锁测试完成")


# ═══════════════════════════════════════════
# 通用连接测试
# ═══════════════════════════════════════════

SERVICE_CHAR_MAP = {
    SERVICE_VIBRATOR: (CHAR_VIBRATOR_WRITE, CHAR_VIBRATOR_NOTIFY),
    SERVICE_EMS:      (CHAR_EMS_WRITE, CHAR_EMS_NOTIFY),
    SERVICE_ENEMA:    (CHAR_ENEMA_WRITE, CHAR_ENEMA_NOTIFY),
}


async def run_test(mac: str, toy_type: str):
    # 查找匹配的服务
    service_uuid = None
    for svc, name in SERVICE_NAMES.items():
        if toy_type in name.lower() or toy_type == {
            "vibrator": SERVICE_VIBRATOR, "ems_v1": SERVICE_EMS,
            "ems_v2": SERVICE_EMS, "enema": SERVICE_ENEMA, "lock": SERVICE_VIBRATOR,
        }.get(toy_type, ""):
            service_uuid = svc
            break

    if not service_uuid:
        print(f"❌ 未知玩具类型: {toy_type}")
        sys.exit(1)

    write_uuid, notify_uuid = SERVICE_CHAR_MAP[service_uuid]

    print(f"\n🔗 连接 {mac} ({SERVICE_NAMES.get(service_uuid, toy_type)})...")
    async with BleakClient(mac, timeout=20) as client:
        print(f"  ✅ 已连接: MTU={client.mtu_size}")

        # 发现服务
        for svc in client.services:
            if svc.uuid.lower() == service_uuid.lower():
                write_char = None
                notify_char = None
                for char in svc.characteristics:
                    if char.uuid.lower() == write_uuid.lower():
                        write_char = char
                    if char.uuid.lower() == notify_uuid.lower():
                        notify_char = char

                if write_char is None:
                    print(f"  ❌ 未找到写特征值 {write_uuid}")
                    continue

                # 运行测试（enema 测试已废弃，用 query 代替）
                if toy_type == "enema":
                    print("  ⚠ enema 功能测试会发声，已停用。请用 `query` 命令静默查气压")
                elif toy_type in ("vibrator", "ems_v1", "ems_v2", "lock"):
                    test_fn = {"vibrator": test_vibrator, "ems_v1": test_ems_v1,
                               "ems_v2": test_ems_v2, "lock": test_lock}[toy_type]
                    await test_fn(client, write_char)
                else:
                    print(f"  ⚠ 未知类型: {toy_type}")

                break

    print(f"\n🔌 已断开 {mac}")


# ═══════════════════════════════════════════
# 入口
# ═══════════════════════════════════════════

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        return

    cmd = sys.argv[1]

    if cmd == "scan":
        asyncio.run(scan())
    elif cmd == "test":
        if len(sys.argv) < 4:
            print("用法: python3 toy_ble_test.py test <MAC地址> <类型>")
            print("类型: vibrator | ems_v1 | ems_v2 | lock")
            return
        mac = sys.argv[2]
        toy_type = sys.argv[3]
        asyncio.run(run_test(mac, toy_type))
    elif cmd == "query":
        if len(sys.argv) < 3:
            print("用法: python3 toy_ble_test.py query <MAC地址>")
            print("🔇 静默模式：只连接灌肠机读取气压/电量，不触发任何物理动作")
            return
        mac = sys.argv[2]
        asyncio.run(query_pressure_enema(mac))
    else:
        print(f"未知命令: {cmd}")
        print(__doc__)


if __name__ == "__main__":
    main()
