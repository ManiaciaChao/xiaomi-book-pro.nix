# SPDX-License-Identifier: GPL-2.0-only
{ libfprintSource }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.xiaomi-book-pro;
in
{
  config = lib.mkIf (cfg.enable && cfg.fingerprint.enable) {
    nixpkgs.overlays = [ (import ../overlays/libfprint.nix { inherit libfprintSource; }) ];
    services.fprintd.enable = true;
    services.udev.packages = [ pkgs.libfprint ];
  };
}
