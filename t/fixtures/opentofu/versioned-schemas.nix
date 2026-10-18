# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
# Test package graph. Production callers supply their own locked package inputs.
{ pkgs }:
let
  package = args: import ./aws-5.100.0/package.nix ({ inherit pkgs; } // args);
  schema = provider: pkgs.callPackage
    ../../../modules/opentofu/nix/provider-schema.nix { inherit provider; };
in {
  parent = schema (package {
    version = "5.99.0";
    hash = "sha256:d77fc7e17730eb40cde656e67fc206e9d7ca2a346d9e1819e6f3bd71289207e2";
  });
  child = schema (package { });
}
