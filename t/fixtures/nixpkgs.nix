# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
# Standalone Core qualification input, pinned to the recorded package source.
builtins.fetchTarball {
  url = "https://github.com/NixOS/nixpkgs/archive/9eac87a12312b8f60dd52e1c6e1a265f6fc7f5fc.tar.gz";
  sha256 = "sha256-d2xfDjnfRuf/xYGdu9VVRHiav/2w5hDL/5cw2TuVAXw=";
}
