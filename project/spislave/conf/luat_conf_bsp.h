#ifndef LUAT_CONF_BSP
#define LUAT_CONF_BSP

// 芯片型号 (必须与 partition/AIR6010.csv 一致)
#define AIR6010

// BSP 版本号
#define LUAT_BSP_VERSION "S1001"

//------------------------------------------------------
// 分区内存头 (由 buildx.lua 从 partition/AIR6010.csv 自动生成)
//------------------------------------------------------
#include "partition_mem_AIR6010.h"

//------------------------------------------------------
// 基础外设
//------------------------------------------------------
#define LUAT_USE_UART 1
#define LUAT_USE_GPIO 1
#define LUAT_USE_WDT 1
#define LUAT_USE_PM 1
#define LUAT_USE_MCU 1
#define LUAT_USE_OTP 1
// 不需要: I2C, ADC, PWM, LCDSEG, TOUCHKEY, SDIO
//  => 都未 #define, 代码中 #ifdef 块会被剔除

//------------------------------------------------------
// 网络栈 (airlink 通过 netdrv 挂载 lwip)
//------------------------------------------------------
#define LUAT_USE_NETWORK 1
#define LUAT_USE_NETDRV 1
#define LUAT_USE_LWIP 1
#define LUAT_USE_WLAN 1           // WLAN 功能 (airlink-wlan 命令需要)

//------------------------------------------------------
// airlink 通信通道: SPI slave + UART
//------------------------------------------------------
#define LUAT_USE_AIRLINK 1
#define LUAT_USE_AIRLINK_SPI_SLAVE 1
#define LUAT_USE_SPI_SLAVE 1
#define LUAT_USE_AIRLINK_UART 1
#define LUAT_USE_AIRLINK_GPIO 1
#define LUAT_USE_HMETA 1   // airlink devinfo 需要 hmeta 提供设备元数据

//------------------------------------------------------
// FOTA 升级 (通过 airlink FOTA 命令从 host 接收)
//------------------------------------------------------
#define LUAT_USE_FOTA 1

//------------------------------------------------------
// KV 存储 (FSKV, 用于 airlink 配置持久化)
//------------------------------------------------------
#define LUAT_USE_FS 1
#define LUAT_USE_FS_VFS 1
#define LUAT_USE_FSKV 1
#define LUAT_USE_FSKV_NO_HMAC 1   // air6010 无 PSRAM, 跳过 HMAC 节省空间

//------------------------------------------------------
// 显式禁用的功能 (#undef 守卫, 防止云编译误开)
//------------------------------------------------------
#undef LUAT_USE_NIMBLE
#undef LUAT_USE_I2S
#undef LUAT_USE_MEDIA
#undef LUAT_USE_AUDIO_G711
#undef LUAT_SUPPORT_AMR
#undef LUAT_USE_HTTP
#undef LUAT_USE_FTP
#undef LUAT_USE_MQTT
#undef LUAT_USE_WEBSOCKET
#undef LUAT_USE_SNTP
#undef LUAT_USE_HTTPSRV
#undef LUAT_USE_TLS
#undef LUAT_USE_ERRDUMP
#undef LUAT_USE_ICMP
#undef LUAT_USE_PSRAM
#undef LUAT_USE_NETDRV_NAPT
#undef LUAT_USE_NETDRV_CH390H
#undef LUAT_USE_CJSON
#undef LUAT_USE_CRYPTO
#undef LUAT_USE_PACK
#undef LUAT_USE_ZBUFF
#undef LUAT_USE_FATFS
#undef LUAT_USE_SFUD
#undef LUAT_USE_NR_MICRO_SHELL
#undef LUAT_USE_SHELL
#undef LUAT_USE_REPL
#undef LUAT_USE_OTA
#undef LUAT_CONF_VM_64bit
#undef LUAT_USE_AIRUI
#undef LUAT_USE_PINYIN

//------------------------------------------------------
// 内存优化选项
//------------------------------------------------------
// air6010 无 PSRAM, 所有分配走 SRAM, 尽量少分配
// NOTE: LUAT_HEAP_SRAM is already an enum value in luat_mem.h, do NOT #define it
// 关闭非必要资源
#define LUAT_USE_DNS 1

// 兼容老代码的 KB 宏 (buildx 注入的 partition_mem_*.h 里有)
#define LUAT_FS_SIZE     (LUAT_PARTITION_FS_SIZE / 1024U)
#define LUAT_SCRIPT_SIZE (LUAT_PARTITION_SCRIPT_SIZE / 1024U)

// pin 最大数 (xt804)
#define LUAT_GPIO_PIN_MAX (48)
#define LUAT_CONF_SPI_HALF_DUPLEX_ONLY 1

#define LUAT_RET int
#define LUAT_RT_RET_TYPE void
#define LUAT_RT_CB_PARAM void *param

// Firmware type (与 LuatOS 区分, 自定义 SPI slave 固件)
#define LUAT_CONF_FIRMWARE_TYPE_NUM 6010

#endif
