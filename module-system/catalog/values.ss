;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: lightweight module value catalog constructors for syntax paths.
;;; Invariant: catalog construction never evaluates modules or loads runtimes.

(import (only-in :clan/poo/object .o)
        (only-in :yuanxu/module-system/config yuanxu-module-kind=?))

(export yuanxu-module-catalog
        yuanxuModuleCatalog)

;;; Boundary: value catalog is a user-facing catalog, separate from source catalog.
;; : (-> [PooModuleDescriptor] POOObject)
(def yuanxu-module-value-catalog-kind "yuanxu.modules.value-catalog.v1")

(def (yuanxu-module-catalog . module-values)
  (.o kind: yuanxu-module-value-catalog-kind
      modules: module-values))

;; : (-> [PooModuleDescriptor] POOObject)
(def (yuanxuModuleCatalog . module-values)
  (apply yuanxu-module-catalog module-values))
