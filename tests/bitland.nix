# SPDX-License-Identifier: GPL-2.0-only
{ pkgs, bitland }:
pkgs.runCommand "bitland-tm2424-behavior-tests"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.stdenv.cc
      pkgs.patch
    ];
  }
  ''
    tar -xOf ${bitland.src} --wildcards '*/drivers/platform/x86/bitland-mifs-wmi.c' > bitland-mifs-wmi.c
    patch -p1 < ${../modules/hotkeys/bitland/tm2424.patch}
    python3 ${./extract-bitland-tests.py} bitland-mifs-wmi.c ${./bitland-harness.c} > test.c
    cc -std=gnu11 -Wall -Wextra -Werror -Wno-unused-parameter -Wno-missing-field-initializers test.c -o test
    ./test
    touch "$out"
  ''
