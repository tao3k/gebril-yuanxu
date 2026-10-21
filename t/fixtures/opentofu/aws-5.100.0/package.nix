# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
# Historical real-provider control. Production callers select their own package.
{ pkgs
, version ? "5.100.0"
, hash ? "sha256:bb64e8aff37becab373a1a0cc1080990785304141af42ed6aa3dd4913b000421"
}:
assert pkgs.stdenv.hostPlatform.system == "aarch64-darwin";
pkgs.stdenvNoCC.mkDerivation {
  pname = "terraform-provider-aws";
  inherit version;
  # The native fixed-output fetcher reports transfer counters to Nix's activity
  # stream. A curl builder's carriage-return display is not liveness evidence.
  # URL, expected content hash and archive name retain the same fixed output.
  # stdenv.fetchurlBoot can itself be replaced by a later curl bootstrap stage.
  # Use Nix's shipped fixed-output builder rather than inferring from its name.
  src = import <nix/fetchurl.nix> {
    system = pkgs.stdenv.hostPlatform.system;
    url = "https://releases.hashicorp.com/terraform-provider-aws/${version}/terraform-provider-aws_${version}_darwin_arm64.zip";
    inherit hash;
  };
  nativeBuildInputs = [ pkgs.unzip ];
  unpackPhase = ''unzip "$src"'';
  installPhase = ''
    directory="$out/libexec/terraform-providers/registry.terraform.io/hashicorp/aws/${version}/darwin_arm64"
    mkdir -p "$directory"
    install -m755 terraform-provider-aws_v${version}_x5 "$directory/terraform-provider-aws_v${version}_x5"
  '';
  passthru.provider-source-address = "registry.terraform.io/hashicorp/aws";
}
