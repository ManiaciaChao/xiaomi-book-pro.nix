# SPDX-License-Identifier: GPL-2.0-only
{
  description = "NixOS hardware support for Xiaomi Book Pro 14 (2026), TM2424";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    libfprint-master = {
      url = "git+https://gitlab.freedesktop.org/libfprint/libfprint.git?rev=d79f157282085738ea8ffbe8c2ae96fb8b3ad831";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      tm2424 = import ./modules {
        libfprintSource = inputs.libfprint-master;
      };
      hotkeys = pkgs.linuxPackages_latest.callPackage ./modules/hotkeys/package.nix { };
      touchpad = pkgs.linuxPackages_latest.callPackage ./modules/touchpad/package.nix { };
    in
    {
      nixosModules = {
        inherit tm2424;
        default = tm2424;
      };
      overlays.default = import ./overlays/libfprint.nix {
        libfprintSource = inputs.libfprint-master;
      };
      packages.${system} = {
        inherit hotkeys touchpad;
        default = hotkeys;
      };
      checks.${system} = {
        inherit hotkeys touchpad;
        module-evaluation = import ./tests {
          inherit nixpkgs pkgs tm2424;
        };
      };
      formatter.${system} = pkgs.nixfmt-tree;
    };
}
