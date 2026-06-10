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
#include "luat_uart.h"

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

// YHM27xx GPIO driver stub (AIR6010 无此芯片)
int luat_gpio_driver_yhm27xx(uint32_t pin, uint8_t chip_id, uint8_t reg, uint8_t is_read, uint8_t *data) {
    (void)pin; (void)chip_id; (void)reg; (void)is_read; (void)data;
    return -1;
}

// PM IO 电压控制 stub (AIR6010 不支持, airlink spi slave 需要此符号)
int luat_pm_iovolt_ctrl(int id, int val) {
    (void)id; (void)val;
    return 0;
}

// GPIO mode stub (AIR6010 不需要, luat_uart_setup 调用)
void luat_gpio_mode(int pin, int mode, int pull, int initOutput) {
    (void)pin; (void)mode; (void)pull; (void)initOutput;
}

// === LWIP adapter stubs (spislave 走 airlink, 不需要标准 lwip socket/dhcp/dns) ===
struct netif;  // forward decl
void net_lwip2_set_link_state(uint8_t adapter_index, uint8_t updown) {
    (void)adapter_index; (void)updown;
}
void net_lwip2_register_adapter(uint8_t adapter_index) {
    (void)adapter_index;
}
void net_lwip2_set_netif(uint8_t adapter_index, struct netif *netif) {
    (void)adapter_index; (void)netif;
}
// === ULWIP stubs ===
void ulwip_dhcp_client_start(ulwip_ctx_t *ctx) {
    (void)ctx;
}
void ulwip_dhcp_client_stop(ulwip_ctx_t *ctx) {
    (void)ctx;
}

// UART ctrl stub (airlink uart task 需要)
int luat_uart_ctrl(int uart_id, LUAT_UART_CTRL_CMD_E cmd, void* param) {
    (void)uart_id; (void)cmd; (void)param;
    return 0;
}

void UserMain(void) {
    LLOGI("=== AIR6010 spislave boot ===");

    LLOGD("[1/7] tick64_init...");
    luat_mcu_tick64_init();
    LLOGD("[1/7] tick64_init done");

    LLOGD("[2/7] fs_update_addr...");
    luat_fs_update_addr();
    LLOGD("[2/7] fs_update_addr done: kv=0x%x/%dK", kv_addr, kv_size_kb);

    LLOGD("[3/7] heap_init...");
    luat_heap_init();
    LLOGD("[3/7] heap_init done");

    // WLAN init crashes; skip for now, verify airlink basics first
    // TODO: debug luat_wlan_init, call it lazily via airlink exec wlan
    LLOGD("[4/7] wlan_init SKIPPED (crash, debug later)");

    LLOGD("[5/7] netdrv_register SKIPPED");

    LLOGD("[6/7] airlink_init...");
    int ret = luat_airlink_init();
    LLOGD("[6/7] airlink_init ret=%d", ret);
    if (ret != 0) {
        LLOGE("airlink init failed");
    }

    g_airlink_spi_conf.spi_id = HSPI_INTERFACE_SPI;
    g_airlink_spi_conf.master = 0;
    g_airlink_spi_conf.speed = 60000000;
    LLOGD("[7/7] airlink_start SPI slave (id=%d cs=%d rdy=%d)...",
          g_airlink_spi_conf.spi_id, g_airlink_spi_conf.cs_pin, g_airlink_spi_conf.rdy_pin);
    ret = luat_airlink_start(LUAT_AIRLINK_MODE_SPI_SLAVE);
    LLOGD("[7/7] airlink_start SPI slave ret=%d", ret);

#ifdef LUAT_USE_AIRLINK_UART
    LLOGD("[+UART] airlink_start UART...");
    ret = luat_airlink_start(LUAT_AIRLINK_MODE_UART);
    LLOGD("[+UART] airlink_start UART ret=%d", ret);
    LLOGD("[+TASK] airlink_task_start...");
    luat_airlink_task_start();
    LLOGD("[+TASK] airlink_task_start done");
#endif

    LLOGI("=== boot done, entering idle ===");

    while (1) {
        vTaskDelay(10000 / portTICK_PERIOD_MS);
    }
}
