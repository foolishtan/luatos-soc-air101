/**
 * @file    lwipopts_override.h
 *
 * @brief   air101 lwIP 2.2 lwipopts 覆盖层
 *
 * 设计说明（来自 plan §2、§3.2）：
 *   - 以 LuatOS/components/network/lwip22/port/luat_rtos/lwipopts.h 为基线
 *     （NO_SYS=1、LWIP_IPV6=1 已默认开启）。
 *   - 本文件只覆盖 air101 资源约束的少量宏，**不**整段重新定义 lwipopts。
 *   - 工作方式：本文件作为 lwipopts.h 的入口（由 xmake 把 src/network/
 *     lwip22_port 加在 lwip22 include 目录之前），先把本文件的覆盖宏定义
 *     好，再用相对路径显式 #include LuatOS 基线 lwipopts；基线里用
 *     #ifndef 保护的宏（MEM_SIZE、TCP_* 等）会跳过基线默认值，命中前面
 *     的定义。基线里**裸** #define 的宏（LWIP_NETIF_STATUS_CALLBACK、
 *     LWIP_NETIF_HOSTNAME 等）在基线加载完后用 #undef + #define 重新写
 *     一次，确保 vendor 语义保持。
 *
 * 用法（xmake.lua 端，由 subagent D 配置）：
 *     add_includedirs(".../LuatOS/components/network/lwip22/include")
 *     add_includedirs(".../LuatOS/components/network/lwip22/port/luat_rtos")
 *     -- 必须在 lwip22 include 之前
 *     add_includedirs("src/network/lwip22_port")
 *
 * 若以后 air101 与 LuatOS 仓库相对位置变更，本文件末尾的相对路径需同步
 * 调整；也可改用绝对路径但会牺牲可移植性。
 */

#ifndef LWIPOPTS_OVERRIDE_H
#define LWIPOPTS_OVERRIDE_H

/* =========================================================================
 * 0) 类型兼容：vendor wm_type_def.h 已经 typedef u8_t/u16_t/u32_t/s8_t，
 *    用 #ifdef + #undef + typedef 写法，会在 lwip22 自己的 typedef 之后
 *    跑一次 redefine。lwip22 用 stdint.h 的 uint8_t/int8_t 等，与 csky 平
 *    台上 vendor 的 unsigned char/short/int 一致，不会冲突。
 *
 *    旧 lwip2.1.3 时代用 LWIP_NO_INTTYPES_H=1 跳过 lwip 自己的 typedef，
 *    lwip22 把这个旗标改名为 LWIP_NO_STDINT_H。本仓库改用让 lwip22 先
 *    typedef，vendor 再覆盖（#undef + typedef）的策略。
 * ======================================================================= */
/* 不再强制 LWIP_NO_STDINT_H=1，让 lwip22 用 stdint.h 自己 typedef */

/* =========================================================================
 * 1) 资源约束：TCP 缓冲
 * -------------------------------------------------------------------------
 * air101 XT804 RAM 约 96 KB，跑 lwip22 默认的 32*TCP_MSS（≈42 KB）会 OOM。
 * 参考旧 lwip2.1.3 lwipopts 取 15*TCP_MSS 的折中规模。
 *
 * lwip22 基线 lwipopts.h 用 #ifndef TCP_SND_BUF 保护，所以下面的定义会优
 * 先于 lwip22 的 (32 * TCP_MSS) 生效。
 * ======================================================================= */
#ifndef TCP_SND_BUF
#define TCP_SND_BUF                      (15 * TCP_MSS)
#endif

/* TCP_WND 在 lwip22 默认里是 soc_tcpip_rx_cache() 函数指针；air101 没有该
 * 符号，因此改成编译期常量，避免 undefined reference。8*TCP_MSS 是
 * lwip2.1.3 时代取值，与 lwip22 默认的 receive-window 经验值一致。 */
#ifndef TCP_WND
#define TCP_WND                          (8 * TCP_MSS)
#endif

/* =========================================================================
 * 2) 把 lwip22 基线 lwipopts 拉进来：
 *
 *   相对路径基于 air101 与 LuatOS 是 D:\github\ 的同级子目录这一前提
 *   （xmake.lua 里有 local luatos = "../LuatOS/"）。
 *   从 src/network/lwip22_port/lwipopts_override.h 出发需要上溯 4 层到
 *   D:\github\，再进入 LuatOS/。
 *
 *   如果实际工程目录布局有变，请同步修改下面这条 include，或改为绝对路径。
 * ======================================================================= */
#include "../../../../LuatOS/components/network/lwip22/port/luat_rtos/lwipopts.h"

/* =========================================================================
 * 3) 自定义 src-based 路由 hook：vendor 的 wm_ethernet.c 提供 wm_ip4_route_src。
 *    lwip22 内部仍保留 LWIP_HOOK_IP4_ROUTE_SRC 宏（见 core/ip4/ip4.c 与
 *    include/lwip/opt.h 注释），这里打开即可。本头文件被 lwip22 源码引
 *    用时 LWIP_NO_STDINT_H 已经生效，但 lwip/ip4_addr.h 此时会提供
 *    struct ip4_addr 与 ip4_addr_t，足够声明 wm_ip4_route_src。
 * ======================================================================= */
#ifndef LWIP_HOOK_IP4_ROUTE_SRC
struct netif;
struct ip4_addr;
extern struct netif *wm_ip4_route_src(const struct ip4_addr *dest,
                                      const struct ip4_addr *src);
#define LWIP_HOOK_IP4_ROUTE_SRC          wm_ip4_route_src
#endif

/* =========================================================================
 * 4) 基线加载完成后强制覆盖：vendor 依赖的 lwip22 默认开关与 air101 需求
 *    不一致，必须在基线 include 之后用 #undef + #define 重写。
 *
 *    - LWIP_NETIF_STATUS_CALLBACK = 1   netif_set_status_callback() 可用
 *    - LWIP_NETIF_HOSTNAME        = 1   ethernetif_init() 设 hostname
 *    - LWIP_IGMP                  = 1   ethernetif.c 注册 IGMP MAC filter
 *    - LWIP_NETIF_API             = 0   同 lwip22 默认，保持 NO_SYS=1
 *
 *    lwip22 lwipopts 用裸 #define 定义这些宏（没有 #ifndef 保护），所以
 *    必须在基线 include 之后用 #undef + #define 重写。
 * ======================================================================= */
#ifdef LWIP_NETIF_STATUS_CALLBACK
#undef LWIP_NETIF_STATUS_CALLBACK
#endif
#define LWIP_NETIF_STATUS_CALLBACK        1

#ifdef LWIP_NETIF_HOSTNAME
#undef LWIP_NETIF_HOSTNAME
#endif
#define LWIP_NETIF_HOSTNAME               1

#ifdef LWIP_IGMP
#undef LWIP_IGMP
#endif
#define LWIP_IGMP                          1

#endif /* LWIPOPTS_OVERRIDE_H */