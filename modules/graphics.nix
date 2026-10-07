# SPDX-License-Identifier: GPL-2.0-only
{ config, lib, ... }:
let
  cfg = config.hardware.xiaomi-book-pro;
  kernelVersion = config.boot.kernelPackages.kernel.version;
in
{
  options.hardware.xiaomi-book-pro.graphics = {
    forceProbe.enable = lib.mkEnableOption "forced Xe probing for GPU b080" // {
      # Panther Lake is enabled by default in Xe starting with Linux 6.17.
      default = lib.versionOlder kernelVersion "6.17";
    };
    psrWorkaround.enable = lib.mkEnableOption "the panel self-refresh workaround" // {
      default = true;
    };
  };

  config = lib.mkIf (cfg.enable && cfg.graphics.enable) {
    # Actual GPU ID on the tested unit is 8086:b080.
    boot.kernelParams =
      lib.optionals cfg.graphics.forceProbe.enable [
        "xe.force_probe=b080"
        "i915.force_probe=!b080"
      ]
      ++ lib.optional cfg.graphics.psrWorkaround.enable "xe.enable_psr=0";
  };
}
