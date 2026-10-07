# SPDX-License-Identifier: GPL-2.0-only
{ libfprintSource }:
final: prev: {
  libfprint = prev.libfprint.overrideAttrs (old: {
    # Pinned upstream source includes Goodix MOC 27c6:6890 support.
    # WIP: remove this source override when the consumer's release includes it.
    version = "${old.version}-master-d79f157";
    src = libfprintSource;
    patches = builtins.filter (patch: !prev.lib.hasSuffix "-focal-077a-079a.patch" (toString patch)) (
      old.patches or [ ]
    );
    mesonFlags = builtins.filter (flag: flag != "-Ddrivers=all") old.mesonFlags ++ [
      "-Ddrivers=goodixmoc"
    ];
  });
  fprintd = prev.fprintd.override {
    libfprint = final.libfprint;
  };
}
