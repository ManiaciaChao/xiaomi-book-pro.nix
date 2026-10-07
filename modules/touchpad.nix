# SPDX-License-Identifier: GPL-2.0-only
{ config, lib, ... }:
let
  cfg = config.hardware.xiaomi-book-pro;
in
{
  options.hardware.xiaomi-book-pro.touchpad = {
    mode = lib.mkOption {
      type = lib.types.enum [
        "driver"
        "udev"
        "none"
      ];
      default = "driver";
      description = "Confidence handling: patched driver palm reports, legacy udev filtering, or upstream behavior.";
    };
    pressureWorkaround.enable = lib.mkEnableOption "local libinput pressure and palm thresholds" // {
      default = true;
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = config.boot.kernelPackages.callPackage ./touchpad/package.nix { };
      defaultText = lib.literalExpression "config.boot.kernelPackages.callPackage ./touchpad/package.nix { }";
      description = "Standalone hid-multitouch replacement built for the selected kernel.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.touchpad.enable) {
    services.libinput.enable = lib.mkDefault true;
    boot.extraModulePackages = lib.mkIf (cfg.touchpad.mode == "driver") [ cfg.touchpad.package ];
    services.udev.extraRules = lib.mkIf (cfg.touchpad.mode == "udev") ''
      ACTION=="add", SUBSYSTEM=="hid", ENV{HID_ID}=="0018:0000347D:00007853", ATTR{quirks}="64"
      ACTION=="bind", SUBSYSTEM=="hid", ENV{HID_ID}=="0018:0000347D:00007853", ATTR{quirks}="64"
    '';
    environment.etc = lib.mkIf cfg.touchpad.pressureWorkaround.enable {
      "libinput/local-overrides.quirks".text = ''
        [BLTP7853 disable pressure palm]
        MatchName=BLTP7853:00 347D:7853 Touchpad
        MatchUdevType=touchpad
        AttrPressureRange=2:0
        AttrPalmPressureThreshold=1024
      '';
    };
  };
}
