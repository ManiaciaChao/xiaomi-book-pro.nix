# SPDX-License-Identifier: GPL-2.0-only
{ config, lib, ... }:
let
  cfg = config.hardware.xiaomi-book-pro;
  kernelVersion = config.boot.kernelPackages.kernel.version;
in
{
  options.hardware.xiaomi-book-pro.keyboard.workaround.enable =
    lib.mkEnableOption "the nopnp/dumbkbd keyboard workaround"
    // {
      # Xiaomi's atkbd fix first appeared in 7.2-rc7; use stable 7.2 as the
      # default boundary. Pair nopnp with dumbkbd as a local policy, not an
      # independently established PnP fix. Backports can override this default.
      default = lib.versionOlder kernelVersion "7.2";
    };

  config = lib.mkIf (cfg.enable && cfg.keyboard.enable && cfg.keyboard.workaround.enable) {
    boot.kernelParams = [
      "i8042.nopnp=1"
      "i8042.dumbkbd=1"
    ];
  };
}
