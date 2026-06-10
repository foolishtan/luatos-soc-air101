/*
 * AIR6010 SPI Slave 入口
 * 作为 airlink SPI slave 协处理器, 通过 HSPI 与 host(air6208)通讯
 * 编译配置: project/spislave/xmake.lua
 */

#include "wm_include.h"

#include "luat_base.h"
#include "luat_log.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_fota.h"
#include "luat_airlink.h"
#include "luat_netdrv.h"

#include "FreeRTOS.h"
#include "task.h"

#define LUAT_LOG_TAG "spislave"
#include "luat_log.h"

extern void luat_mcu_tick64_init(void);
extern void luat_heap_init(void);
extern int luat_netdrv_register_xt804(void);

// 分区地址变量 (原在 luat_fs_air101.c, spislave 无 script/fs 分区, 仅设 KV)
uint32_t kv_addr = 0;
uint32_t kv_size_kb = 0;
uint32_t luadb_addr = 0;
uint32_t luadb_size_kb = 0;
uint32_t lfs_addr = 0;
uint32_t lfs_size_kb = 0;

// 自定义 luat_fs_update_addr: 仅挂载 KV 分区 (spislave 无 script/fs)
void luat_fs_update_addr(void) {
    kv_addr = LUAT_PARTITION_KV_ADDR;
    kv_size_kb = LUAT_PARTITION_KV_SIZE / 1024U;
    // script/fs 分区不存在, 保持为 0, 不挂载
}

// airlink SPI 配置 (g_airlink_spi_conf 来自 luat_airlink.c, 这里只覆盖需要的字段)
// HSPI_INTERFACE_SPI = 2 (来自 wm_hspi.h)
#ifndef HSPI_INTERFACE_SPI
#define HSPI_INTERFACE_SPI 2
#endif

// GPIO IRQ 默认回调 stub (spislave 无 lua vm, 不需要 lua dispatch)
int luat_gpio_irq_default(int pin, void* args) {
    return 0;
}

void UserMain(void) {
    LLOGD("AIR6010 UserMain start");

    // 1. tick64 (供 luat_mcu_tick64_ms 使用)
    luat_mcu_tick64_init();

    // 2. 更新文件系统地址 (即使无 script 区, 也要让 KV 等分区地址生效)
    luat_fs_update_addr();

    // 3. 堆初始化 (LuatOS 内存管理)
    luat_heap_init();

    // 4. 注册 netdrv (xt804 lwip 适配, airlink 通过 ulwip 挂载)
    luat_netdrv_register_xt804();

    // 5. 配置 airlink SPI (xt804 HSPI 从机模式)
    //    默认引脚 (cs=8, rdy=22, irq=255) 由 luat_airlink_spi_slave_task.c:144-163 内部补全
    g_airlink_spi_conf.spi_id = HSPI_INTERFACE_SPI;  // 2
    g_airlink_spi_conf.master = 0;                    // 0 = 从机
    g_airlink_spi_conf.speed = 60000000;              // 60MHz, 与 BSP 默认一致
    LLOGI("airlink spi conf: id=%d master=%d speed=%d cs=%d rdy=%d irq=%d",
          g_airlink_spi_conf.spi_id, g_airlink_spi_conf.master, g_airlink_spi_conf.speed,
          g_airlink_spi_conf.cs_pin, g_airlink_spi_conf.rdy_pin, g_airlink_spi_conf.irq_pin);

    // 6. 初始化 airlink 协议栈
    if (luat_airlink_init() != 0) {
        LLOGE("airlink init failed");
    }

    // 7. 启动 SPI slave 模式 (id=0 = LUAT_AIRLINK_MODE_SPI_SLAVE)
    //     内部会创建 spi_slave_task 并启动 HSPI 控制器
    if (luat_airlink_start(LUAT_AIRLINK_MODE_SPI_SLAVE) != 0) {
        LLOGE("airlink start SPI slave failed");
    }

    // 8. 启动 UART 模式 (id=2 = LUAT_AIRLINK_MODE_UART)
    //     用于 host 通过串口与 spislave 通讯
    #ifdef LUAT_USE_AIRLINK_UART
    if (luat_airlink_start(LUAT_AIRLINK_MODE_UART) != 0) {
        LLOGE("airlink start UART failed");
    }
    #endif

    LLOGI("AIR6010 UserMain done, entering idle");

    // 9. 主任务阻塞
    while (1) {
        vTaskDelay(10000 / portTICK_PERIOD_MS);
    }
}
