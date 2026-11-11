;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/struct/rbtree
                 RBTree rbtree-get rbtree-put! rbtree-put rbtree-remove
                 rbtree-empty? rbtree-foldr symbol-cmp symbol-hash-cmp))

(export module-catalog-release
        module-metadata-catalog module-metadata-versions module-metadata-resolve
        module-metadata-dependencies
        module-catalog-edit module-metadata-publish)

;; A release owns scalar names and a dependency reference. The tree carrier
;; and its mutable builder are private. Demand owns the meaning of the reference.
(defstruct catalog-release (name version dependency-ref) final: #t)
(defstruct catalog-snapshot (names) final: #t)
(defstruct catalog-edit (expected replacement) final: #t)

(def (catalog-symbol value)
  (unless (symbol? value) (error "expected a catalog symbol" value))
  (string->symbol (symbol->string value)))

(def (module-catalog-release name version dependency-ref)
  (make-catalog-release (catalog-symbol name)
    (catalog-symbol version) (catalog-symbol dependency-ref)))

;; A producer returns one release per call, then EOF. Only bootstrap mutates
;; tree wrappers. The producer never receives a writer into a published root.
(def (module-metadata-catalog next)
  (def names (RBTree symbol-hash-cmp))
  (let loop ()
    (let (release (next))
      (unless (eof-object? release)
        (unless (catalog-release? release) (error "expected a catalog release" release))
        (let* ((name (catalog-release-name release))
               (version (catalog-release-version release))
               (versions (or (rbtree-get names name)
                             (let (fresh (RBTree symbol-cmp))
                               (rbtree-put! names name fresh)
                               fresh))))
          (when (rbtree-get versions version)
            (error "duplicate catalog release" name version))
          (rbtree-put! versions version release))
        (loop))))
  (make-catalog-snapshot names))

(def (module-metadata-versions snapshot name)
  (let (versions (rbtree-get (catalog-snapshot-names snapshot) (catalog-symbol name)))
    (if versions
      (rbtree-foldr (lambda (version _release result) (cons version result)) '() versions)
      '())))

(def (module-metadata-resolve snapshot name version)
  (let ((versions (rbtree-get (catalog-snapshot-names snapshot) (catalog-symbol name)))
        (key (catalog-symbol version)))
    (and versions (rbtree-get versions key))))

(def (module-metadata-dependencies snapshot release read-dependencies)
  (def name (catalog-release-name release))
  (def version (catalog-release-version release))
  (unless (eq? release (module-metadata-resolve snapshot name version))
    (error "stale catalog release" name version))
  (read-dependencies name version (catalog-release-dependency-ref release)))

(def (module-catalog-edit expected replacement)
  (unless (and (or expected replacement)
               (or (not expected) (catalog-release? expected))
               (or (not replacement) (catalog-release? replacement))
               (or (not expected) (not replacement)
                   (and (eq? (catalog-release-name expected) (catalog-release-name replacement))
                        (eq? (catalog-release-version expected) (catalog-release-version replacement)))))
    (error "invalid catalog edit" expected replacement))
  (make-catalog-edit expected replacement))

;; Validate each exact old row while constructing private persistent roots.
;; A conflict discards the entire provisional result. A returned snapshot
;; shares untouched names and versions with its predecessor.
(def (module-metadata-publish previous edits)
  (unless (list? edits) (error "expected a finite list of catalog edits" edits))
  (def original (catalog-snapshot-names previous))
  (let loop ((names original) (remaining edits))
    (if (null? remaining)
      (if (eq? names original) previous (make-catalog-snapshot names))
      (let* ((edit (car remaining))
             (expected (catalog-edit-expected edit))
             (replacement (catalog-edit-replacement edit))
             (release (or expected replacement))
             (name (catalog-release-name release))
             (version (catalog-release-version release))
             (versions (rbtree-get names name)))
        (unless (eq? expected (and versions (rbtree-get versions version)))
          (error "catalog version conflict" name version))
        (if (eq? expected replacement)
          (loop names (cdr remaining))
          (let (updated
                 (if replacement
                   (rbtree-put (or versions (RBTree symbol-cmp)) version replacement)
                   (rbtree-remove versions version)))
            (loop (if (rbtree-empty? updated)
                    (rbtree-remove names name)
                    (rbtree-put names name updated))
              (cdr remaining))))))))
