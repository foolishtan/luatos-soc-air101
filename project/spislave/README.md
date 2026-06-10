# project/spislave — AIR6010 SPI Slave 固件

## 角色

作为 airlink SPI slave 协处理器,通过 xt804 高速 SPI(HSPI)与 host(air6208)通讯。

- **物理层**: HSPI(xt804 内置高速 SPI/SDIO 控制器)
- **协议层**: airlink(`../LuatOS/components/airlink/`)
- **网络层**: netdrv + lwip(airlink 通过 ulwip 挂载)

## 编译

### 方式 1: 独立编译(推荐用于迭代)

```bash
cd project/spislave
xmake f -P .
xmake
xmake build air6010_spislave
```

产物:
- `build/out/AIR6010.elf`
- `build/out/AIR6010.bin`
- `build/out/AIR6010.fls` (烧录文件 = secboot + app)

### 方式 2: 根项目下多 target 编译

在根 `xmake.lua` 末尾加 `includes("project/spislave", {inherit=false})` 后:

```bash
cd <repo-root>
xmake f -y           # 配置
xmake build air10x              # 编译 air6208
xmake build air6010_spislave    # 编译 air6010
```

### 说明: buildx.lua 为什么拷贝一份?

`buildx.lua` 是公共模块,根 `xmake.lua` 已经在用 `import "buildx"`。
spislave 拷贝一份是为了让 `import "buildx"` 在 standalone 模式下也能找到模块
(xmake 不会从父目录查找模块)。两份内容**完全相同**,只维护一份时,记得
`cp ../buildx.lua buildx.lua` 同步过来即可。

## BSP 配置

`conf/luat_conf_bsp.h` 是该子项目的 BSP 宏入口。

- `#define AIR6010` 触发 `buildx.lua` 加载 `partition/AIR6010.csv`
- 显式 `#undef` 大量不需要的协议库,防止 cloud-build 误开
- 启用:`LUAT_USE_AIRLINK` / `LUAT_USE_AIRLINK_SPI_SLAVE` / `LUAT_USE_SPI_SLAVE` / `LUAT_USE_FOTA` / `LUAT_USE_NETDRV` / `LUAT_USE_FSKV`

`xmake.lua` 中把 `project/spislave/conf` 加到 include 路径前面,
使共享 BSP 代码 `#include "luat_conf_bsp.h"` 优先解析到本目录的版本,
与 `app/port/luat_conf_bsp.h`(air6208 用)互不干扰。

## 链接脚本

`ld/xt804.ld` 是通用模板,本项目在 `on_load` 时动态替换为 `ld/air6010.ld`:

| 占位符 | 替换值 | 来源 |
|---|---|---|
| `SRAM_O` | `0x080D0400` | `partition_mem_AIR6010.h` 的 `app` 偏移 + 0x400 (1K header) |
| `SRAM_L` | `0x110000`   | app 分区大小 - 1K = 1088K - 1K = 1087K (向上对齐) |
| `RAM_END` | `0x2002A400` | 固定,把 SLAVE_HSPI 0x2400 buffer 完整包入 `__ram_end` 之外 |
| `__min_heap_size` | `0x4000` | 16K, 避免无 PSRAM 时碎片 |

## 入口

`main.c::UserMain()` 流程:

1. RTC 初始化(沿用 `app/main.c:140-151`)
2. Flash id/size 读取
3. `luat_heap_init()`
4. `luat_fota_boot_check()` (必须在 airlink 之前)
5. `luat_netdrv_register_xt804()` (lwip 适配)
6. 配置 `g_airlink_spi_conf` (HSPI id=2, master=0, speed=60MHz)
7. `luat_airlink_init()`
8. `luat_airlink_start(LUAT_AIRLINK_MODE_SPI_SLAVE)` (id=0)

## 烧录

```bash
# 烧录到 air6010 板
./soc_tools/air101_flash.exe -p COMx -b 115200 -r build/out/AIR6010.fls
```

UART0 默认 115200 8N1,日志前缀 `[spislave]`。

## 升级流程

1. air6208 host 通过 airlink FOTA 命令(0x04-0x07)推送新固件
2. air6010 接收数据,`luat_fota_write` 写入本地 fota 分区
3. `luat_fota_done` 写 OTA flag,触发软重启
4. secboot 检测 OTA flag,从 fota 区启动新固件
