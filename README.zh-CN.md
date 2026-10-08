# xiaomi-book-pro.nix

[English](README.md) | [简体中文](README.zh-CN.md)

为 **小米笔记本 Pro 14（2026），主板型号 TM2424** 提供 NixOS 硬件支持。

这个 flake 提供硬件兼容性修复，不改变你的桌面、磁盘布局、引导程序或内核选择。
替换驱动按独立模块构建，无需重新编译整个内核。

## 快速开始

在 flake 中添加输入：

```nix
inputs.xiaomi-book-pro = {
  url = "github:ManiaciaChao/xiaomi-book-pro.nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

然后在能够访问 `inputs` 的 NixOS 配置中导入并启用模块：

```nix
imports = [ inputs.xiaomi-book-pro.nixosModules.tm2424 ];
hardware.xiaomi-book-pro.enable = true;
```

重新构建 NixOS 配置并重启，以加载内核改动。
`nixosModules.default` 是 `tm2424` 的别名。

## 支持哪些功能

启用硬件配置模块后，以下功能组默认全部启用。

| 功能 | 支持内容 |
| --- | --- |
| 键盘 | Linux < 7.2 时启用配对的 `i8042.nopnp` / `i8042.dumbkbd` 修复 |
| 显卡与屏幕 | Linux < 6.17 时为 GPU `b080` 启用 force-probe；OLED PSR 修复 |
| 指纹 | 为 Goodix `27c6:6890` 提供 libfprint 支持，并启用 fprintd |
| 触摸板 | 为 `347D:7853` 适配 confidence／掌触处理及压力阈值 |
| 厂商按键 | 通过替换 WMI 驱动提供 AI／Mi 键的按下和释放事件 |

应用快捷键和桌面动作由你自行配置。

## 配置选项

可以关闭不需要的功能组：

```nix
hardware.xiaomi-book-pro = {
  enable = true;
  keyboard.enable = false;
  graphics.enable = false;
  fingerprint.enable = false;
  touchpad.enable = false;
  hotkeys.enable = false;
};
```

内核版本只决定修复的默认值，不限制手动设置。
遇到回移补丁或回归问题时，可以单独覆盖：

```nix
hardware.xiaomi-book-pro = {
  keyboard.workaround.enable = false; # 默认：内核 < 7.2
  graphics.forceProbe.enable = false; # 默认：内核 < 6.17
  graphics.psrWorkaround.enable = true; # 默认：true
};
```

### 触摸板

```nix
hardware.xiaomi-book-pro.touchpad = {
  mode = "driver"; # 默认；也可选择 "udev" 或 "none"
  pressureWorkaround.enable = true;
};
```

- **driver**：替换 `hid-multitouch.ko`，提供基于 confidence 位的掌触报告。
- **udev**：通过 `quirks=64` 覆盖，丢弃低置信度报告。
- **none**：不改变驱动的 confidence 行为。如果也不希望调整压力阈值，
  请同时关闭 `pressureWorkaround.enable`。

驱动模式要求 `CONFIG_HID_MULTITOUCH=m`，对触点卡住问题的改善仍需运行验证。
请重启后测试，不要卸载正在使用的触摸板驱动。

### 实验性 Bitland 后端

快捷键后端默认为 `redmi`。如需尝试 Bitland：

```nix
hardware.xiaomi-book-pro.hotkeys.backend = "bitland";
```

Bitland 添加麦克风、投屏和设置键映射，并提供 TM2424 的固件电源模式控制：

- 标准 Linux 电源配置对应 **Quiet / Auto / Full-speed**。
- 小米原生 **Quiet / Auto / Full-speed / Turbo / Eco** 模式通过控制设备的
  `performance_mode` sysfs 属性提供。
- Turbo 和 Eco 在标准 platform-profile 接口中显示为 `custom`。

此后端要求 `CONFIG_BITLAND_MIFS_WMI=m`。补丁已针对 Linux 7.2.9 测试，
其他版本可能需要适配。Quiet 和 Turbo 模式已通过初步挂起／恢复测试，
但仍需要更广泛的验证。用法见 [Bitland 使用与测试笔记](docs/bitland.md)（英文）。

## 兼容性注意事项

- 本模块针对 TM2424 和上述硬件 ID，不适用于所有小米笔记本。
- 请使用足够新的内核和图形用户态组件。
- 启用 Secure Boot 模块签名强制检查时，可能需要为替换模块签名。
- 指纹软件包只构建 `goodixmoc`，其他指纹设备可能需要不同配置。
  如果只需要覆盖软件包，可使用 `overlays.default`。

## 开发与文档

```sh
nix flake check
nix build .#hotkeys  # 默认 WMI 驱动
nix build .#bitland # 实验性 WMI 驱动
nix build .#touchpad
nix fmt
```

独立构建使用本项目的 `linuxPackages_latest`；导入 NixOS 模块时使用你配置的内核。
求值检查不能代替实际硬件测试。

进一步阅读（英文）：

- [硬件调查](docs/investigation.md)
- [快捷键调查](docs/hotkeys.md)
- [Bitland 调查与运行检查](docs/bitland.md)

## 许可证

Nix 配置、测试、文档和非 Bitland 内核补丁使用 GPL-2.0-only。
Bitland 补丁保留上游驱动的 GPL-2.0-or-later 许可。全文见 [LICENSE](LICENSE)。
