set_project("AIR101")
set_xmakever("2.6.3")

-- set_version("0.0.2", {build = "%Y%m%d%H%M"})
add_rules("mode.debug", "mode.release")

local luatos = "../LuatOS/"

toolchain("csky")
    set_kind("cross")
    -- on load
    on_load(function (toolchain)
        -- load basic configuration of cross toolchain
        toolchain:load_cross_toolchain()
    end)
toolchain_end()

package("csky")
    set_kind("toolchain")
    set_homepage("https://occ.t-head.cn/community/download?id=3885366095506644992")
    set_description("GNU Csky Embedded Toolchain")

    if is_host("windows") then
        set_urls("http://gz01.air32.cn:10888/files/public/xmake/csky-elfabiv2-tools-mingw-minilibc-$(version).tar.gz")
        add_versions("20210423", "e7d0130df26bcf7b625f7c0818251c04e6be4715ed9b3c8f6303081cea1f058b")
        add_versions("20230301", "1b958769601e8ba94a866df68215700614f55e0152933d5f5263899bb44d24f5")
        add_versions("20250328", "3eb0fa8681f0996136902171855db974659674ed3d6ebe7ddc6a601ddc0f27f2")
    elseif is_host("linux") then
        set_urls("http://gz01.air32.cn:10888/files/public/xmake/csky-elfabiv2-tools-x86_64-minilibc-$(version).tar.gz")
        add_versions("20210423", "8b9a353c157e4d44001a21974254a21cc0f3c7ea2bf3c894f18a905509a7048f")
        add_versions("20230301", "dac3c285d7dc9fe91805d6275c11fa260511cdd6a774891cbe2d79ec73535e10")
        add_versions("20250328", "ad5c8564ada7fbf77acb952448b03a394d7aafb56c945b2f8698d598076a69f9")
    end
    on_install("@windows", "@linux", function (package)
        os.vcp("*", package:installdir())
    end)
package_end()

add_requires("csky 20250328")
set_toolchains("csky@csky")

local flto = ""

--add macro defination
add_defines("GCC_COMPILE=1","TLS_CONFIG_CPU_XT804=1","NIMBLE_FTR=1","__LUATOS__","__USER_CODE__")

set_warnings("allextra")

-- set_optimize("fastest")
set_optimize("smallest")

-- set language: c99
set_languages("c99")
add_defines("MBEDTLS_CONFIG_FILE=\"mbedtls_config_air101.h\"")
add_asflags(flto .. "-DTLS_CONFIG_CPU_XT804=1 -DGCC_COMPILE=1 -mcpu=ck804ef -std=gnu99 -c -mhard-float -fdata-sections -ffunction-sections")
add_cflags(flto .. "-DTLS_CONFIG_CPU_XT804=1 -DGCC_COMPILE=1 -mcpu=ck804ef -std=gnu99 -c -mhard-float -Wall -fdata-sections -ffunction-sections")
add_cxflags(flto .. "-DTLS_CONFIG_CPU_XT804=1 -DGCC_COMPILE=1 -mcpu=ck804ef -std=gnu99 -c -mhard-float -Wall -fdata-sections -ffunction-sections")

-- 已经生效的GCC警告信息
-- add_cxflags("-Werror=maybe-uninitialized")
add_cxflags("-Werror=unused-value")
add_cxflags("-Werror=array-bounds")
add_cxflags("-Werror=return-type")
add_cxflags("-Werror=overflow")
add_cxflags("-Werror=empty-body")
add_cxflags("-Werror=old-style-declaration")
add_cxflags("-Werror=implicit-function-declaration")

-- -- 暂不考虑的GCC警告信息
add_cxflags("-Wno-unused-parameter")
add_cxflags("-Wno-unused-but-set-variable")
add_cxflags("-Wno-sign-compare")
add_cxflags("-Wno-unused-variable")
add_cxflags("-Wno-unused-function")

-- -- 待修复的GCC警告信息
-- add_cxflags("-Wno-int-conversion")
-- add_cxflags("-Wno-discarded-qualifiers")
-- add_cxflags("-Wno-pointer-sign")
-- -- add_cxflags("-Werror=type-limits")
-- add_cxflags("-Wno-incompatible-pointer-types")
-- add_cxflags("-Wno-pointer-to-int-cast")
-- add_cxflags("-Wno-int-to-pointer-cast")

add_cflags("-fno-builtin-exit -fno-builtin-strcat -fno-builtin-strncat -fno-builtin-strcpy -fno-builtin-strlen -fno-builtin-calloc -fno-builtin-malloc -fno-builtin-free")
add_cflags("-fjump-tables -ftree-switch-conversion")

-- add_cflags("-Werror=unused-value")

set_dependir("$(builddir)/.deps")
set_objectdir("$(builddir)/.objs")

set_policy("build.across_targets_in_parallel", false)

-- add_includedirs(luatos.."components/multimedia/")
add_includedirs("app/port",{public = true})

add_includedirs("include",{public = true})
add_includedirs("include/app",{public = true})
add_includedirs("include/driver",{public = true})
add_includedirs("include/os",{public = true})
add_includedirs("include/bt",{public = true})
add_includedirs("include/platform",{public = true})
add_includedirs("platform/common/params",{public = true})
add_includedirs("include/wifi",{public = true})
add_includedirs("include/arch/xt804",{public = true})
add_includedirs("include/arch/xt804/csi_core",{public = true})
add_includedirs("include/net",{public = true})
-- add_includedirs("demo",{public = true})
add_includedirs("platform/inc",{public = true})
add_includedirs(luatos.."components/mbedtls/include")

add_includedirs("src/os/rtos/include",{public = true})

add_includedirs("include/driver",{public = true})
-- lwip22: lwip2.1.3 已删除,改为 src/network/lwip22_port (vendor 网卡入口)
-- + ../LuatOS/components/network/lwip22 (核心协议栈).
-- 放在顶层 (而非 network target 内) 是为了让 air10x binary target
-- 编译 app/network/*.c 时也能找到 lwip22 头文件, 与原 lwip2.1.3 写法一致.
add_includedirs("src/network/lwip22_port")
-- build/lwipopts_gen/ 下生成的 lwipopts.h shim 必须放在 lwip22 include
-- 路径之前, 否则 lwip22 自带的 luat_rtos/lwipopts.h 会先于 shim 被找到,
-- 导致 LWIP_NETIF_STATUS_CALLBACK 等覆盖宏失效.
add_includedirs("build/lwipopts_gen")
add_includedirs(luatos.."components/network/lwip22/include")
add_includedirs(luatos.."components/network/lwip22/port/luat_rtos")
add_includedirs("src/network/api_wm",{public = true})


add_includedirs(luatos.."components/mbedtls/include")
add_includedirs(luatos.."components/common_api/include", {public = true})
add_includedirs(luatos.."components/luat_image/include", {public = true})
-- add_includedirs("src/app/mbedtls/include",{public = true})
add_includedirs("platform/arch",{public = true})
add_includedirs("include/os",{public = true})
add_includedirs("include/wifi",{public = true})
add_includedirs("include/arch/xt804",{public = true})
add_includedirs("include/arch/xt804/csi_core",{public = true})
add_includedirs("include/app",{public = true})
add_includedirs("include/net",{public = true})
-- add_includedirs("demo",{public = true})
add_includedirs("platform/inc",{public = true})

-- add_includedirs("demo/console")
add_includedirs("include/arch/xt804/csi_dsp")
add_includedirs("platform/sys")
add_includedirs("src/app/mbedtls/ports")
add_includedirs(luatos.."components/printf",{public = true})

-- add_ldflags(" -Wl,--wrap=malloc ",{force = true})
-- add_ldflags(" -Wl,--wrap=free ",{force = true})
-- add_ldflags(" -Wl,--wrap=zalloc ",{force = true})
-- add_ldflags(" -Wl,--wrap=calloc ",{force = true})
-- add_ldflags(" -Wl,--wrap=realloc ",{force = true})
add_ldflags(" -Wl,--wrap=localtime ",{force = true})
add_ldflags(" -Wl,--wrap=gmtime ",{force = true})
add_ldflags(" -Wl,--wrap=mktime ",{force = true})
add_ldflags(" -Wl,--wrap=printf ",{force = true})


target("app")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")

    add_includedirs("app/port",{public = true})

    add_files("src/app/**.c")
    remove_files("src/app/btapp/**.c")

    add_includedirs(os.dirs(path.join(os.scriptdir(),"src/app/**")))
    -- add_includedirs(os.dirs(path.join(os.scriptdir(),"src/bt/blehost/**")))


target_end()

target("wmarch")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    set_targetdir("$(projectdir)/lib")

    add_files("platform/arch/**.c")
    add_files("platform/arch/**.S")

    after_load(function (target)
        for _, sourcebatch in pairs(target:sourcebatches()) do
            if sourcebatch.sourcekind == "as" then -- only asm files
                for idx, objectfile in ipairs(sourcebatch.objectfiles) do
                    sourcebatch.objectfiles[idx] = objectfile:gsub("%.S%.o", ".o")
                end
            end
        end
    end)

target_end()

-- target("blehost")
--     set_kind("static")
--     set_plat("cross")
--     set_arch("c-sky")
--
--     add_files("src/bt/blehost/**.c")
--     add_includedirs(os.dirs(path.join(os.scriptdir(),"src/bt/blehost/**")))
--     
--     add_includedirs("app/port",{public = true})
--     add_includedirs(luatos.."lua/include",{public = true})
--     add_includedirs(luatos.."luat/include",{public = true})
--
--     add_includedirs("src/app/bleapp",{public = true})
--     add_includedirs("src/os/rtos/include",{public = true})
--     add_includedirs("include",{public = true})
--     add_includedirs("include/bt",{public = true})
--     add_includedirs("include/platform",{public = true})
--     add_includedirs("include/os",{public = true})
--     add_includedirs("include/arch/xt804",{public = true})
--     add_includedirs("include/arch/xt804/csi_core",{public = true})
--
--     remove_files("src/app/bleapp/wm_ble_server_wifi_app.c")
--
-- target_end()

target("hzfont")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    set_default(false)

    add_includedirs("app/port",{public = true})
    add_includedirs("include",{public = true})
    add_includedirs(luatos.."lua/include",{public = true})
    add_includedirs(luatos.."luat/include",{public = true})
    add_includedirs(luatos.."components/lcd",{public = true})
    add_includedirs(luatos.."components/u8g2",{public = true})
    add_includedirs(luatos.."components/hzfont/inc",{public = true})

    add_files(luatos.."components/hzfont/binding/*.c")
    add_files(luatos.."components/hzfont/src/*.c")

    set_targetdir("$(builddir)/lib")
target_end()

target("u8g2")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")

    add_files(luatos.."components/u8g2/*.c")

    add_includedirs("app/port",{public = true})
    add_includedirs("include",{public = true})
    add_includedirs(luatos.."lua/include",{public = true})
    add_includedirs(luatos.."luat/include",{public = true})
    add_includedirs(luatos.."components/u8g2",{public = true})
    add_includedirs(luatos.."components/gtfont")
    add_includedirs(luatos.."components/qrcode",{public = true})

    set_targetdir("$(builddir)/lib")
target_end()

target("miniz")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")

    add_files(luatos.."components/miniz/*.c")
    add_includedirs("app/port")
    add_includedirs("include")
    add_includedirs(luatos.."lua/include")
    add_includedirs(luatos.."luat/include")
    add_includedirs(luatos.."components/miniz")
    set_targetdir("$(builddir)/lib")
target_end()



target("fastlz")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")

    add_files(luatos.."components/fastlz/*.c")
    add_includedirs("app/port")
    add_includedirs("include")
    add_includedirs(luatos.."lua/include")
    add_includedirs(luatos.."luat/include")
    add_includedirs(luatos.."components/fastlz")
    set_targetdir("$(builddir)/lib")
target_end()

target("eink")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")


    add_files(luatos.."components/eink/*.c")
    add_files(luatos.."components/epaper/*.c")
    remove_files(luatos.."components/epaper/GUI_Paint.c")
    
    add_includedirs("app/port")
    add_includedirs("include")
    add_includedirs(luatos.."lua/include")
    add_includedirs(luatos.."luat/include")
    add_includedirs(luatos.."components/eink")
    add_includedirs(luatos.."components/epaper")
    add_includedirs(luatos.."components/u8g2")
    add_includedirs(luatos.."components/gtfont")
    add_includedirs(luatos.."components/qrcode")
    set_targetdir("$(builddir)/lib")
target_end()

-- target("audio")
--     set_kind("static")
--     set_plat("cross")
--     set_arch("c-sky")
--
--     add_includedirs("app/port")
--     add_includedirs("include")
--     add_includedirs(luatos.."lua/include")
--     add_includedirs(luatos.."luat/include")
--     add_includedirs(luatos.."components/common",{public = true})
--
--     add_includedirs(luatos.."components/multimedia/")
--     add_includedirs(luatos.."components/multimedia/mp3_decode")
--     add_includedirs(luatos.."components/multimedia/amr_decode/amr_common/dec/include")
--     add_includedirs(luatos.."components/multimedia/amr_decode/amr_nb/common/include")
--     add_includedirs(luatos.."components/multimedia/amr_decode/amr_nb/dec/include")
--     add_includedirs(luatos.."components/multimedia/amr_decode/amr_wb/dec/include")
--     add_includedirs(luatos.."components/multimedia/amr_decode/opencore-amrnb")
--     add_includedirs(luatos.."components/multimedia/amr_decode/opencore-amrwb")
--     add_includedirs(luatos.."components/multimedia/amr_decode/oscl")
--     add_includedirs(luatos.."components/multimedia/amr_decode/amr_nb/enc/src")
--     add_includedirs(luatos.."components/multimedia/vtool/include")
--     add_includedirs(luatos.."components/multimedia/audio/include")
--     add_includedirs(luatos.."components/common_api/include")
--     add_files(luatos.."components/multimedia/**.c")
--
--     -- exclude all opus files
--     remove_files(luatos.."components/multimedia/opus/**.c")
--
--     set_targetdir("$(builddir)/lib")
-- target_end()

target("network")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    add_includedirs("app/port")
    add_includedirs("include")
    add_includedirs(luatos.."lua/include")
    add_includedirs(luatos.."luat/include")
    add_includedirs(luatos.."components/common",{public = true})

    -- =========================================================================
    -- lwip22 替换 lwip2.1.3 (subagent A 完成的源码迁移)
    -- lwipopts_override.h 是 src/network/lwip22_port/ 下的项目覆盖层,
    -- 但 lwip 源码做的是 `#include "lwipopts.h"`,需要一个同名入口;
    -- 这里在 $(builddir)/lwipopts_gen/ 下生成两个包装,避免改 vendor 源码:
    --   1) lwipopts.h           : 转发到 lwipopts_override.h
    --   2) netif/ethernetif.h   : 转发到 lwip22 公共 lwip/etharp.h,补 ethernetif_* 声明
    --      (旧版 vendor dhcp_server.c / dns_server.c 还在
    --       #include "netif/ethernetif.h", 该头在 lwip2.1.3/include/netif/ 下
    --       随 lwip2.1.3 目录被一起删了)
    -- 注意:lwip22 的 include dir 已在顶层添加过 (与原 lwip2.1.3 位置对称),
    -- 这里不再重复 add_includedirs.
    -- =========================================================================
    local lwip22_path = luatos .. "components/network/lwip22/"
    -- 使用固定 build/ 路径 (xmake 默认 builddir);若用户自定义 builddir,
    -- 也可改用 -D 传入或 on_build 钩子,本次按默认 build/ 处理.
    local lwipopts_gen_dir = path.join(os.projectdir(), "build", "lwipopts_gen")
    on_load(function (target)
        if not os.isdir(lwipopts_gen_dir) then
            os.mkdir(lwipopts_gen_dir)
        end
        local netif_gen_dir = path.join(lwipopts_gen_dir, "netif")
        if not os.isdir(netif_gen_dir) then
            os.mkdir(netif_gen_dir)
        end
        -- 1) lwipopts.h -> lwipopts_override.h
        local lwipopts_wrapper = path.join(lwipopts_gen_dir, "lwipopts.h")
        local override = path.join(os.projectdir(),
            "src/network/lwip22_port/lwipopts_override.h")
        io.writefile(lwipopts_wrapper,
            '/* Auto-generated by xmake.lua: forward to lwipopts_override.h */\n' ..
            '#include "' .. override:gsub("\\", "/") .. '"\n')
        -- 2) netif/ethernetif.h -> lwip/etharp.h + ethernetif_init/input 声明
        local eth_wrapper = path.join(netif_gen_dir, "ethernetif.h")
        io.writefile(eth_wrapper,
            [[/* Auto-generated by xmake.lua: shim for vendor dhcp_server.c / dns_server.c
 * lwip22 不再自带 netif/ethernetif.h (lwip2.1.3/include/netif/ethernetif.h
 * 已随 lwip2.1.3 目录删除). 本文件保留原版 API:
 *   - #include "lwip/etharp.h" 提供 etharp_update_arp_entry/ETHARP_FLAG_STATIC_ENTRY
 *   - ethernetif_init/input 声明来自 src/network/lwip22_port/ethernetif.c
 */
#ifndef ETHERNETIF_H_INCLUDED
#define ETHERNETIF_H_INCLUDED
#include "lwip/netif.h"
#include "lwip/ip_addr.h"
#include "lwip/err.h"
#include "lwip/etharp.h"
err_t ethernetif_init(struct netif *netif);
int  ethernetif_input(const u8 *bssid, u8 *buf, u32 buf_len);
#endif
]])
    end)
    add_includedirs(lwipopts_gen_dir, {public = true})

    -- vendor 私有 api_wm (tls_netconn 等扩展, 与 lwip 版本无关)
    add_files("src/network/api_wm/*.c")
    -- lwip22 核心协议栈
    add_files("src/network/lwip22_port/*.c")
    add_files(lwip22_path .. "api/**.c")
    add_files(lwip22_path .. "core/**.c")
    add_files(lwip22_path .. "netif/**.c")
    -- 仓库裁掉了 PPP 内存池 (memp_std.h 未声明 PPP/PPPOL2TP 池),
    -- 不能编译 lwip22 自带的 netif/ppp,需要 PPP 走 vendor 副本.
    remove_files(lwip22_path .. "netif/ppp/**.c")
    -- luat_rtos 适配: 单一 lwip 任务线程 + 事件投递 (替代旧 sys_arch)
    add_files(lwip22_path .. "port/luat_rtos/luat_rtos_lwip.c")

    -- app/network (vendor netdrv 注册 + wlan 适配)
    add_files("app/network/**.c")
    

    -- network
    add_includedirs(luatos.."components/network/adapter",{public = true})
    add_files(luatos.."components/network/adapter/*.c")
    add_includedirs(luatos.."components/network/adapter_lwip2",{public = true})
    add_files(luatos.."components/network/adapter_lwip2/*.c")

    -- netdrv
    add_includedirs(luatos.."components/network/netdrv/include",{public = true})
    add_files(luatos.."components/network/netdrv/**.c")
    -- air101 无 USB 外挂以太网, luat_netdrv_usb_eth.c 依赖 SOC 专属头
    -- (luat_common_api.h / luat_usb.h), 编译期排除.
    remove_files(luatos.."components/network/netdrv/src/luat_netdrv_usb_eth.c")

    -- icmp
    add_includedirs(luatos.."components/network/icmp/include",{public = true})
    add_files(luatos.."components/network/icmp/**.c")

    -- airlink
    add_includedirs(luatos.."components/airlink/include",{public = true})
    add_files(luatos.."components/airlink/**.c")

    -- w5500
    add_includedirs(luatos.."components/ethernet/common",{public = true})
    add_files(luatos.."components/ethernet/common/*.c")

    -- wlan
    add_includedirs(luatos.."components/wlan")
    add_files(luatos.."components/wlan/**.c")

    -- http_parser
    add_includedirs(luatos.."components/network/http_parser",{public = true})
    add_files(luatos.."components/network/http_parser/*.c")
    
    -- httpsrv
    add_includedirs(luatos.."components/network/httpsrv/inc",{public = true})
    add_files(luatos.."components/network/httpsrv/src/*.c")

    
    -- http
    add_includedirs(luatos.."components/network/libhttp",{public = true})
    add_files(luatos.."components/network/libhttp/*.c")

    -- libftp
    add_includedirs(luatos.."components/network/libftp",{public = true})
    add_files(luatos.."components/network/libftp/*.c")
    
    -- websocket
    add_includedirs(luatos.."components/network/websocket",{public = true})
    add_files(luatos.."components/network/websocket/*.c")

    -- sntp
    add_includedirs(luatos.."components/network/libsntp",{public = true})
    add_files(luatos.."components/network/libsntp/*.c")

    -- mqtt
    add_includedirs(luatos.."components/network/libemqtt",{public = true})
    add_files(luatos.."components/network/libemqtt/*.c")

    -- ymodem
    add_includedirs(luatos.."components/ymodem",{public = true})
    add_files(luatos.."components/ymodem/*.c")

    -- errdump
    add_includedirs(luatos.."components/network/errdump",{public = true})
    add_files(luatos.."components/network/errdump/*.c")

    -- ercoap
    -- add_includedirs(luatos.."components/network/ercoap/include",{public = true})
    -- add_files(luatos.."components/network/ercoap/src/*.c")
    -- add_files(luatos.."components/network/ercoap/binding/*.c")

    -- xxtea
    add_includedirs(luatos.."components/xxtea/include",{public = true})
    add_files(luatos.."components/xxtea/src/*.c")
    add_files(luatos.."components/xxtea/binding/*.c")

    -- pcap
    -- add_includedirs(luatos.."components/network/pcap/include",{public = true})
    -- add_files(luatos.."components/network/pcap/src/*.c")

    -- zlink
    -- add_includedirs(luatos.."components/network/zlink/include",{public = true})
    -- add_files(luatos.."components/network/zlink/src/*.c")

    -- ulwip 已删除 (subagent B 迁移到 netdrv_dhcp_client),这里不再 include

    -- spi slave
    -- add_includedirs(luatos.."components/device/spi_slave/include",{public = true})
    -- add_files(luatos.."components/device/spi_slave/**.c")

    -- wlan raw
    add_includedirs(luatos.."components/device/wlanraw/include",{public = true})
    add_files(luatos.."components/device/wlanraw/**.c")

    -- hmeta
    add_includedirs(luatos.."components/hmeta",{public = true})
    add_files(luatos.."components/hmeta/**.c")
    -- air101 无 luat_hmeta_muid 实现 (PC-only), 排除 luat_lib_hmeta.c
    remove_files(luatos.."components/hmeta/luat_lib_hmeta.c")

    -- add soc_service
    add_includedirs(luatos.."components/soc_service/include",{public = true})
    add_files(luatos.."components/soc_service/**.c")

    -- add nanopb
    add_includedirs(luatos.."components/nanopb/include",{public = true})
    add_files(luatos.."components/nanopb/src/*.c")

    -- add new ble
    add_includedirs(luatos.."components/bluetooth/include",{public = true})


target_end()

target("mbedtls")
    set_kind("static")
    set_plat("cross")
    set_optimize("fastest",{force = true})
    set_targetdir("$(builddir)/lib")
    add_includedirs("app/port")
    add_includedirs("include")
    add_includedirs(luatos.."lua/include")
    add_includedirs(luatos.."luat/include")
    -- mbedtls
    add_files(luatos.."components/mbedtls/library/*.c")
target_end()

target("airui")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    set_default(false)


    add_includedirs("app/port")
    add_includedirs("include")
    add_includedirs(luatos.."lua/include")
    add_includedirs(luatos.."luat/include")

    add_includedirs(luatos.."components/lcd",{public = true})
    add_includedirs(luatos.."components/u8g2",{public = true})
    add_includedirs(luatos.."components/tp",{public = true})

    -- LVGL 9.4 + AirUI - 最基础组件编译
    -- 宏定义：启用 AirUI 和 SDL2 平台
    -- 头文件添加：lvgl9
    local luatos_root = luatos
    add_includedirs(luatos_root.."/components/airui")
    add_includedirs(luatos_root.."/components/airui/lvgl9")
    add_includedirs(luatos_root.."/components/airui/lvgl9/src")

    -- 先添加所有源文件
    add_files(luatos_root.."/components/airui/lvgl9/src/**.c")

    -- 排除不需要的组件（按优先级排序）
    -- 1. 硬件驱动（不需要）
    remove_files(luatos_root.."/components/airui/lvgl9/src/drivers/**/*.c")
    remove_files(luatos_root.."/components/airui/lvgl9/src/drivers/**/*.cpp")
    
    -- 2. 硬件加速绘制引擎（只保留软件渲染 SW）
    remove_files(luatos_root.."/components/airui/lvgl9/src/draw/dma2d/**/*.c")
    remove_files(luatos_root.."/components/airui/lvgl9/src/draw/eve/**/*.c")
    remove_files(luatos_root.."/components/airui/lvgl9/src/draw/nema_gfx/**/*.c")
    remove_files(luatos_root.."/components/airui/lvgl9/src/draw/nxp/**/*.c")
    remove_files(luatos_root.."/components/airui/lvgl9/src/draw/opengles/**/*.c")
    remove_files(luatos_root.."/components/airui/lvgl9/src/draw/renesas/**/*.c")
    remove_files(luatos_root.."/components/airui/lvgl9/src/draw/vg_lite/**/*.c")
    remove_files(luatos_root.."/components/airui/lvgl9/src/draw/sdl/**/*.c")
    remove_files(luatos_root.."/components/airui/lvgl9/src/draw/espressif/**/*.c")
    remove_files(luatos_root.."/components/airui/lvgl9/src/draw/convert/**/*.c")
    
    -- AirUI 架构配置
    -- 1. 公共头文件
    add_includedirs(luatos_root.."/components/airui/inc")
    
    -- 2. 包含 src 目录下的所有文件（递归）
    add_includedirs(luatos_root.."/components/airui/src")
    add_files(luatos_root.."/components/airui/src/**/*.c")
    
    -- 排除多媒体相关文件（NES、Video等）
    remove_files(luatos_root.."/components/airui/src/components/widgets/luat_airui_nes.c")
    remove_files(luatos_root.."/components/airui/src/components/widgets/luat_airui_video.c")
    
    -- 3. Lua 绑定层（binding，不在 src 目录下，需单独处理）
    add_includedirs(luatos_root.."/components/airui/binding")
    add_files(luatos_root.."/components/airui/binding/*.c")

    -- pinyin
    add_includedirs(luatos_root.."/components/pinyin/inc",{public = true})
    add_files(luatos_root.."/components/pinyin/binding/*.c")
    add_files(luatos_root.."/components/pinyin/src/*.c")


    set_targetdir("$(builddir)/lib")
target_end()

target("air10x")
    -- set kind
    set_kind("binary")
    set_plat("cross")
    set_arch("c-sky")
    set_targetdir("$(builddir)/out")
    on_load(function (target)


        import "buildx"
        local chip = buildx.chip()

        target:add("deps", "miniz")
        target:add("deps", "fastlz")
        
        local ld_data = io.readfile("./ld/xt804.ld")
        local ld_data_n = ld_data:gsub("SRAM_O", string.format("0x%X", chip.flash_app_offset))
        ld_data_n = ld_data_n:gsub("SRAM_L", string.format("0x%X", chip.flash_app_size))
        ld_data_n = ld_data_n:gsub("RAM_END", string.format("0x%X", chip.ram_end))
        io.writefile("./ld/air101_103.ld", ld_data_n)

        TARGET_NAME = chip.target_name
        target:set("filename", TARGET_NAME..".elf")
        target:add("ldflags", flto .. "-Wl,--gc-sections -Wl,-zmax-page-size=1024 -Wl,--whole-archive ./lib/libwmarch.a ./lib/libgt.a ./lib/libwlan.a ./lib/libbtcontroller.a -Wl,--no-whole-archive -mcpu=ck804ef -nostartfiles -mhard-float -lm -Wl,-T./ld/air101_103.ld -Wl,-ckmap=./build/out/"..TARGET_NAME..".map ",{force = true})
    end)

    add_deps("app")
    -- add_deps("wmarch")
    -- add_deps("blehost")
    add_deps("u8g2")
    add_deps("eink")
    add_deps("network")
    -- add_deps("opus131")
    -- add_deps("nes")
    -- add_deps("audio")
    -- add_deps("luatfonts")
    add_deps("mbedtls")
    -- add files
    add_files("app/*.c")
    add_files("app/port/*.c")
    add_files("app/custom/*.c")
    add_files("platform/sys/*.c")
    add_files("platform/drivers/**.c")
    add_files("src/os/**.c")
    add_files("src/os/**.S")
    add_files("platform/common/**.c")
    remove_files("app/port/luat_spi_slave_air101.c")
    remove_files("app/port/luat_audio_air101.c")


    add_files(luatos.."lua/src/*.c")
    add_files(luatos.."luat/modules/*.c")
    add_files(luatos.."luat/vfs/*.c")
    remove_files(luatos.."luat/vfs/luat_fs_posix.c")
    add_files(luatos.."luat/freertos/*.c")
    add_files(luatos.."components/rtos/freertos/*.c")
    
    add_files(luatos.."components/printf/*.c")

    add_files(luatos.."components/lcd/*.c")
    add_files(luatos.."components/sfd/*.c")
    -- add_files(luatos.."components/nr_micro_shell/*.c")
    -- add_files(luatos.."components/luf/*.c")

    add_files(luatos.."components/iconv/*.c")
    add_files(luatos.."components/lfs/*.c")
    add_files(luatos.."components/lua-cjson/*.c")
    add_files(luatos.."components/minmea/*.c")
    add_files(luatos.."luat/weak/luat_spi_*.c")
    add_files(luatos.."luat/weak/luat_rtos_legacy_to_std.c")
    add_files(luatos.."components/crypto/*.c")

    add_includedirs(luatos.."lua/include",{public = true})
    add_includedirs(luatos.."luat/include",{public = true})
    add_includedirs(luatos.."components/lcd",{public = true})
    add_includedirs(luatos.."components/miniz", {public = true})

    add_includedirs(luatos.."components/iconv")
    add_includedirs(luatos.."components/lfs")
    add_includedirs(luatos.."components/lua-cjson")
    add_includedirs(luatos.."components/minmea")

    add_files(luatos.."components/sfud/*.c")
    add_includedirs(luatos.."components/sfud")

    -- add_files(luatos.."components/statem/*.c")
    -- add_includedirs(luatos.."components/statem")

    add_files(luatos.."components/coremark/*.c")
    add_includedirs(luatos.."components/coremark")

    add_files(luatos.."components/cjson/*.c")
    add_includedirs(luatos.."components/cjson")
    
    -- eink
    add_includedirs(luatos.."components/eink")
    add_includedirs(luatos.."components/epaper")

    add_files(luatos.."components/mlx90640-library/*.c")
    add_includedirs(luatos.."components/mlx90640-library")

    add_files(luatos.."components/i2c-tools/*.c")
    add_includedirs(luatos.."components/i2c-tools")

    add_files(luatos.."components/tjpgd/*.c")
    add_includedirs(luatos.."components/tjpgd")

    -- ble
    add_includedirs("src/app/bleapp", "src/bt/blehost/nimble/include", "src/bt/blehost/nimble/host/include", "include/bt")
    add_includedirs("src/bt/blehost/nimble/transport/uart/include", "src/bt/blehost/porting/xt804/include")
    add_includedirs("src/bt/blehost/ext/tinycrypt/include", "src/bt/blehost/nimble/host/util/include")

    -- add_includedirs(luatos.."components/nr_micro_shell")

    -- flashdb & fal
    -- add_includedirs(luatos.."components/fal/inc")
    -- add_files(luatos.."components/fal/src/*.c")
    -- add_includedirs(luatos.."components/flashdb/inc")
    -- add_files(luatos.."components/flashdb/src/*.c")

    -- shell & cmux
    add_includedirs(luatos.."components/shell",{public = true})
    add_includedirs(luatos.."components/cmux",{public = true})
    -- add_files(luatos.."components/shell/*.c")
    -- add_files(luatos.."components/cmux/*.c")

    -- ymodem
    add_includedirs(luatos.."components/ymodem",{public = true})
    add_files(luatos.."components/ymodem/*.c")

    -- qrcode
    add_includedirs(luatos.."components/qrcode",{public = true})
    add_files(luatos.."components/qrcode/*.c")

    -- lora
    add_includedirs(luatos.."components/lora",{public = true})
    add_files(luatos.."components/lora/**.c")

    -- c_common
    add_includedirs(luatos.."components/common",{public = true})
    add_files(luatos.."components/common/*.c")

    -- iotauth
    add_includedirs(luatos.."components/iotauth", {public = true})
    add_files(luatos.."components/iotauth/*.c")


    -- tlfs3
    -- add_includedirs(luatos.."components/mempool/tlsf3")
    -- add_files(luatos.."components/mempool/tlsf3/*.c")
    
    add_includedirs(luatos.."components/serialization/protobuf")
    add_files(luatos.."components/serialization/protobuf/*.c")

    
    add_includedirs("src/bt/blehost/nimble/host/services/gap/include")
    add_includedirs("src/bt/blehost/nimble/host/services/gatt/include")
    
    add_includedirs(luatos.."components/nimble/inc")
    add_files(luatos.."components/nimble/src/*.c")
    
    -- add_includedirs(luatos.."components/rsa/inc")
    add_files(luatos.."components/rsa/**.c")

    -- 添加rtos的统一实现
    -- add_files(luatos.."components/rtos/freertos/*.c")

    -- 添加fskv
    add_includedirs(luatos.."components/fskv")
    add_files(luatos.."components/fskv/*.c")

    -- fatfs
    add_includedirs(luatos.."components/fatfs")
    add_files(luatos.."components/fatfs/*.c")

    -- 心率传感器
    add_files(luatos.."components/max30102/*.c")
    add_includedirs(luatos.."components/max30102")

    -- 国密算法, by chenxudong1208, 基于GMSSL
    add_includedirs(luatos.."components/gmssl/include")
    add_files(luatos.."components/gmssl/src/**.c")
    add_files(luatos.."components/gmssl/bind/*.c")

    -- tp
    add_includedirs(luatos.."components/tp/",{public = true})
    add_files(luatos.."components/tp/*.c")

    add_includedirs(luatos.."components/wlan")

	after_build(function(target)
        import "buildx"
        local chip = buildx.chip()
        local TARGET_NAME = chip.target_name
        local AIR10X_VERSION = chip.bsp_version

        sdk_dir = target:toolchains()[1]:sdkdir().."/"
        os.exec(sdk_dir .. "bin/csky-elfabiv2-objcopy -O binary $(builddir)/out/"..TARGET_NAME..".elf $(builddir)/out/"..TARGET_NAME..".bin")
        -- 默认不生成.asm和.list,调试的时候自行打开吧
        -- io.writefile("$(builddir)/out/"..TARGET_NAME..".asm", os.iorun(sdk_dir .. "bin/csky-elfabiv2-objdump -d $(builddir)/out/"..TARGET_NAME..".elf"))
        -- io.writefile("$(builddir)/out/"..TARGET_NAME..".list", os.iorun(sdk_dir .. "bin/csky-elfabiv2-objdump -h -S $(builddir)/out/"..TARGET_NAME..".elf"))
        io.writefile("$(builddir)/out/"..TARGET_NAME..".size", os.iorun(sdk_dir .. "bin/csky-elfabiv2-size $(builddir)/out/"..TARGET_NAME..".elf"))
        io.cat("$(builddir)/out/"..TARGET_NAME..".size")
        
        local wm_tool = "./tools/xt804/wm_tool"..(is_plat("windows") and ".exe" or "")
        -- 计算升级区地址 (从分区表获取 fota 偏移)
        local upgrade_addr = 0x8010000  -- 默认值
        if chip.partitions and chip.partitions.fota then
            upgrade_addr = chip.flash_base + chip.partitions.fota.offset
        end
        local app_image = "-fc 0 -it 1 -ih %x -ra %x -ua %x -nh 0 -un 0 -vs G01.00.02 -o $(builddir)/out/%s"
        app_image = string.format(app_image, chip.flash_app_offset - 1024, chip.flash_app_offset, upgrade_addr, chip.target_name)
        local cmd = wm_tool.." -b $(builddir)/out/"..TARGET_NAME..".bin " .. app_image
        print(cmd)
        os.exec(cmd)
        local sec_image = "-fc 0 -it 0 -ih 8002000 -ra 8002400 -ua %x -nh %x -un 0 -o ./tools/xt804/%s_secboot"
        sec_image = string.format(sec_image, upgrade_addr, chip.flash_app_offset - 1024, chip.target_name)
        cmd = wm_tool .. " -b ./tools/xt804/xt804_secboot.bin " .. sec_image
        print(cmd)
        os.exec(cmd)

        os.cp("./tools/xt804/"..TARGET_NAME.."_secboot.img", "$(builddir)/out/"..TARGET_NAME..".fls")
        local img = io.readfile("$(builddir)/out/"..TARGET_NAME..".img", {encoding = "binary"})
        local fls = io.open("$(builddir)/out/"..TARGET_NAME..".fls", "a+")
        if fls then fls:write(img) fls:close() end

        -- 统计刷机文件的大小, 
        -- 文件1 ./tools/xt804/"..TARGET_NAME.."_secboot.img"
        -- 文件2 $(builddir)/out/"..TARGET_NAME..".bin
        local secboot_size = io.readfile("./tools/xt804/"..TARGET_NAME.."_secboot.img", {encoding = "binary"}):len()
        local app_size = io.readfile("$(builddir)/out/"..TARGET_NAME..".img", {encoding = "binary"}):len()

        -- if is_mode("debug") then
        --     os.cd("./mklfs")
        --     os.exec("./luac_536_32bits.exe -s -o ./disk/main.luac ../main.lua")
        --     os.exec("./mklfs.exe -size 112")
        --     os.cd("../")
        --     os.mv("./mklfs/disk.fs", "$(builddir)/out/script.bin")
        --     if TARGET_NAME == "AIR101" then
        --         os.exec("./tools/xt804/wm_tool"..(is_plat("windows") and ".exe" or "").." -b  $(builddir)/out/script.bin -it 1 -fc 0 -ih 20008000 -ra 81E0000 -ua 0 -nh 0  -un 0 -o $(builddir)/out/script")
        --     else
        --         os.exec("./tools/xt804/wm_tool"..(is_plat("windows") and ".exe" or "").." -b  $(builddir)/out/script.bin -it 1 -fc 0 -ih 20008000 -ra 80E0000 -ua 0 -nh 0  -un 0 -o $(builddir)/out/script")
        --     end
        --     local script = io.readfile("$(builddir)/out/script.img", {encoding = "binary"})
        --     local fls = io.open("$(builddir)/out/"..TARGET_NAME..".fls", "a+")
        --     if fls then fls:write(script) fls:close() end
        -- elseif is_mode("release") then
            import("lib.detect.find_file")
            os.cp("$(builddir)/out/"..TARGET_NAME..".fls", "./soc_tools/"..TARGET_NAME..".fls")
            local path7z = nil
            if is_plat("windows") then
                path7z = "\"$(programdir)/winenv/bin/7z.exe\""
            elseif is_plat("linux") then
                path7z = find_file("7z", { "/usr/bin/"})
                if not path7z then
                    path7z = find_file("7zr", { "/usr/bin/"})
                end
            end
            if path7z then
                    local info_data = io.readfile("./soc_tools/"..TARGET_NAME..".json")
                    import("core.base.json")
                    local data = json.decode(info_data)
                    data.rom.fs.script.size = tonumber(LUAT_SCRIPT_SIZE)
                    
                    -- 从分区表获取各区域地址
                    local app_offset = chip.partitions.app and chip.partitions.app.offset or 0
                    local secboot_offset = chip.partitions.secboot and chip.partitions.secboot.offset or 0
                    local script_offset = chip.partitions.script and chip.partitions.script.offset or 0
                    local fota_offset = chip.partitions.fota and chip.partitions.fota.offset or 0
                    
                    -- 更新 app_addr (app分区起始 = header地址)
                    if app_offset > 0 then
                        data.download.app_addr = string.format("0x%08X", chip.flash_base + app_offset)
                        -- 添加 run_addr (代码实际运行地址 = app_addr + 0x400)
                        data.download.run_addr = string.format("0x%08X", chip.flash_base + app_offset + 1024)
                        print("分区表布局", "App header地址", data.download.app_addr, "代码运行地址", data.download.run_addr)
                    end
                    
                    -- 更新 core_addr (secboot地址)
                    if secboot_offset > 0 then
                        data.download.core_addr = string.format("0x%08X", chip.flash_base + secboot_offset)
                        print("分区表布局", "Core(secboot)地址", data.download.core_addr)
                    end
                    
                    -- 从分区表获取脚本区偏移
                    if script_offset > 0 then
                        -- 使用分区表中的偏移量，统一使用 0x 前缀格式
                        data.download.script_addr = string.format("0x%08X", chip.flash_base + script_offset)
                        data.rom.fs.script.offset = data.download.script_addr
                        data.rom.fs.script.size = chip.flash_script_size // 1024
                        print("分区表布局", "脚本区偏移量", data.download.script_addr)
                    elseif chip.flash_size == 2*1024*1024 then
                        data.download.script_addr = string.format("0x%08X", 0x81FC000-chip.flash_fs_size - chip.flash_script_size)
                        data.rom.fs.script.offset = data.download.script_addr
                        data.rom.fs.script.size = chip.flash_script_size // 1024
                        print("2M布局", "脚本区偏移量", data.download.script_addr)
                    else
                        data.download.script_addr = string.format("0x%08X", 0x80FC000-chip.flash_fs_size - chip.flash_script_size)
                        data.rom.fs.script.offset = data.download.script_addr
                        data.rom.fs.script.size = chip.flash_script_size // 1024
                        print("1M布局", "脚本区偏移量", data.download.script_addr)
                    end
                    -- 添加 OTA 升级区地址
                    if fota_offset > 0 then
                        data.download.ota_addr = string.format("0x%08X", chip.flash_base + fota_offset)
                        print("分区表布局", "OTA升级区偏移量", data.download.ota_addr)
                    end
                    -- 添加文件系统(LittleFS)分区信息
                    local fs_offset = chip.partitions.fs and chip.partitions.fs.offset or 0
                    local fs_size   = chip.partitions.fs and chip.partitions.fs.size or 0
                    if fs_offset > 0 then
                        data.download.fs_addr = string.format("0x%08X", chip.flash_base + fs_offset)
                        data.rom.fs.filesystem = data.rom.fs.filesystem or {}
                        data.rom.fs.filesystem.offset = data.download.fs_addr
                        data.rom.fs.filesystem.size   = fs_size // 1024
                        data.rom.fs.filesystem.type   = "lfs"
                        print("分区表布局", "文件系统偏移量", data.download.fs_addr, "大小", fs_size // 1024 .. "K")
                    end
                    -- 添加 KV (FSKV) 分区信息
                    local kv_offset = chip.partitions.kv and chip.partitions.kv.offset or 0
                    local kv_size   = chip.partitions.kv and chip.partitions.kv.size or 0
                    if kv_offset > 0 then
                        data.download.kv_addr = string.format("0x%08X", chip.flash_base + kv_offset)
                        data.rom.fs.kv = data.rom.fs.kv or {}
                        data.rom.fs.kv.offset = data.download.kv_addr
                        data.rom.fs.kv.size   = kv_size // 1024
                        data.rom.fs.kv.type   = "fskv"
                        print("分区表布局", "KV分区偏移量", data.download.kv_addr, "大小", kv_size // 1024 .. "K")
                    end
                    if chip.use_64bit then
                        data.script.bitw = 64
                    end
                    io.writefile("./soc_tools/info.json", json.encode(data))
                if chip.use_64bit then
                    os.cp("./soc_tools/script_64bit.img", "./soc_tools/script.img")
                else
                    os.cp("./soc_tools/script_32bit.img", "./soc_tools/script.img")
                end

                os.exec(path7z.." a -mx9 LuatOS-SoC_"..AIR10X_VERSION.."_"..TARGET_NAME..".7z ./soc_tools/air101_flash.exe ./soc_tools/info.json ./soc_tools/script.img ./app/port/luat_conf_bsp.h ./soc_tools/"..TARGET_NAME..".fls")
                dst = ""
                if chip.use_64bit then
                    dst = "$(builddir)/out/LuatOS-SoC_"..AIR10X_VERSION.."_Air"..TARGET_NAME:sub(4).."_101.soc"
                else
                    dst = "$(builddir)/out/LuatOS-SoC_"..AIR10X_VERSION.."_Air"..TARGET_NAME:sub(4).."_1.soc"
                end
                os.mv("LuatOS-SoC_"..AIR10X_VERSION.."_"..TARGET_NAME..".7z", dst)
                os.rm("./soc_tools/info.json")
                os.rm("./soc_tools/script.img")
                os.rm("./soc_tools/"..TARGET_NAME..".fls")
            else
                print("7z not find")
                os.rm("./soc_tools/"..TARGET_NAME..".fls")
                return
            end
            
            print("刷机文件大小统计:", "secboot区", secboot_size, "app区", app_size, "总大小", secboot_size + app_size)
    end)
target_end()

-- ============================================================================
-- 子项目: AIR6010 SPI slave (airlink 协处理器)
-- 独立 xmake.lua, 不继承主项目的全局宏/include 路径, 避免污染 air10x
-- ============================================================================
includes("project/spislave", {inherit = false})


-- Custom task: generate function dependency tree HTML from linker map file
task("maptree")
    set_menu {
        usage = "xmake maptree [options]",
        description = "Generate function dependency tree HTML from linker map file",
        options = {
            {nil, "map", "kv", nil, "Path to .map file (auto-detect if omitted)"},
            {nil, "entry", "kv", nil, "Entry function(s), comma-separated (default: UserMain,luat_main)"},
            {nil, "all-roots", "k", nil, "Use all uncalled functions as roots"},
        }
    }
    on_run(function ()
        import("core.base.option")
        import("core.project.config")

        -- Resolve map file
        local map_file = option.get("map")
        if not map_file then
            -- Auto-detect from build output
            local out_dir = "$(builddir)/out"
            local maps = os.files(path.join(out_dir, "*.map"))
            if #maps == 0 then
                out_dir = path.absolute("$(builddir)/out")
                maps = os.files(path.join(out_dir, "*.map"))
            end
            if #maps > 0 then
                map_file = maps[1]
                print("Auto-detected map file: " .. map_file)
            else
                raise("No .map file found in build/out/. Run xmake build first, or specify --map")
            end
        end

        -- Resolve Python
        local maptool_dir = "$(projectdir)/tools/maptool"
        local python = nil
        if is_host("windows") then
            python = path.join(maptool_dir, ".venv/Scripts/python.exe")
            if not os.isfile(python) then
                python = "python"
            end
        else
            python = path.join(maptool_dir, ".venv/bin/python")
            if not os.isfile(python) then
                python = "python3"
            end
        end

        local output_dir = path.join(maptool_dir, "output")
        os.mkdir(output_dir)
        local target_name = path.basename(map_file):gsub("%.map$", "")
        local output_file = path.join(output_dir, target_name .. "_tree.html")

        local cmd_args = {
            python,
            "-m", "maptool.cli",
            "--map", map_file,
            "--output", output_file,
            "--title", string.format("%s Function Dependency Tree", target_name),
        }

        local entries = option.get("entry")
        if entries then
            table.insert(cmd_args, "--entry")
            table.insert(cmd_args, entries)
        end

        if option.get("all-roots") then
            table.insert(cmd_args, "--all-roots")
        end

        local old_pythonpath = os.getenv("PYTHONPATH")
        os.setenv("PYTHONPATH", maptool_dir)
        os.execv(cmd_args[1], cmd_args, {curdir = maptool_dir})
        if old_pythonpath then
            os.setenv("PYTHONPATH", old_pythonpath)
        end

        print("")
        print("Generated: " .. output_file)
        print("Open this file in your browser to explore the function dependency tree.")
    end)
