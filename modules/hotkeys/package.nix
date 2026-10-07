# SPDX-License-Identifier: GPL-2.0-only
{
  lib,
  kernel,
  kernelModuleMakeFlags,
}:
kernel.stdenv.mkDerivation {
  pname = "redmi-wmi-hotkeys";
  version = "0.1-${kernel.version}";

  src = kernel.src;
  # Extract only the existing driver; do not build or unpack the whole kernel.
  unpackPhase = ''
    runHook preUnpack
    mkdir source
    tar -xOf "$src" --wildcards '*/drivers/platform/x86/redmi-wmi.c' > source/redmi-wmi.c
    sourceRoot=source
    runHook postUnpack
  '';
  patches = [ ./hotkeys.patch ];

  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];

  buildPhase = ''
    runHook preBuild
    printf '%s\n' 'obj-m += redmi-wmi.o' > Makefile
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M="$PWD" ${lib.escapeShellArgs kernelModuleMakeFlags} modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 redmi-wmi.ko \
      "$out/lib/modules/${kernel.modDirVersion}/updates/redmi-wmi.ko"
    mkdir -p "$out/etc/depmod.d"
    printf '%s\n' 'override redmi-wmi * updates' > "$out/etc/depmod.d/redmi-wmi-hotkeys.conf"
    runHook postInstall
  '';

  meta = {
    description = "Hotkey-only redmi-wmi fixes for Xiaomi Book Pro 14 (TM2424)";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
