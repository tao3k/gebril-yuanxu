;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Test data preparation only: no processes, script dispatcher or main.
(import :clan/poo/object
        (only-in :std/io/tempfile make-temporary-file-name))
(export source-build-fixture copy-fixture-tree)
(def (copy-fixture-tree source target accept?)
  (create-directory* target)
  (for-each
    (lambda (name)
      (def from (path-expand name source))
      (def to (path-expand name target))
      (def kind (file-info-type (file-info from #f)))
      (when (accept? from name kind)
        (case kind
          ((directory) (copy-fixture-tree from to accept?))
          ((regular) (copy-file from to))
          (else (error "qualification fixture requires regular inputs" from)))))
    (directory-files source)))
(def (source-build-fixture owner
                          (existing (getenv "CORE_QUALIFICATION_ROOT" #f))
                          (installed (getenv "GERBIL_PATH" (path-expand ".gerbil" owner))))
  (if existing
    (.o root: existing state: installed cold: #f)
    (let* ((scratch (make-temporary-file-name "core-source-build-"))
           (fixture-root (path-expand "source/core" scratch))
           (fixture-state (path-expand "gerbil" scratch))
           (lib (path-expand "lib" installed)))
      ;; Keep failed fixtures for diagnosis. No source checkout is modified.
      (copy-fixture-tree owner fixture-root
        (lambda (_path name kind)
          (and (not (string-prefix? "." name))
               (not (member name '("t" "design" "docs" "dev" "packages")))
               (or (eq? kind 'directory) (string-suffix? ".ss" name)
                   (string=? name "gerbil.pkg")))))
      ;; A source-only package state legitimately has no installed lib tree.
      ;; Create the empty destination without manufacturing compiled artifacts.
      (create-directory* (path-expand "lib" fixture-state))
      (when (file-exists? lib)
        (copy-fixture-tree lib (path-expand "lib" fixture-state)
          (lambda (path name _kind)
            (not (or (equal? path (path-expand "core" lib))
                     (and (equal? (path-directory path) (path-expand "static/" lib))
                          (string-prefix? "core__" name)))))))
      ;; Narrow only fixture selection and retained roots, never build.ss.
      (call-with-output-file (list path: (path-expand "init.ss" fixture-root) truncate: #t)
        (lambda (port)
          (display "(import \"./module-system/selection/init-syntax.ss\")\n" port)
          (write '(poo-flow! mode: explicit source: "./modules" (json-schema)) port)))
      (call-with-output-file (list path: (path-expand "core-spec.ss" fixture-root) truncate: #t)
        (lambda (port)
          (write '(export core-spec) port) (newline port)
          (write '(def core-spec '("utilities/algorithms" "types" "core-spec")) port)))
      (.o root: fixture-root state: fixture-state cold: #t))))
