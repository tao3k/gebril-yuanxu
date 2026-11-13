;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; One reader's source associations and generation-local counters.
(import (only-in :tao3k/yuanxu/module-system/source/import-provenance module-import-provenance)
        (only-in :tao3k/yuanxu/module-system/source/reader-support source-observation-rows))
(export (struct-out reader-session) (struct-out candidate-support) new-reader-session
        reader-session-guards reader-session-guard-count reader-session-add-guard!)

;; One unpublished operation's support, released after its recording frame.
(defstruct candidate-support (guards tools tool-rows open? epoch-current metadata-current) final: #t)

(defstruct reader-session
  (guard-support dependencies imported-owners refused? evaluated-interface-bindings
   input-origins kernel-contexts kernel-inputs kernel-source-count kernel-progress-key kernel-owners kernel-data
   kernel-initializers preparations public-prepared-count publication-prepared-count
   candidate tool-contexts tool-paths tool-dependencies tool-observations compiler-contexts
   interpreter-observations tool-rows previous-context check-current check-current/closed open-boundary)
  final: #t)

(def (reader-session-guards session)
  (car (reader-session-guard-support session)))
(def (reader-session-guard-count session)
  (cdr (reader-session-guard-support session)))
(def (reader-session-add-guard! session guard)
  ;; Publish the new guard spine and its exact diagnostic width together.
  (let (support (reader-session-guard-support session))
    (set! (reader-session-guard-support session)
      (cons (cons guard (car support)) (1+ (cdr support))))))

(def (new-reader-session previous-context)
  (def dependencies (make-hash-table))
  (def kernel-contexts (make-hash-table))
  (def kernel-inputs (make-hash-table-eq))
  (def kernel-owners (make-hash-table-eq))
  (def kernel-data (make-hash-table-eq))
  (def kernel-initializers (make-hash-table-eq))
  (def preparations (make-hash-table))
  (def candidate (make-parameter #f))
  (defvalues (tool-contexts tool-paths tool-dependencies tool-observations compiler-contexts)
    (module-import-provenance))
  (make-reader-session (cons '() 0) dependencies (make-hash-table) #f 0
    (make-hash-table-eq) kernel-contexts kernel-inputs 0 (gensym 'reader-native-imports)
    kernel-owners kernel-data kernel-initializers
    preparations 0 0 candidate
    tool-contexts tool-paths tool-dependencies tool-observations compiler-contexts
    (hash->list tool-observations) (source-observation-rows tool-observations) previous-context #f #f #f))
