#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_netdrv_dhcp_client.h"
#include "luat_network_adapter.h"
#include "net_lwip2.h"

#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "lwip/ip_addr.h"

#include <string.h>

#define LUAT_LOG_TAG "netdrv"
#include "luat_log.h"

// ============================================================================
// External declarations
// ============================================================================

// STA netif getter from SDK
extern struct netif *tls_get_netif(void);

// AP netif (defined in src/network/lwip2.1.3/netif/wm_ethernet.c)
extern struct netif *nif4apsta;

// ============================================================================
// Static driver instances (STA + AP only, no ETH)
// ============================================================================

static luat_netdrv_t g_netdrv_sta;
static luat_netdrv_t g_netdrv_ap;

// Initialization flags
static uint8_t g_sta_init_ok = 0;
static uint8_t g_ap_init_ok = 0;

// ============================================================================
// Forward declarations
// ============================================================================

static int sta_bootup_cb(luat_netdrv_t* drv, void* userdata);
static int ap_bootup_cb(luat_netdrv_t* drv, void* userdata);
static int sta_dhcp(luat_netdrv_t* drv, void* userdata, int enable);
static void netif_dataout(luat_netdrv_t* drv, void* userdata, uint8_t* buff, uint16_t len);

// ============================================================================
// dataout callback - send packets through netif->linkoutput
// ============================================================================

static void netif_dataout(luat_netdrv_t* drv, void* userdata, uint8_t* buff, uint16_t len) {
    if (userdata == NULL || len < 16) {
        LLOGD("netif_dataout: invalid params %p len=%d", userdata, len);
        return;
    }

    struct netif *netif = (struct netif *)userdata;
    if (netif->linkoutput == NULL) {
        LLOGW("netif_dataout: linkoutput is NULL");
        return;
    }

    struct pbuf *p = pbuf_alloc(PBUF_RAW_TX, len, PBUF_RAM);
    if (p == NULL) {
        LLOGW("netif_dataout: pbuf_alloc failed len=%d", len);
        return;
    }

    pbuf_take(p, buff, len);
    err_t ret = netif->linkoutput(netif, p);
    (void)ret;  // Suppress unused variable warning
    pbuf_free(p);
}

// ============================================================================
// STA boot callback
// ============================================================================

static int sta_bootup_cb(luat_netdrv_t* drv, void* userdata) {
    (void)userdata;  // Unused

    if (g_sta_init_ok) {
        return 0;  // Already initialized
    }

    struct netif *sta = tls_get_netif();
    if (sta == NULL) {
        LLOGE("sta_bootup: tls_get_netif() returned NULL");
        return -1;
    }

    // Register with net_lwip2 adapter layer
    net_lwip2_set_netif(NW_ADAPTER_INDEX_LWIP_WIFI_STA, sta);
    net_lwip2_register_adapter(NW_ADAPTER_INDEX_LWIP_WIFI_STA);

    // Store netif reference
    g_netdrv_sta.netif = sta;
    g_netdrv_sta.userdata = sta;

    // DHCP is on by default; the netdrv DHCP timer checks drv->dhcp_enable before running
    g_netdrv_sta.dhcp_enable = 1;

    LLOGI("STA netdrv registered, netif=%p", sta);
    g_sta_init_ok = 1;
    return 0;
}

// ============================================================================
// AP boot callback
// ============================================================================

static int ap_bootup_cb(luat_netdrv_t* drv, void* userdata) {
    (void)userdata;  // Unused

    if (g_ap_init_ok) {
        return 0;  // Already initialized
    }

    // AP netif is created when softap starts
    if (nif4apsta == NULL) {
        LLOGD("ap_bootup: nif4apsta is NULL, AP not started yet");
        return -1;
    }

    // Register with net_lwip2 adapter layer
    net_lwip2_set_netif(NW_ADAPTER_INDEX_LWIP_WIFI_AP, nif4apsta);
    net_lwip2_register_adapter(NW_ADAPTER_INDEX_LWIP_WIFI_AP);

    // Store netif reference
    g_netdrv_ap.netif = nif4apsta;
    g_netdrv_ap.userdata = nif4apsta;

    LLOGI("AP netdrv registered, netif=%p", nif4apsta);
    g_ap_init_ok = 1;
    return 0;
}

// ============================================================================
// STA DHCP callback
// ============================================================================

static int sta_dhcp(luat_netdrv_t* drv, void* userdata, int enable) {
    (void)userdata;

    struct netif *sta = tls_get_netif();
    if (sta == NULL) {
        LLOGW("sta_dhcp: STA netif is NULL");
        return -2;
    }

    // netdrv DHCP timer (dhcp_client_timer_cb) only runs the state machine when
    // drv->dhcp_enable is set, so we must update it before invoking start/stop.
    drv->dhcp_enable = (uint8_t)enable;

    if (enable && netif_is_up(sta) && netif_is_link_up(sta)) {
        luat_netdrv_dhcp_client_start(drv);
        LLOGD("sta_dhcp: DHCP client started");
    } else {
        luat_netdrv_dhcp_client_stop(drv);
        LLOGD("sta_dhcp: DHCP client stopped");
    }

    return 0;
}

// ============================================================================
// Public function: Start DHCP when WiFi connects
// ============================================================================

void luat_netdrv_sta_start_dhcp(void) {
    struct netif *sta = tls_get_netif();
    if (sta == NULL) {
        LLOGW("luat_netdrv_sta_start_dhcp: STA netif is NULL");
        return;
    }

    // Ensure netif is up
    if (!netif_is_up(sta)) {
        netif_set_up(sta);
    }

    // Set link state
    netif_set_link_up(sta);

    // netdrv framework drives the IP_READY/IP_LOSE events from luat_netdrv_dhcp_client.c;
    // l_wlan_cb no longer needs an event_cb shim.
    g_netdrv_sta.dhcp_enable = 1;

    // Start DHCP client via netdrv framework
    LLOGI("Starting netdrv DHCP client, netif=%p", sta);
    luat_netdrv_dhcp_client_start(&g_netdrv_sta);
}

// ============================================================================
// Public function: Initialize AP netdrv when softap starts
// ============================================================================

void luat_netdrv_ap_init(void) {
    // AP netif is created when softap starts
    if (nif4apsta == NULL) {
        LLOGW("luat_netdrv_ap_init: nif4apsta is NULL");
        return;
    }

    // Initialize AP driver if not done
    if (!g_ap_init_ok) {
        // Register with net_lwip2 adapter layer
        net_lwip2_set_netif(NW_ADAPTER_INDEX_LWIP_WIFI_AP, nif4apsta);
        net_lwip2_register_adapter(NW_ADAPTER_INDEX_LWIP_WIFI_AP);

        // Store netif reference
        g_netdrv_ap.netif = nif4apsta;
        g_netdrv_ap.userdata = nif4apsta;

        // Ensure netif is up synchronously (SDK uses async netifapi which may not complete yet)
        // Note: SDK's tls_netif2_set_up() uses netif_set_link_up() (sync) + netifapi_netif_set_up() (async)
        // We call netif_set_up() directly to ensure netif_is_up() returns true immediately
        if (!netif_is_up(nif4apsta)) {
            netif_set_up(nif4apsta);
        }
        if (!netif_is_link_up(nif4apsta)) {
            netif_set_link_up(nif4apsta);
        }

        LLOGI("AP netdrv initialized, netif=%p, link_up=%d, up=%d, ip=%s",
              nif4apsta,
              netif_is_link_up(nif4apsta),
              netif_is_up(nif4apsta),
              ipaddr_ntoa(&nif4apsta->ip_addr));

        g_ap_init_ok = 1;
    }
}

// ============================================================================
// Registration function - called from luat_wlan_init()
// ============================================================================

void luat_netdrv_register_xt804(void) {
    // Initialize driver instances
    memset(&g_netdrv_sta, 0, sizeof(luat_netdrv_t));
    memset(&g_netdrv_ap, 0, sizeof(luat_netdrv_t));

    // Configure STA driver
    g_netdrv_sta.id = NW_ADAPTER_INDEX_LWIP_WIFI_STA;
    g_netdrv_sta.boot = sta_bootup_cb;
    g_netdrv_sta.dataout = netif_dataout;
    g_netdrv_sta.dhcp = sta_dhcp;

    // Configure AP driver (no DHCP client for AP mode)
    g_netdrv_ap.id = NW_ADAPTER_INDEX_LWIP_WIFI_AP;
    g_netdrv_ap.boot = ap_bootup_cb;
    g_netdrv_ap.dataout = netif_dataout;

    // Set AP netif immediately if already available
    // nif4apsta is created during Tcpip_stack_init(), which runs before luat_wlan_init()
    if (nif4apsta != NULL) {
        g_netdrv_ap.netif = nif4apsta;
        g_netdrv_ap.userdata = nif4apsta;
        LLOGI("AP netif pre-set during registration, netif=%p", nif4apsta);
    }

    // Register drivers with netdrv framework
    luat_netdrv_register(NW_ADAPTER_INDEX_LWIP_WIFI_STA, &g_netdrv_sta);
    luat_netdrv_register(NW_ADAPTER_INDEX_LWIP_WIFI_AP, &g_netdrv_ap);

    
    // netif association is handled by netdrv boot callbacks
    // netdrv was registered early in main.c, trigger boot now
    luat_netdrv_conf_t drvconf = {0};
    drvconf.id = NW_ADAPTER_INDEX_LWIP_WIFI_STA;
    luat_netdrv_setup(&drvconf);
    extern struct netif *nif4apsta;
    if (nif4apsta) {
        drvconf.id = NW_ADAPTER_INDEX_LWIP_WIFI_AP;
        luat_netdrv_setup(&drvconf);
    }

    // Set STA as default network adapter
    network_register_set_default(NW_ADAPTER_INDEX_LWIP_WIFI_STA);

    LLOGI("xt804 netdrv registered (STA + AP)");
}

// ============================================================================
// Optional: Static IP configuration for STA
// ============================================================================

void luat_netdrv_sta_set_static_ip(ip_addr_t* ip, ip_addr_t* gateway, ip_addr_t* mask) {
    struct netif *sta = tls_get_netif();
    if (sta == NULL) {
        LLOGW("luat_netdrv_sta_set_static_ip: STA netif is NULL");
        return;
    }

    // Stop DHCP if running
    if (g_netdrv_sta.dhcp_enable) {
        luat_netdrv_dhcp_client_stop(&g_netdrv_sta);
        g_netdrv_sta.dhcp_enable = 0;
    }

    // Set static IP
    netif_set_ipaddr(sta, ip_2_ip4(ip));
    netif_set_gw(sta, ip_2_ip4(gateway));
    netif_set_netmask(sta, ip_2_ip4(mask));

    LLOGI("STA static IP configured: %s / %s / %s",
          ipaddr_ntoa(ip), ipaddr_ntoa(mask), ipaddr_ntoa(gateway));
}