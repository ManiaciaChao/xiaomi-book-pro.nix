# SPDX-License-Identifier: GPL-2.0-only
{
  lib,
  kernel,
  kernelModuleMakeFlags,
}:
kernel.stdenv.mkDerivation {
  pname = "bitland-mifs-wmi-tm2424";
  version = "0.1-${kernel.version}";
  src = kernel.src;
  unpackPhase = ''
    runHook preUnpack
    mkdir source
    tar -xOf "$src" --wildcards '*/drivers/platform/x86/bitland-mifs-wmi.c' > source/bitland-mifs-wmi.c
    sourceRoot=source
    runHook postUnpack
  '';
  patches = [ ./tm2424.patch ];
  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];
  buildPhase = ''
    runHook preBuild
    if ! grep -qx 'CONFIG_BITLAND_MIFS_WMI=m' ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build/.config; then
      echo 'The Bitland replacement requires CONFIG_BITLAND_MIFS_WMI=m.' >&2
      exit 1
    fi
    printf '%s\n' 'obj-m += bitland-mifs-wmi.o' > Makefile
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M="$PWD" ${lib.escapeShellArgs kernelModuleMakeFlags} modules
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm644 bitland-mifs-wmi.ko \
      "$out/lib/modules/${kernel.modDirVersion}/updates/bitland-mifs-wmi.ko"
    mkdir -p "$out/etc/depmod.d"
    printf '%s\n' 'override bitland-mifs-wmi * updates' > "$out/etc/depmod.d/bitland-mifs-wmi-tm2424.conf"
    runHook postInstall
  '';
  meta = {
    description = "Experimental Bitland WMI hotkey and platform-profile support for Xiaomi TM2424";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
}
