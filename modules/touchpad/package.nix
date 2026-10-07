# SPDX-License-Identifier: GPL-2.0-only
{
  lib,
  kernel,
  kernelModuleMakeFlags,
}:
kernel.stdenv.mkDerivation {
  pname = "hid-multitouch-confidence";
  version = "0.1-${kernel.version}";
  src = kernel.src;
  unpackPhase = ''
    runHook preUnpack
    mkdir source
    for file in hid-multitouch.c hid-ids.h hid-haptic.h; do
      tar -xOf "$src" --wildcards "*/drivers/hid/$file" > "source/$file"
    done
    sourceRoot=source
    runHook postUnpack
  '';
  patches = [ ./confidence.patch ];
  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];
  buildPhase = ''
    runHook preBuild
    if ! grep -qx 'CONFIG_HID_MULTITOUCH=m' ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build/.config; then
      echo 'The touchpad replacement requires CONFIG_HID_MULTITOUCH=m, not a built-in driver.' >&2
      exit 1
    fi
    printf '%s\n' 'obj-m += hid-multitouch.o' > Makefile
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M="$PWD" ${lib.escapeShellArgs kernelModuleMakeFlags} modules
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm644 hid-multitouch.ko \
      "$out/lib/modules/${kernel.modDirVersion}/updates/hid-multitouch.ko"
    mkdir -p "$out/etc/depmod.d"
    printf '%s\n' 'override hid-multitouch * updates' > "$out/etc/depmod.d/hid-multitouch-confidence.conf"
    runHook postInstall
  '';
  meta = {
    description = "Firmware confidence palm reporting for BLTP7853 touchpads";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
