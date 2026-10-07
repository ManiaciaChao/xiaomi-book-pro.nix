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
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = config.boot.kernelPackages.callPackage ./package.nix { };
      description = "Patched redmi-wmi module built for the configured kernel.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.hotkeys.enable) {
    boot.extraModulePackages = [ cfg.hotkeys.package ];
    boot.kernelModules = [ "redmi_wmi" ];
    # Both drivers match the same event GUID. Keep the hotkey-only driver in
    # charge until the Bitland driver has the complete TM2424 adaptation.
    boot.blacklistedKernelModules = [ "bitland_mifs_wmi" ];
  };
}
