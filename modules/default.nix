# SPDX-License-Identifier: GPL-2.0-only
{ libfprintSource }:
{
  config,
  lib,
  ...
}:
let
  cfg = config.hardware.xiaomi-book-pro;
  enabledByDefault = description: lib.mkEnableOption description // { default = true; };
in
{
  imports = [
    ./keyboard.nix
    ./graphics.nix
    ./touchpad.nix
    ./hotkeys
    (import ./fingerprint.nix { inherit libfprintSource; })
  ];

  options.hardware.xiaomi-book-pro = {
    enable = lib.mkEnableOption "Xiaomi Book Pro 14 (2026), TM2424 hardware support";
    keyboard.enable = enabledByDefault "version-gated keyboard workarounds";
    graphics.enable = enabledByDefault "version-gated Xe and panel workarounds";
    fingerprint.enable = enabledByDefault "Goodix 27c6:6890 fingerprint support";
    touchpad.enable = enabledByDefault "BLTP7853 touchpad confidence and palm quirks";
    hotkeys.enable = enabledByDefault "the standalone redmi-wmi hotkey replacement";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.nixpkgs.hostPlatform.system == "x86_64-linux";
        message = "xiaomi-book-pro.nix supports only the x86_64-linux TM2424 profile.";
      }
    ];
  };
}
