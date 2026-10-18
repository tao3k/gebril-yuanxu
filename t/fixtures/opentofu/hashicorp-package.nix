# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
# Fixed-checksum official packages for local qualification, not runtime policy.
{ pkgs, name, version, hash }:
assert pkgs.stdenv.hostPlatform.system == "aarch64-darwin";
pkgs.stdenvNoCC.mkDerivation {
  pname = "terraform-provider-${name}";
  inherit version;
  src = pkgs.fetchurl {
    url = "https://releases.hashicorp.com/terraform-provider-${name}/${version}/terraform-provider-${name}_${version}_darwin_arm64.zip";
    inherit hash;
  };
  nativeBuildInputs = [ pkgs.unzip ];
  unpackPhase = ''unzip "$src"'';
  installPhase = ''
    shopt -s nullglob
    binaries=(terraform-provider-${name}_v${version}*)
    test "''${#binaries[@]}" -eq 1
    directory="$out/libexec/terraform-providers/registry.terraform.io/hashicorp/${name}/${version}/darwin_arm64"
    mkdir -p "$directory"
    install -m755 "''${binaries[0]}" "$directory/"
  '';
  passthru.provider-source-address = "registry.terraform.io/hashicorp/${name}";
}
