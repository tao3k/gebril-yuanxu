;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; One reader's source associations and generation-local counters.
(import (only-in :yuanxu/module-system/source/compiler-tools module-compiler-tools)
        (only-in :yuanxu/module-system/source/reader-support source-observation-rows))
(export (struct-out reader-session) (struct-out candidate-support) new-reader-session)

;; One unpublished operation's support, released after its recording frame.
(defstruct candidate-support (guards tools tool-rows open? epoch-current metadata-current) final: #t)

(defstruct reader-session
  (guards dependencies refused? evaluated-interface-bindings
   kernel-contexts kernel-inputs kernel-source-count kernel-owners kernel-data
   kernel-initializers preparations public-prepared-count publication-prepared-count
   candidate tool-contexts tool-paths tool-dependencies tool-observations compiler-contexts
   interpreter-observations tool-rows previous-context check-current check-current/closed open-boundary)
  final: #t)

(def (new-reader-session previous-context)
  (def guards '())
  (def dependencies (make-hash-table))
  (def kernel-contexts (make-hash-table))
  (def kernel-inputs (make-hash-table-eq))
  (def kernel-owners (make-hash-table-eq))
  (def kernel-data (make-hash-table-eq))
  (def kernel-initializers (make-hash-table-eq))
  (def preparations (make-hash-table))
  (def candidate (make-parameter #f))
  (defvalues (tool-contexts tool-paths tool-dependencies tool-observations compiler-contexts)
    (module-compiler-tools))
  (make-reader-session guards dependencies #f 0
    kernel-contexts kernel-inputs 0 kernel-owners kernel-data kernel-initializers
    preparations 0 0 candidate
    tool-contexts tool-paths tool-dependencies tool-observations compiler-contexts
    (hash->list tool-observations) (source-observation-rows tool-observations) previous-context #f #f #f))
