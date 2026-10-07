# SPDX-License-Identifier: GPL-2.0-only
{
  nixpkgs,
  pkgs,
  tm2424,
}:
let
  inherit (nixpkgs) lib;
  parametersFor =
    version: overrides:
    (lib.evalModules {
      modules = [
        ../modules/keyboard.nix
        ../modules/graphics.nix
        {
          options = {
            hardware.xiaomi-book-pro = {
              enable = lib.mkEnableOption "test profile";
              keyboard.enable = lib.mkEnableOption "test keyboard";
              graphics.enable = lib.mkEnableOption "test graphics";
            };
            boot.kernelPackages = lib.mkOption { type = lib.types.raw; };
            boot.kernelParams = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          };
          config = {
            hardware.xiaomi-book-pro = lib.recursiveUpdate {
              enable = true;
              keyboard.enable = true;
              graphics.enable = true;
            } overrides;
            boot.kernelPackages.kernel.version = version;
          };
        }
      ];
    }).config.boot.kernelParams;
  evaluateVersion = version: parametersFor version { };
  evaluateProfile =
    profile:
    (lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        tm2424
        {
          boot.kernelPackages = pkgs.linuxPackages_latest;
          hardware.xiaomi-book-pro = profile;
          system.stateVersion = "26.05";
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "/dev/null";
            fsType = "ext4";
          };
        }
      ];
    }).config;
  defaultProfile = evaluateProfile { enable = true; };
  bitland = evaluateProfile {
    enable = true;
    hotkeys.backend = "bitland";
  };
  enabled = evaluateProfile {
    enable = true;
    touchpad.mode = "udev";
  };
  disabled = evaluateProfile { enable = false; };
  driver = evaluateProfile {
    enable = true;
    touchpad.mode = "driver";
  };
  native = evaluateProfile {
    enable = true;
    touchpad.mode = "none";
    touchpad.pressureWorkaround.enable = false;
  };
  featuresDisabled = evaluateProfile {
    enable = true;
    keyboard.enable = false;
    graphics.enable = false;
    fingerprint.enable = false;
    touchpad.enable = false;
    hotkeys.enable = false;
  };
  psr = [ "xe.enable_psr=0" ];
  keyboard = [
    "i8042.nopnp=1"
    "i8042.dumbkbd=1"
  ];
  graphics = [
    "xe.force_probe=b080"
    "i915.force_probe=!b080"
  ];
  sorted = lib.sort builtins.lessThan;
in
assert sorted (evaluateVersion "6.16") == sorted (keyboard ++ graphics ++ psr);
assert sorted (evaluateVersion "6.17") == sorted (keyboard ++ psr);
assert sorted (evaluateVersion "7.1") == sorted (keyboard ++ psr);
assert sorted (evaluateVersion "7.2") == sorted psr;
assert sorted (evaluateVersion "7.2.9") == sorted psr;
assert
  sorted (
    parametersFor "7.2.9" {
      keyboard.workaround.enable = true;
      graphics.forceProbe.enable = true;
    }
  ) == sorted (keyboard ++ graphics ++ psr);
assert
  parametersFor "6.16" {
    keyboard.workaround.enable = false;
    graphics.forceProbe.enable = false;
  } == psr;
assert parametersFor "7.2.9" { graphics.psrWorkaround.enable = false; } == [ ];
assert enabled.services.fprintd.enable;
assert lib.elem "redmi_wmi" bitland.boot.blacklistedKernelModules;
assert !lib.elem "bitland_mifs_wmi" bitland.boot.blacklistedKernelModules;
assert lib.elem "bitland_mifs_wmi" bitland.boot.kernelModules;
assert !lib.elem "redmi_wmi" bitland.boot.kernelModules;
assert lib.elem bitland.hardware.xiaomi-book-pro.hotkeys.package bitland.boot.extraModulePackages;
assert bitland.hardware.xiaomi-book-pro.hotkeys.package.pname == "bitland-mifs-wmi-tm2424";
assert defaultProfile.hardware.xiaomi-book-pro.touchpad.mode == "driver";
assert lib.elem defaultProfile.hardware.xiaomi-book-pro.touchpad.package
  defaultProfile.boot.extraModulePackages;
assert !lib.hasInfix "347D:00007853" defaultProfile.services.udev.extraRules;
assert lib.hasInfix "347D:00007853" enabled.services.udev.extraRules;
assert lib.hasInfix "BLTP7853" enabled.environment.etc."libinput/local-overrides.quirks".text;
assert !lib.hasInfix "347D:00007853" driver.services.udev.extraRules;
assert lib.elem driver.hardware.xiaomi-book-pro.touchpad.package driver.boot.extraModulePackages;
assert lib.hasInfix "BLTP7853" driver.environment.etc."libinput/local-overrides.quirks".text;
assert !lib.hasInfix "347D:00007853" native.services.udev.extraRules;
assert !(native.environment.etc ? "libinput/local-overrides.quirks");
assert
  builtins.length native.boot.extraModulePackages == builtins.length enabled.boot.extraModulePackages;
assert lib.elem "bitland_mifs_wmi" enabled.boot.blacklistedKernelModules;
assert lib.elem enabled.hardware.xiaomi-book-pro.hotkeys.package enabled.boot.extraModulePackages;
assert !disabled.services.fprintd.enable;
assert !lib.elem "bitland_mifs_wmi" disabled.boot.blacklistedKernelModules;
assert !(disabled.environment.etc ? "libinput/local-overrides.quirks");
assert !featuresDisabled.services.fprintd.enable;
assert !lib.elem "xe.enable_psr=0" featuresDisabled.boot.kernelParams;
assert !lib.elem "bitland_mifs_wmi" featuresDisabled.boot.blacklistedKernelModules;
assert featuresDisabled.boot.extraModulePackages == [ ];
assert !(featuresDisabled.environment.etc ? "libinput/local-overrides.quirks");
pkgs.runCommand "xiaomi-book-pro-module-evaluation" { } ''
  touch "$out"
''
