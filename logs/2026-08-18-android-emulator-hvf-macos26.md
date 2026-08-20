# 2026-08-18 Android 模拟器在 macOS 26.6.1 上无法启用 hvf

> 历史记录：保留当时的排查证据与结论，不代表未来 emulator 版本仍存在该问题。Android 端的工程方案见 [android-migration](../docs/engineering/android-migration.md)。

## 现象

- Android Studio 下载 Pixel 8 / API 37 / Google APIs ARM 64 v8a 系统镜像时报 `意外的文件结尾`（下载中断，产生残缺目录）。
- 用命令行补全镜像、创建 AVD 后，模拟器启动异常：
  - 日志反复出现 `qemu_mprotect__osdep: mprotect failed: Permission denied`，首次启动直接 SIGSEGV 崩溃。
  - 即使强制 `-qemu -accel hvf`，guest 也不启动（进程 0% CPU、adb 一直 `offline`）。

## 环境

- 机器：MacBook Air M1（arm64），macOS 26.6.1 (25G76)，8GB 内存（空闲时常 <100MB）。
- emulator 37.1.11.0（SDK Manager 当前最新），cmdline-tools 10.0。
- AVD：`Pixel_8_API_37`，`system-images;android-37.0;google_apis;arm64-v8a`。

## 排查过程

1. 下载失败：`sdkmanager` 重新安装镜像成功（包名 `android-37.0` 非标准，avdmanager 解析成 "API 0"）。
2. `emulator -accel-check` 返回 accel 可用，`kern.hv_support=1`、`kern.hv_disable=0`，系统 HVF 正常。
3. `-verbose` 日志显示 `CPU Acceleration: working`，但随后 `feature check for hvf` 分支不通过，qemu 启动参数不含 `-enable-hvf`，退回 TCG → JIT `mprotect failed` → 崩溃/挂起。
4. 逐一尝试：重签 qemu 加 `allow-jit`/`hypervisor` entitlement、`-feature HVF`、`-qemu -accel hvf`、`-cpu host|Host|max`，均无效。
5. 还原用原始签名 emulator 复现，同样失败 → 排除签名问题。
6. 读 emulator 源码（`android/emulation/CpuAccelerator.cpp` 的 `ProbeHVF`、`main-common.c` 的 `handleCpuAcceleration`）：`ProbeHVF` 在 Apple Silicon 上恒返回 READY，判定关键在 `feature_is_enabled(HVF)` 与 qemu 侧 `hv_vm_create` 初始化。qemu 侧 HVF 初始化在 macOS 26.6.1 上失败。

## 根因

emulator 37.1.11 与 macOS 26.6.1 存在兼容性缺陷：qemu 的 Hypervisor.framework 初始化在该系统上失败，模拟器只能退回 TCG 纯软件模拟；而 TCG 的 JIT 又受 macOS 内存保护限制无法执行（`mprotect failed`）。两者叠加导致 API 37 镜像无法启动。用户侧无 workaround。

## 结论与后续

- Android 镜像、AVD、APK（`android/app/build/outputs/apk/debug/app-debug.apk`，60MB，含正确 Supabase 公开配置）均已就绪，唯一阻塞项是模拟器本身。
- 后续先检查 emulator 是否有更新（`sdkmanager --list | grep emulator`）；若无，可在稳定版 macOS（如 26.0.x）或物理 Android 设备上运行。
- 注意：emulator 二进制被重签过，已通过 `sdkmanager --uninstall/--install emulator` 恢复为 Google 原始签名。
- 系统镜像包名 `android-37.0` 会让 avdmanager 显示 "Android API 0"，属显示 bug，不影响使用。
