;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Standalone public libraries that are not imported by the selected roles.
;;; Gerbil derives their transitive sources from these three entry points.
(def Build '("control-plane/api" "workload" "bundle-v1"))
