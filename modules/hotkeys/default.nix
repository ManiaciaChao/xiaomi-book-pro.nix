# SPDX-License-Identifier: GPL-2.0-only
{
  config,
  lib,
  ...
}:
let
  cfg = config.hardware.xiaomi-book-pro;
in
{
  options.hardware.xiaomi-book-pro.hotkeys = {
    backend = lib.mkOption {
      type = lib.types.enum [
        "redmi"
        "bitland"
      ];
      default = "redmi";
      description = "WMI backend: stable hotkey-only Redmi driver or experimental TM2424 Bitland driver.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = config.boot.kernelPackages.callPackage (
        if cfg.hotkeys.backend == "bitland" then ./bitland/package.nix else ./package.nix
      ) { };
      description = "Selected patched WMI module built for the configured kernel.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.hotkeys.enable) {
    boot.extraModulePackages = [ cfg.hotkeys.package ];
    boot.kernelModules = [
      (if cfg.hotkeys.backend == "bitland" then "bitland_mifs_wmi" else "redmi_wmi")
    ];
    # Both drivers match the same event GUID; only the selected backend may bind.
    boot.blacklistedKernelModules = [
      (if cfg.hotkeys.backend == "bitland" then "redmi_wmi" else "bitland_mifs_wmi")
    ];
  };
}
