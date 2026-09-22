/**
 * @file    wm_ethernet.c
 *
 * @brief   air101 vendor IP 栈入口（lwIP 2.2 移植版）
 *
 * 本文件由 src/network/lwip2.1.3/netif/wm_ethernet.c 平移到 lwip22，关键
 * 变更：
 *   - 移除 netifapi_*（lwip22 NO_SYS=1 + LWIP_NETIF_API=0 下不存在对应实现），
 *     改用同步 netif_add / netif_set_default / netif_set_status_callback。
 *   - tcpip_init(NULL, NULL) 在 lwip22 NO_SYS=1 下不存在（api/tcpip.c 整个
 *     文件被 #if !NO_SYS 包住），改为 lwip_init() 初始化核心；lwip worker
 *     task 改由 LuatOS port 层 luat_rtos_lwip.c 提供的 luat_lwip_init()
 *     启动（extern，编译期链接由 xmake 端把 luat_rtos_lwip.c 加进来）。
 *   - 移除 vendor alg.c NAPT（NAPT 已迁出到 netdrv），不再调用
 *     alg_napt_init / tls_ethernet_ip_rx_callback(alg_input)。
 *   - 保留所有 vendor 私有符号（tls_netif_*、tls_dhcp_* 空体、tls_dhcps_*、
 *     tls_dnss_*、tls_get_netif、nif4apsta），保证 app/network/luat_wlan_*
 *     与 app/network/luat_netdrv_* 链接不破。
 *   - netif 状态回调签名变化：lwip2.1.3 vendor 用 (netif, u8 netif_state)，
 *     lwip22 标准改成 (netif)，事件分发改为本地实现。
 *
 * lwIP IPv6：air101 把 TLS_CONFIG_IPV6 打开后，low_level_init() 内启用
 * SLAAC + RS，netif_set_ip6_autoconfig_enabled 由 ethernetif.c 完成；本
 * 文件仅负责 netif 创建和事件分发。
 */

#include <string.h>
#include "wm_config.h"
#include "wm_mem.h"
#include "wm_params.h"
#include "wm_wifi.h"
#include "tls_common.h"

#include "lwip/opt.h"
#include "lwip/tcpip.h"
#include "lwip/init.h"
#include "lwip/dhcp.h"
#include "lwip/dns.h"
#include "lwip/netif.h"
#include "lwip/ip_addr.h"
#include "lwip/ip4_addr.h"
#include "lwip/stats.h"
#include "lwip/sys.h"
#include "lwip/memp.h"
#include "lwip/api.h"
#include "lwip/netifapi.h"

#include "list.h"
#include "lwip/sockets.h"

#include "app/wm_netif2.1.3.h"

/* ethernetif.c 声明: STA/AP 网卡的 init_fn + 数据输入入口 */
err_t ethernetif_init(struct netif *netif);
int  ethernetif_input(const u8 *bssid, u8 *buf, u32 buf_len);

/* lwip22 不再自带 netif/ethernetif.h；ethernetif.c 是我们 vendored 进来的，
 * 在此 forward-declare ethernetif_init()。netif_add() 要求 init 回调是
 * netif_init_fn（与 ethernetif_init 签名一致）。
 *
 * 同时声明 netif_input()：lwip22 NO_SYS=1 下 api/tcpip.c 整个文件被
 * #if !NO_SYS 包住，tcpip_input() 不存在；netif_input() 在 core/netif.c
 * 里实现，对 NETIF_FLAG_ETHARP/ETHERNET netif 走 ethernet_input，否则
 * ip_input，正好对应 lwip2.1.3 时代 tcpip_input 的语义。 */
err_t ethernetif_init(struct netif *netif);
err_t netif_input(struct pbuf *p, struct netif *inp);

#if TLS_CONFIG_SOCKET_RAW
#include "tls_netconn.h"
#endif
#if TLS_CONFIG_RMMS
#include "tls_sys.h"
#include "wm_rmms.h"
#endif

#define LUAT_LOG_TAG "wmet"
#include "luat_log.h"

/* ===========================================================================
 * vendor 私有全局
 * ======================================================================= */
static struct tls_ethif *ethif  = NULL;
static struct netif      *nif   = NULL;          /* STA netif */
#if TLS_CONFIG_AP
static struct tls_ethif *ethif2 = NULL;
struct netif *nif4apsta = NULL;                  /* AP netif，外部可见 */
#endif

static struct tls_netif_status_event netif_status_event;
static u8_t netif_initialized;

/* ===========================================================================
 * extern：从 lwip22 移植层 luat_rtos_lwip.c 引入 lwip worker task 启动入口。
 *
 * 该函数在 lwip22 NO_SYS=1 模式下等价于 lwip2.1.3 的 tcpip_init()：内部
 * 调用 lwip_init() 并创建一个 rtos task 异步处理 tcpip 事件。airlink SOC
 * 启动由 xmake 把 components/network/lwip22/port/luat_rtos/luat_rtos_lwip.c
 * 加入编译后即可链接到。
 * ======================================================================= */
extern void luat_lwip_init(void);

/* ===========================================================================
 * src-based IPv4 路由 hook（lwipopts_override.h 已声明 LWIP_HOOK_IP4_ROUTE_SRC）
 * ======================================================================= */
struct netif *wm_ip4_route_src(const ip4_addr_t *dest, const ip4_addr_t *src)
{
    struct netif *netif;

    for (netif = netif_list; netif != NULL; netif = netif->next) {
        if (netif_is_up(netif) && netif_is_link_up(netif)
            && !ip4_addr_isany(netif_ip4_addr(netif))) {
            if (src != NULL) {
                if (ip4_addr_isany(src)) {
                    if (ip4_addr_isbroadcast(dest, netif))
                        return netif;
                } else {
                    if (ip4_addr_netcmp(src, netif_ip4_addr(netif),
                                        netif_ip4_netmask(netif))) {
                        return netif;
                    }
                }
            } else {
                if (ip4_addr_isbroadcast(dest, netif))
                    return netif;
            }
        }
    }
    return NULL;
}

/* ===========================================================================
 * netif 状态回调（lwip22 标准签名：void (*)(struct netif *)）
 *
 * lwip2.1.3 vendor 版带一个 u8 netif_state 形参；lwip22 改为单参，本函数自
 * 己根据 netif 当前 IP 状态分发事件码。
 * ======================================================================= */
static void fire_status_event(u8_t code)
{
    struct tls_netif_status_event *status_event;
    dl_list_for_each(status_event, &netif_status_event.list,
                     struct tls_netif_status_event, list) {
        if (status_event->status_callback != NULL) {
            status_event->status_callback(code);
        }
    }
}

static void netif_status_changed(struct netif *netif)
{
    if (!netif_is_up(netif))
        return;

    if (ip4_addr_isany(netif_ip4_addr(netif))) {
        /* IPv4 还没拿到，触发 JOIN_FAILED（按需：原 vendor 用
         * tls_dhcp_get_ip_timeout_flag() 区分；airlink 路径下 netdrv
         * 接管 DHCP，超时由 netdrv 自己 fire，这里保持简单分发。 */
        return;
    }

#if TLS_CONFIG_IPV6
    if (!ip6_addr_isany(netif_ip6_addr(netif, 0))) {
        fire_status_event(NETIF_IPV6_NET_UP);
        return;
    }
#endif
    fire_status_event(NETIF_IP_NET_UP);
}

#if TLS_CONFIG_AP
static void netif_status_changed2(struct netif *netif)
{
    if (!netif_is_up(netif))
        return;
    if (!ip4_addr_isany(netif_ip4_addr(netif))) {
        fire_status_event(NETIF_IP_NET2_UP);
        return;
    }
#if TLS_CONFIG_IPV6
    if (!ip6_addr_isany(netif_ip6_addr(netif, 0))) {
        fire_status_event(NETIF_IPV6_NET_UP);
        return;
    }
#endif
}
#endif

static void wifi_status_changed(u8 status)
{
    struct tls_netif_status_event *status_event;
    dl_list_for_each(status_event, &netif_status_event.list,
                     struct tls_netif_status_event, list) {
        if (status_event->status_callback == NULL)
            continue;
        switch (status) {
            case WIFI_JOIN_SUCCESS:
                status_event->status_callback(NETIF_WIFI_JOIN_SUCCESS);
                break;
            case WIFI_JOIN_FAILED:
                status_event->status_callback(NETIF_WIFI_JOIN_FAILED);
                break;
            case WIFI_DISCONNECTED:
                status_event->status_callback(NETIF_WIFI_DISCONNECTED);
                break;
#if TLS_CONFIG_AP
            case WIFI_SOFTAP_SUCCESS:
                status_event->status_callback(NETIF_WIFI_SOFTAP_SUCCESS);
                break;
            case WIFI_SOFTAP_FAILED:
                status_event->status_callback(NETIF_WIFI_SOFTAP_FAILED);
                break;
            case WIFI_SOFTAP_CLOSED:
                status_event->status_callback(NETIF_WIFI_SOFTAP_CLOSED);
                break;
#endif
            default:
                break;
        }
    }
}

/* ===========================================================================
 * Tcpip_stack_init：lwip22 NO_SYS=1 下等价于"建好 STA + AP 两个 netif"
 *
 * lwip 核心初始化走 lwip_init()（lwip22 NO_SYS=1 标准入口），worker task
 * 由 LuatOS port 层 luat_lwip_init() 启动。netif_add/set_default/set_status_
 * callback 在 NO_SYS 下都是同步调用，不需要 netifapi_* 包裹。
 * ======================================================================= */
#if TLS_CONFIG_AP
#define TCPIP_STACK_INIT Tcpip_stack_init
#endif

struct netif *Tcpip_stack_init(void)
{
    if (netif_initialized) {
        LLOGW("Tcpip_stack_init already done");
        return nif;
    }

    /* 初始化 lwip 核心并启动 lwip worker task（luat_lwip_init 内部会调
     * lwip_init；此处直接调 lwip_init() 等价语义。*/
    lwip_init();
    luat_lwip_init();

#if TLS_CONFIG_AP
    nif4apsta = (struct netif *)tls_mem_alloc(sizeof(struct netif));
    if (nif4apsta == NULL) {
        LLOGE("Tcpip_stack_init: alloc apsta netif failed");
        return NULL;
    }
    memset(nif4apsta, 0, sizeof(struct netif));
    /* AP netif 先 add，挂在 netif_list 末尾；STA add 后会成为 netif_list 头
     * 并被设为 default。AP 在 lwip2.1.3 时代通过 nif->next 访问，lwip22
     * 同样保留 netif->next 链表指针，访问语义不变。 */
    if (netif_add(nif4apsta, IP4_ADDR_ANY, IP4_ADDR_ANY, IP4_ADDR_ANY,
                  NULL, ethernetif_init, netif_input) == NULL) {
        LLOGE("Tcpip_stack_init: netif_add(apsta) failed");
        tls_mem_free(nif4apsta);
        nif4apsta = NULL;
        return NULL;
    }
    netif_set_status_callback(nif4apsta, netif_status_changed2);
#endif

    nif = (struct netif *)tls_mem_alloc(sizeof(struct netif));
    if (nif == NULL) {
#if TLS_CONFIG_AP
        netif_remove(nif4apsta);
        tls_mem_free(nif4apsta);
        nif4apsta = NULL;
#endif
        LLOGE("Tcpip_stack_init: alloc sta netif failed");
        return NULL;
    }
    memset(nif, 0, sizeof(struct netif));
    if (netif_add(nif, IP4_ADDR_ANY, IP4_ADDR_ANY, IP4_ADDR_ANY,
                  NULL, ethernetif_init, netif_input) == NULL) {
        LLOGE("Tcpip_stack_init: netif_add(sta) failed");
#if TLS_CONFIG_AP
        netif_remove(nif4apsta);
        tls_mem_free(nif4apsta);
        nif4apsta = NULL;
#endif
        tls_mem_free(nif);
        nif = NULL;
        return NULL;
    }
    netif_set_default(nif);
    dl_list_init(&netif_status_event.list);
    netif_set_status_callback(nif, netif_status_changed);
    tls_wifi_status_change_cb_register(wifi_status_changed);

    /* Register Ethernet Rx Data callback from wifi */
    tls_ethernet_data_rx_callback(ethernetif_input);

    netif_initialized = 1;
    LLOGI("Tcpip_stack_init done (NO_SYS=1 lwip22)");
    return nif;
}

int tls_ethernet_init(void)
{
    if (ethif == NULL) {
        ethif = tls_mem_alloc(sizeof(struct tls_ethif));
        if (ethif == NULL) {
            LLOGE("tls_ethernet_init: alloc ethif failed");
            return -1;
        }
        memset(ethif, 0, sizeof(struct tls_ethif));
    }
#if TLS_CONFIG_AP
    if (ethif2 == NULL) {
        ethif2 = tls_mem_alloc(sizeof(struct tls_ethif));
        if (ethif2 == NULL) {
            LLOGE("tls_ethernet_init: alloc ethif2 failed");
            return -1;
        }
        memset(ethif2, 0, sizeof(struct tls_ethif));
    }
#endif

    TCPIP_STACK_INIT();

#if TLS_CONFIG_SOCKET_RAW
    tls_net_init();
#endif
    return 0;
}

void tls_netif_set_status(u8 status)
{
    if (ethif)
        ethif->status = status;
}

struct tls_ethif *tls_netif_get_ethif(void)
{
#if TLS_CONFIG_IPV6
    int i;
#endif
    if (nif && ethif) {
        ip_addr_copy(ethif->ip_addr,  nif->ip_addr);
        ip_addr_copy(ethif->netmask,  nif->netmask);
        ip_addr_copy(ethif->gw,       nif->gw);
#if TLS_CONFIG_IPV6
        for (i = 0; i < LWIP_IPV6_NUM_ADDRESSES; i++) {
            ip_addr_copy(ethif->ip6_addr[i], nif->ip6_addr[i]);
        }
        for (i = 0; i < LWIP_IPV6_NUM_ADDRESSES; i++) {
            ethif->ipv6_status[i] =
                (nif->ip6_addr_state[i] == IP6_ADDR_PREFERRED) ? 1 : 0;
        }
#endif
    }
    return ethif;
}

/* ===========================================================================
 * tls_dhcp_start / tls_dhcp_stop
 *
 * 在 lwip22 + netdrv 迁移里，DHCP client 已经移交给 LuatOS netdrv_dhcp_
 * client（plan §3.3、subagent B 的 luat_netdrv_air101.c）。本函数保留符号
 * 给可能还在用的旧链接单元（wm_netif.h 头声明），函数体置空。
 * 若某天有调用方仍在使用，会得到一个 silent no-op；这是过渡期设计。
 * ======================================================================= */
err_t tls_dhcp_start(void)
{
    LLOGW("tls_dhcp_start deprecated: DHCP moved to netdrv");
    return 0;
}

err_t tls_dhcp_stop(void)
{
    LLOGW("tls_dhcp_stop deprecated: DHCP moved to netdrv");
    return 0;
}

err_t tls_netif_set_addr(ip_addr_t *ipaddr,
                         ip_addr_t *netmask,
                         ip_addr_t *gw)
{
    if (nif == NULL)
        return -1;
    netif_set_addr(nif, ip_2_ip4(ipaddr), ip_2_ip4(netmask), ip_2_ip4(gw));
    return 0;
}

err_t tls_netif_set_up(void)
{
    if (nif == NULL)
        return -1;
    netif_set_link_up(nif);
    netif_set_up(nif);
    return 0;
}

err_t tls_netif_set_down(void)
{
    if (nif == NULL)
        return -1;
    netif_set_down(nif);
    return 0;
}

err_t tls_netif_add_status_event(tls_netif_status_event_fn event_fn)
{
    u32 cpu_sr;
    struct tls_netif_status_event *evt;
    if (nif == NULL || event_fn == NULL)
        return -1;
    /* 若已存在同名回调，先移除 */
    tls_netif_remove_status_event(event_fn);
    evt = tls_mem_alloc(sizeof(struct tls_netif_status_event));
    if (evt == NULL)
        return -1;
    memset(evt, 0, sizeof(struct tls_netif_status_event));
    evt->status_callback = event_fn;
    cpu_sr = tls_os_set_critical();
    dl_list_add_tail(&netif_status_event.list, &evt->list);
    tls_os_release_critical(cpu_sr);
    return 0;
}

err_t tls_netif_remove_status_event(tls_netif_status_event_fn event_fn)
{
    struct tls_netif_status_event *status_event;
    bool is_exist = FALSE;
    u32 cpu_sr;
    if (nif == NULL || event_fn == NULL)
        return 0;
    if (dl_list_empty(&netif_status_event.list))
        return 0;
    dl_list_for_each(status_event, &netif_status_event.list,
                     struct tls_netif_status_event, list) {
        if (status_event->status_callback == event_fn) {
            is_exist = TRUE;
            break;
        }
    }
    if (is_exist) {
        cpu_sr = tls_os_set_critical();
        dl_list_del(&status_event->list);
        tls_os_release_critical(cpu_sr);
        tls_mem_free(status_event);
    }
    return 0;
}

#if TLS_CONFIG_RMMS
INT8S tls_rmms_start(void)
{
    if (nif == NULL)
        return -1;
    return RMMS_Init(nif);
}
void tls_rmms_stop(void)
{
    RMMS_Fini();
}
#endif

#if TLS_CONFIG_AP
err_t tls_netif2_set_up(void)
{
    if (nif4apsta == NULL)
        return -1;
    netif_set_link_up(nif4apsta);
    netif_set_up(nif4apsta);
    return 0;
}

err_t tls_netif2_set_down(void)
{
    if (nif4apsta == NULL)
        return -1;
    netif_set_down(nif4apsta);
    return 0;
}

err_t tls_netif2_set_addr(ip_addr_t *ipaddr,
                          ip_addr_t *netmask,
                          ip_addr_t *gw)
{
    if (nif4apsta == NULL)
        return -1;
    netif_set_addr(nif4apsta, ip_2_ip4(ipaddr),
                   ip_2_ip4(netmask), ip_2_ip4(gw));
    return 0;
}
#endif

struct netif *tls_get_netif(void)
{
    return nif;
}