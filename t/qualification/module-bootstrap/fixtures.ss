;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Test data preparation only: no processes, script dispatcher or main.
(import :clan/poo/object
        (only-in :std/io/tempfile make-temporary-file-name))
(export source-build-fixture copy-fixture-tree)
(def (copy-fixture-tree source target accept? (materialize copy-file))
  (create-directory* target)
  (for-each
    (lambda (name)
      (def from (path-expand name source))
      (def to (path-expand name target))
      (def kind (file-info-type (file-info from #f)))
      (when (accept? from name kind)
        (case kind
          ((directory) (copy-fixture-tree from to accept? materialize))
          ((regular) (materialize from to))
          ((symbolic-link)
           ;; Only dependency materialization may retain a regular artifact link.
           ;; Source snapshots keep their original no-symlink boundary.
           (unless (and (eq? materialize create-symbolic-link)
                        (eq? (file-info-type (file-info from)) 'regular))
             (error "qualification fixture requires a regular dependency target" from))
           (materialize from to))
          (else (error "qualification fixture requires regular inputs" from)))))
    (directory-files source)))
(def (source-build-fixture owner
                          (existing (getenv "CORE_QUALIFICATION_ROOT" #f))
                          (installed (getenv "GERBIL_PATH" (path-expand ".gerbil" owner))))
  (if existing
    (.o root: existing state: installed cold: #f)
    (let* ((scratch (make-temporary-file-name "core-source-build-"))
           (fixture-root (path-expand "source/yuanxu" scratch))
           (fixture-state (path-expand "gerbil" scratch))
           (lib (path-expand "lib" installed)))
      ;; Keep failed fixtures for diagnosis. No source checkout is modified.
      (copy-fixture-tree owner fixture-root
        (lambda (_path name kind)
          (and (not (string-prefix? "." name))
               (not (member name '("t" "design" "docs" "dev" "packages")))
               (or (eq? kind 'directory) (string-suffix? ".ss" name)
                   (string=? name "gerbil.pkg")))))
      ;; Core sources stay regular, independent snapshot files. Trusted compiled
      ;; dependencies keep their original file identity through private links:
      ;; fresh binary copies trigger repeated platform code-signature validation.
      ;; No Yuanxu library/prelude artifact is linked into this cold state.
      ;; A source-only package state legitimately has no installed lib tree.
      ;; Create the empty destination without manufacturing compiled artifacts.
      (create-directory* (path-expand "lib" fixture-state))
      (when (file-exists? lib)
        (copy-fixture-tree lib (path-expand "lib" fixture-state)
          (lambda (path name _kind)
            (not (or (equal? path (path-expand "core" lib))
                     (equal? path (path-expand "yuanxu" lib))
                     (equal? path (path-expand "tao3k/yuanxu" lib))
                     (and (equal? (path-directory path) (path-expand "static/" lib))
                          (or (string-prefix? "core__" name)
                              (string-prefix? "yuanxu__" name)
                              (string-prefix? "tao3k__yuanxu__" name))))))
          create-symbolic-link))
      ;; Narrow only fixture selection and retained roots, never build.ss.
      (call-with-output-file (list path: (path-expand "init.ss" fixture-root) truncate: #t)
        (lambda (port)
          (display "(import \"./module-system/selection/init-syntax.ss\")\n" port)
          (write '(yuanxu! mode: explicit source: "./modules" (json-schema)) port)))
      (call-with-output-file (list path: (path-expand "core-spec.ss" fixture-root) truncate: #t)
        (lambda (port)
          (write '(export core-spec core-public-roots) port) (newline port)
          (write '(def core-public-roots '()) port) (newline port)
          (write '(def core-spec '("prelude" "utilities/algorithms" "object-types/contracts" "object-types/ports" "core-spec")) port)))
      (.o root: fixture-root state: fixture-state cold: #t))))
