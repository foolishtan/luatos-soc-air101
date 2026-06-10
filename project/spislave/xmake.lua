-- ============================================================================
-- AIR6010 SPI slave 编译入口
-- 角色: 作为 airlink SPI slave 协处理器, 通过 HSPI 与 host(air6208)通讯
--
-- 调用方式 (任选其一):
--   1) cd project/spislave && xmake f && xmake
--   2) 根 xmake.lua includes("project/spislave") 后 xmake build air6010_spislave
--
-- 关键设计: 路径解析基于 os.scriptdir() 推算 repo root, 两种模式都有效
-- ============================================================================

set_project("AIR6010")
set_xmakever("2.6.3")
add_rules("mode.debug", "mode.release")

-- ----------------------------------------------------------------------------
-- 路径解析: 无论 standalone 还是 included 模式, os.scriptdir() 始终是子项目目录
-- repo root = os.scriptdir() / "../.."
-- ----------------------------------------------------------------------------
local SCRIPT_DIR = os.scriptdir()
local ROOT = path.absolute(path.join(SCRIPT_DIR, "..", ".."))
local luatos = path.join(ROOT, "..", "LuatOS") .. "/"  -- ../LuatOS/ 相对 repo root

-- 把 ROOT 路径加入 makefile path, 让 add_includedirs/add_files 可以直接用相对路径
add_includedirs(ROOT, {public = true})

-- ============================================================================
-- 工具链: 复用根 xmake.lua 的 csky 工具链声明
-- ============================================================================
toolchain("csky")
    set_kind("cross")
    on_load(function (toolchain)
        toolchain:load_cross_toolchain()
    end)
toolchain_end()

package("csky")
    set_kind("toolchain")
    if is_host("windows") then
        set_urls("http://gz01.air32.cn:10888/files/public/xmake/csky-elfabiv2-tools-mingw-minilibc-$(version).tar.gz")
        add_versions("20250328", "3eb0fa8681f0996136902171855db974659674ed3d6ebe7ddc6a601ddc0f27f2")
    elseif is_host("linux") then
        set_urls("http://gz01.air32.cn:10888/files/public/xmake/csky-elfabiv2-tools-x86_64-minilibc-$(version).tar.gz")
        add_versions("20250328", "ad5c8564ada7fbf77acb952448b03a394d7aafb56c945b2f8698d598076a69f9")
    end
    on_install("@windows", "@linux", function (package)
        os.vcp("*", package:installdir())
    end)
package_end()

add_requires("csky 20250328")
set_toolchains("csky@csky")

local flto = ""

-- 基础宏 (定义 __LUATOS__ 以激活 luat_base.h → lua.h → luaconf.h → luat_conf_bsp.h 的 include 链)
add_defines("GCC_COMPILE=1", "TLS_CONFIG_CPU_XT804=1", "NIMBLE_FTR=1", "__USER_CODE__", "__LUATOS__", 'MBEDTLS_CONFIG_FILE="mbedtls_config_air101.h"')

set_warnings("allextra")
set_optimize("smallest")
set_languages("c99")

add_asflags(flto .. "-DTLS_CONFIG_CPU_XT804=1 -DGCC_COMPILE=1 -mcpu=ck804ef -std=gnu99 -c -mhard-float -fdata-sections -ffunction-sections")
set_policy("check.auto_ignore_flags", false)
add_cflags(flto .. "-include " .. path.join(SCRIPT_DIR, "conf\\luat_conf_bsp.h") .. " -DTLS_CONFIG_CPU_XT804=1 -DGCC_COMPILE=1 -mcpu=ck804ef -std=gnu99 -c -mhard-float -Wall -fdata-sections -ffunction-sections")
add_cxflags(flto .. "-DTLS_CONFIG_CPU_XT804=1 -DGCC_COMPILE=1 -mcpu=ck804ef -std=gnu99 -c -mhard-float -Wall -fdata-sections -ffunction-sections")


add_cxflags("-Werror=unused-value")
add_cxflags("-Werror=array-bounds")
add_cxflags("-Werror=return-type")
add_cxflags("-Werror=overflow")
add_cxflags("-Werror=empty-body")
add_cxflags("-Werror=old-style-declaration")
add_cxflags("-Werror=implicit-function-declaration")

add_cxflags("-Wno-unused-parameter")
add_cxflags("-Wno-unused-but-set-variable")
add_cxflags("-Wno-sign-compare")
add_cxflags("-Wno-unused-variable")
add_cxflags("-Wno-unused-function")

add_cflags("-fno-builtin-exit -fno-builtin-strcat -fno-builtin-strncat -fno-builtin-strcpy -fno-builtin-strlen -fno-builtin-calloc -fno-builtin-malloc -fno-builtin-free")
add_cflags("-fjump-tables -ftree-switch-conversion")

set_dependir("$(builddir)/.deps")
set_objectdir("$(builddir)/.objs")
set_policy("build.across_targets_in_parallel", false)

-- ============================================================================
-- 公共 include 路径 (相对 ROOT)
-- 因为 add_includedirs(ROOT, {public=true}) 已在文件顶部调用,
-- 此处写 "app/port" 即可, xmake 会从 ROOT 开始查找
--
-- ★ spislave conf 必须放在 app/port 前面, 否则 #include "luat_conf_bsp.h"
--   会先找到 app/port/luat_conf_bsp.h (默认 AIR6208, airlink 宏全注释掉)
-- ============================================================================
add_includedirs(path.join(SCRIPT_DIR, "conf"), {public = true})
add_includedirs(path.join(ROOT, "app/port"), {public = true})
add_includedirs(path.join(ROOT, "include"), {public = true})
add_includedirs(path.join(ROOT, "include/app"), {public = true})
add_includedirs(path.join(ROOT, "include/driver"), {public = true})
add_includedirs(path.join(ROOT, "include/os"), {public = true})
add_includedirs(path.join(ROOT, "include/bt"), {public = true})
add_includedirs(path.join(ROOT, "include/platform"), {public = true})
add_includedirs(path.join(ROOT, "platform/common/params"), {public = true})
add_includedirs(path.join(ROOT, "include/wifi"), {public = true})
add_includedirs(path.join(ROOT, "include/arch/xt804"), {public = true})
add_includedirs(path.join(ROOT, "include/arch/xt804/csi_core"), {public = true})
add_includedirs(path.join(ROOT, "include/net"), {public = true})
add_includedirs(path.join(ROOT, "platform/inc"), {public = true})
add_includedirs(path.join(ROOT, "src/os/rtos/include"), {public = true})
add_includedirs(path.join(ROOT, "src/network/lwip2.1.3/include"), {public = true})
add_includedirs(path.join(ROOT, "src/network/api_wm"), {public = true})
add_includedirs(path.join(ROOT, "include/arch/xt804/csi_dsp"), {public = true})
add_includedirs(path.join(ROOT, "platform/sys"), {public = true})

-- LuatOS 仓头文件 (luatos 是绝对路径, 因为它在 repo 之外)
add_includedirs(luatos.."components/airlink/include", {public = true})
add_includedirs(luatos.."components/printf", {public = true})
add_includedirs(luatos.."components/crypto")
add_includedirs(luatos.."components/miniz")
add_includedirs(luatos.."components/serialization/protobuf")
add_includedirs(luatos.."components/nanopb/include", {public = true})
add_includedirs(luatos.."components/soc_service/include", {public = true})
add_includedirs(luatos.."components/hmeta", {public = true})
add_includedirs(luatos.."components/network/adapter", {public = true})
add_includedirs(luatos.."components/network/adapter_lwip2", {public = true})
add_includedirs(luatos.."components/network/netdrv/include", {public = true})
add_includedirs(luatos.."components/network/ulwip/include", {public = true})
add_includedirs(luatos.."components/common", {public = true})
add_includedirs(luatos.."components/lfs")
add_includedirs(luatos.."components/fskv")
add_includedirs(luatos.."luat/include", {public = true})
add_includedirs(luatos.."lua/include", {public = true})
add_includedirs(luatos.."components/wlan", {public = true})
add_includedirs(luatos.."components/device/spi_slave/include", {public = true})
add_includedirs(luatos.."components/i2c-tools", {public = true})

add_ldflags(" -Wl,--wrap=localtime ", {force = true})
add_ldflags(" -Wl,--wrap=gmtime ", {force = true})
add_ldflags(" -Wl,--wrap=mktime ", {force = true})
add_ldflags(" -Wl,--wrap=printf ", {force = true})

-- wmarch 使用预编译的 lib/libwmarch.a, 不在 spislave 中重复编译
-- ============================================================================
-- 静态库: app (src/app, 网络应用层辅助)
-- ============================================================================
target("app")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    add_includedirs(path.join(ROOT, "app/port"), {public = true})
    add_files(path.join(ROOT, "src/app/**.c"))
    remove_files(path.join(ROOT, "src/app/btapp/**.c"))
target_end()

-- ============================================================================
-- 静态库: freertos (rtos 适配)
-- ============================================================================
target("freertos")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    set_targetdir("$(builddir)/lib")
    add_files(luatos.."luat/freertos/*.c")
    add_files(luatos.."components/rtos/freertos/*.c")
    add_includedirs(path.join(ROOT, "include"), {public = true})
    add_includedirs(path.join(ROOT, "include/arch/xt804"), {public = true})
    add_includedirs(path.join(ROOT, "include/arch/xt804/csi_core"), {public = true})
    add_includedirs(path.join(ROOT, "include/os"), {public = true})
    add_includedirs(path.join(ROOT, "src/os/rtos/include"), {public = true})
    add_includedirs(path.join(ROOT, "platform/sys"), {public = true})
    add_includedirs(path.join(ROOT, "app/port"), {public = true})
    add_includedirs(luatos.."luat/include", {public = true})
target_end()

-- ============================================================================
-- 静态库: miniz (FOTA 解压, 但 spislave 无 script 区, 仅留作兼容)
-- ============================================================================
target("miniz")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    add_files(luatos.."components/miniz/*.c")
    add_includedirs(path.join(ROOT, "app/port"))
    add_includedirs(path.join(ROOT, "include"))
    add_includedirs(luatos.."luat/include")
    add_includedirs(luatos.."components/miniz")
    set_targetdir("$(builddir)/lib")
target_end()

-- ============================================================================
-- 静态库: lua (C API 符号, 不启动 VM, 适配层需要)
-- ============================================================================
target("lua")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    set_targetdir("$(builddir)/lib")
    add_includedirs(luatos.."lua/include")
    add_includedirs(luatos.."luat/include")
    add_includedirs(path.join(ROOT, "app/port"))
    add_includedirs(path.join(ROOT, "include"))
    add_files(luatos.."lua/src/*.c")
    remove_files(luatos.."lua/src/lua.c")
    remove_files(luatos.."lua/src/luac.c")
target_end()

-- ============================================================================
-- 静态库: mbedtls (TLS 已禁用, 仅提供符号链接)
-- ============================================================================
target("mbedtls")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    set_targetdir("$(builddir)/lib")
    add_includedirs(path.join(ROOT, "app/port"))
    add_includedirs(path.join(ROOT, "include"))
    add_includedirs(luatos.."lua/include")
    add_includedirs(luatos.."luat/include")
    add_files(luatos.."components/mbedtls/library/*.c")
target_end()

-- ============================================================================
-- 静态库: network (lwip + netdrv + ulwip + airlink + soc_service)
-- ============================================================================
target("network_spislave")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    add_includedirs(path.join(SCRIPT_DIR, "conf"))  -- spislave conf BEFORE app/port for airlink macros
    add_includedirs(path.join(ROOT, "app/port"))
    add_includedirs(path.join(ROOT, "include"))
    add_includedirs(luatos.."luat/include", {public = true})

    add_files(path.join(ROOT, "src/network/**.c"))
    add_files(path.join(ROOT, "app/network/**.c"))
    add_includedirs(path.join(ROOT, "src/app/dhcpserver"))
    add_includedirs(path.join(ROOT, "src/app/dnsserver"))
    add_includedirs(path.join(ROOT, "src/app/oneshotconfig"))

    add_includedirs(luatos.."components/network/adapter", {public = true})
    add_files(luatos.."components/network/adapter/*.c")
    remove_files(luatos.."components/network/adapter/luat_lib_socket.c")
    remove_files(luatos.."components/network/adapter/luat_net_adapter.c")
    add_includedirs(luatos.."components/network/adapter_lwip2", {public = true})

    add_includedirs(luatos.."components/network/netdrv/include", {public = true})
    add_files(luatos.."components/network/netdrv/**.c")

    add_includedirs(luatos.."components/hmeta", {public = true})
    add_includedirs(luatos.."components/bluetooth/include", {public = true})
    add_includedirs(luatos.."components/ethernet/common", {public = true})
    add_includedirs(luatos.."components/airlink/include", {public = true})
    add_files(luatos.."components/airlink/**.c")
    remove_files(luatos.."components/airlink/binding/*.c")
    add_files(luatos.."components/airlink/src/task/*.c")

    add_includedirs(luatos.."components/network/ulwip/include", {public = true})

    add_includedirs(luatos.."components/soc_service/include", {public = true})
    add_files(luatos.."components/soc_service/**.c")

    add_includedirs(luatos.."components/nanopb/include", {public = true})
    add_files(luatos.."components/nanopb/src/*.c")
target_end()

-- ============================================================================
-- 静态库: common (公共辅助)
-- ============================================================================
target("common")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    set_targetdir("$(builddir)/lib")
    add_files(luatos.."components/common/*.c")
    add_includedirs(path.join(ROOT, "app/port"), {public = true})
    add_includedirs(path.join(ROOT, "include"), {public = true})
    add_includedirs(luatos.."luat/include", {public = true})
    add_includedirs(luatos.."components/common", {public = true})
target_end()

-- ============================================================================
-- 静态库: vfs + lfs + fskv (FSKV 用 lfs 实现)
-- ============================================================================
target("vfs")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    set_targetdir("$(builddir)/lib")
    add_files(luatos.."luat/vfs/*.c")
    remove_files(luatos.."luat/vfs/luat_fs_posix.c")
    add_includedirs(path.join(ROOT, "app/port"), {public = true})
    add_includedirs(path.join(ROOT, "include"), {public = true})
    add_includedirs(luatos.."luat/include", {public = true})
    add_includedirs(luatos.."components/lfs")
    add_includedirs(luatos.."components/fskv")
target_end()

target("lfs")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    set_targetdir("$(builddir)/lib")
    add_files(luatos.."components/lfs/*.c")
    add_includedirs(path.join(ROOT, "app/port"), {public = true})
    add_includedirs(path.join(ROOT, "include"), {public = true})
    add_includedirs(luatos.."luat/include", {public = true})
target_end()

target("fskv")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    set_targetdir("$(builddir)/lib")
    add_files(luatos.."components/fskv/*.c")
    add_includedirs(path.join(ROOT, "app/port"), {public = true})
    add_includedirs(path.join(ROOT, "include"), {public = true})
    add_includedirs(luatos.."luat/include", {public = true})
    add_includedirs(luatos.."components/fskv", {public = true})
target_end()

-- ============================================================================
-- 静态库: hmeta (设备元数据, airlink devinfo 需要)
-- ============================================================================
target("hmeta")
    set_kind("static")
    set_plat("cross")
    set_arch("c-sky")
    set_targetdir("$(builddir)/lib")
    add_files(luatos.."components/hmeta/*.c")
    add_includedirs(path.join(ROOT, "app/port"), {public = true})
    add_includedirs(path.join(ROOT, "include"), {public = true})
    add_includedirs(luatos.."luat/include", {public = true})
    add_includedirs(luatos.."components/hmeta", {public = true})
target_end()

-- ============================================================================
-- 主 binary: air6010_spislave
-- ============================================================================
target("air6010_spislave")
    set_kind("binary")
    set_plat("cross")
    set_arch("c-sky")
    set_targetdir("$(builddir)/out")

    on_load(function (target)
        -- buildx.lua 已拷贝到本目录, 直接用模块名 import (与原版 xmake.lua 一致)
        import("buildx")
        local bsp_path = path.join(SCRIPT_DIR, "conf", "luat_conf_bsp.h")
        -- partition_dir 指向 repo 根, 让 buildx 能找到 partition/AIR6010.csv
        local chip = buildx.chip(bsp_path, path.join(ROOT, "partition"))
        print(string.format("[spislave] BSP conf: %s, target=%s", bsp_path, chip.target_name))

        -- 生成 air6010.ld (HSPI 0x2400 buffer 完整包入 RAM_END 之外)
        local ld_data = io.readfile(path.join(ROOT, "ld", "xt804.ld"))
        local ld_data_n = ld_data:gsub("SRAM_O", string.format("0x%X", chip.flash_app_offset))
        ld_data_n = ld_data_n:gsub("SRAM_L", string.format("0x%X", chip.flash_app_size))
        ld_data_n = ld_data_n:gsub("RAM_END", "0x2002A400")
        ld_data_n = ld_data_n:gsub("__min_heap_size = 0x100", "__min_heap_size = 0x4000")
        local ld_out = path.join(ROOT, "ld", "air6010.ld")
        io.writefile(ld_out, ld_data_n)
        print(string.format("[spislave] Generated %s: ORIGIN=0x%X LEN=0x%X RAM_END=0x2002A400",
            ld_out, chip.flash_app_offset, chip.flash_app_size))

        local TARGET_NAME = chip.target_name
        target:set("filename", TARGET_NAME..".elf")

        -- 链接器 flags: 仅 libwmarch.a (无 wifi/BT/GT 库)
        local lib_wmarch = path.join(ROOT, "lib/libwmarch.a")
        local lib_wlan   = path.join(ROOT, "lib/libwlan.a")
        local ld_script  = path.join(ROOT, "ld/air6010.ld")
        target:add("ldflags",
            flto
            .. "-Wl,--gc-sections -Wl,-zmax-page-size=1024 "
            .. "-Wl,--whole-archive " .. lib_wmarch .. " " .. lib_wlan .. " -Wl,--no-whole-archive "
            .. "-mcpu=ck804ef -nostartfiles -mhard-float -lm "
            .. "-Wl,-T" .. ld_script .. " "
            .. "-Wl,-ckmap=$(builddir)/out/" .. TARGET_NAME .. ".map ",
            {force = true})
    end)

    add_deps("app", "freertos", "lua", "mbedtls", "miniz", "network_spislave", "common", "vfs", "lfs", "fskv", "hmeta")

    -- spislave 入口
    add_files("main.c")

    -- BSP 公共源
    add_files(path.join(ROOT, "app/port/*.c"))
    add_files(path.join(ROOT, "platform/sys/*.c"))
    add_files(path.join(ROOT, "platform/drivers/**.c"))
    add_files(path.join(ROOT, "src/os/**.c"))
    add_files(path.join(ROOT, "src/os/**.S"))
    add_files(path.join(ROOT, "platform/common/**.c"))
    remove_files(path.join(ROOT, "platform/common/wifi/**.c"))

    -- 显式 include SPI slave 适配层(air6208 默认会 remove, spislave 必须用)
    add_files(path.join(ROOT, "app/port/luat_spi_slave_air101.c"))

    -- 排除不需要的 BSP 文件
    remove_files(path.join(ROOT, "app/port/luat_audio_air101.c"))
    remove_files(path.join(ROOT, "app/port/luat_lcd_air101.c"))
    remove_files(path.join(ROOT, "app/port/luat_lcdseg_air101.c"))
    remove_files(path.join(ROOT, "app/port/luat_i2s_air101.c"))
    remove_files(path.join(ROOT, "app/port/luat_pwm_air101.c"))
    remove_files(path.join(ROOT, "app/port/luat_nimble_air101.c"))
    remove_files(path.join(ROOT, "app/port/luat_sdio_air101.c"))
    remove_files(path.join(ROOT, "app/port/luat_sfd_onchip_air101.c"))
    remove_files(path.join(ROOT, "app/port/luat_wlan_raw_air101.c"))
    remove_files(path.join(ROOT, "app/port/luat_shell_air101.c"))
    remove_files(path.join(ROOT, "app/port/luat_ota_air101.c"))
    remove_files(path.join(ROOT, "app/port/luat_touchkey_air101.c"))
    remove_files(path.join(ROOT, "app/port/luat_ml306_*.c"))
    -- spislave 无 script/fs 分区, 用自实现 stub 替代 luat_fs_air101.c
    remove_files(path.join(ROOT, "app/port/luat_fs_air101.c"))

    -- LuatOS 仓: 精简到只 airlink 必需 (不要 lua module bindings)
    -- 模块文件在 luat/modules/ 都是 Lua binding, 不需要
    add_files(luatos.."luat/weak/luat_spi_*.c")
    add_files(luatos.."luat/weak/luat_rtos_legacy_to_std.c")
    add_files(luatos.."luat/weak/luat_mem_weak.c")
    add_files(luatos.."components/printf/*.c")
    add_files(luatos.."components/crypto/*.c")
    add_files(luatos.."components/serialization/protobuf/*.c")

    -- spislave conf 必须在 include 路径前面
    add_includedirs(path.join(SCRIPT_DIR, "conf"), {public = true})

    -- ==========================================================================
    -- after_build: 生成 .fls 烧录文件
    -- ==========================================================================
    after_build(function (target)
        local bsp_path = path.join(SCRIPT_DIR, "conf", "luat_conf_bsp.h")
        import("buildx")
        local chip = buildx.chip(bsp_path, path.join(ROOT, "partition"))
        local TARGET_NAME = chip.target_name

        local sdk_dir = target:toolchains()[1]:sdkdir() .. "/"
        local out_dir = path.join("$(builddir)", "out")
        os.exec(sdk_dir .. "bin/csky-elfabiv2-objcopy -O binary " .. out_dir .. "/"..TARGET_NAME..".elf " .. out_dir .. "/"..TARGET_NAME..".bin")
        os.exec(sdk_dir .. "bin/csky-elfabiv2-size " .. out_dir .. "/"..TARGET_NAME..".elf")
        print("[spislave] " .. TARGET_NAME .. " binary built")

        local wm_tool = path.join(ROOT, "tools", "xt804", "wm_tool") .. (is_plat("windows") and ".exe" or "")
        local upgrade_addr = chip.flash_base + chip.partitions.fota.offset

        -- app image (it=1 means app image; ih=app header offset, ra=运行地址, ua=升级区)
        local app_image = "-fc 0 -it 1 -ih %x -ra %x -ua %x -nh 0 -un 0 -vs S01.00.01 -o $(builddir)/out/%s"
        app_image = string.format(app_image, chip.flash_app_offset - 1024, chip.flash_app_offset, upgrade_addr, TARGET_NAME)
        local cmd = wm_tool .. " -b $(builddir)/out/"..TARGET_NAME..".bin " .. app_image
        print("[spislave] " .. cmd)
        os.exec(cmd)

        -- secboot image (从通用 xt804_secboot.bin 打包)
        local sec_image = "-fc 0 -it 0 -ih 8002000 -ra 8002400 -ua %x -nh %x -un 0 -o " .. path.join(ROOT, "tools", "xt804", "%s_secboot")
        sec_image = string.format(sec_image, upgrade_addr, chip.flash_app_offset - 1024, TARGET_NAME)
        cmd = wm_tool .. " -b " .. path.join(ROOT, "tools", "xt804", "xt804_secboot.bin") .. " " .. sec_image
        print("[spislave] " .. cmd)
        os.exec(cmd)

        -- 合并成 .fls
        os.cp(path.join(ROOT, "tools", "xt804", TARGET_NAME.."_secboot.img"),
              "$(builddir)/out/"..TARGET_NAME..".fls")
        local img = io.readfile("$(builddir)/out/"..TARGET_NAME..".img", {encoding = "binary"})
        local fls = io.open("$(builddir)/out/"..TARGET_NAME..".fls", "a+")
        if fls then fls:write(img) fls:close() end

        local secboot_size = io.readfile(path.join(ROOT, "tools", "xt804", TARGET_NAME.."_secboot.img"), {encoding = "binary"}):len()
        local app_size = io.readfile("$(builddir)/out/"..TARGET_NAME..".img", {encoding = "binary"}):len()
        print(string.format("[spislave] %s.fls ready: secboot=%d bytes, app=%d bytes, total=%d bytes",
            TARGET_NAME, secboot_size, app_size, secboot_size + app_size))
    end)
target_end()
