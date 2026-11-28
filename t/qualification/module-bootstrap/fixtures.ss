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
                          (installed (getenv "GERBIL_PATH" (path-expand ".gerbil" owner)))
                          sample: (sample #f))
  (if existing
    (.o root: existing state: installed cold: #f)
    (let* ((scratch (make-temporary-file-name "core-source-build-"))
           (fixture-root (path-expand "source/tao3k/yuanxu" scratch))
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
        (link-fixture-dependencies lib (path-expand "lib" fixture-state)))
      ;; The native build smoke exercises one authored Module. Schema's
      ;; complete import graph has separate build and selection gates.
      (def selected (if sample (string->symbol (path-strip-directory sample)) 'json-schema))
      (when sample
        (copy-fixture-tree sample (path-expand (string-append "modules/" (symbol->string selected)) fixture-root)
          (lambda (_path name kind) (and (eq? kind 'regular) (string-suffix? ".ss" name)))))
      ;; Narrow only fixture selection and retained roots, never build.ss.
      (call-with-output-file (list path: (path-expand "init.ss" fixture-root) truncate: #t)
        (lambda (port)
          (write `(yuanxu! :test-dir "./t" mode: explicit source: "./modules" (,selected)) port)))
      (call-with-output-file (list path: (path-expand "core-spec.ss" fixture-root) truncate: #t)
        (lambda (port)
          (display "prelude: :gerbil/core\n" port)
          (write '(export core-spec) port) (newline port)
          ;; Derive the minimal bootstrap closure from prelude.ss's actual local
          ;; imports instead of hardcoding internal helper module paths.
          (def (local-import-targets root roots)
            (def seen (make-hash-table))
            (def out '())
            (def (read-forms file)
              (call-with-input-file file
                (lambda (port)
                  (let loop ((acc '()))
                    (let (datum (read port))
                      (if (eof-object? datum) (reverse acc) (loop (cons datum acc))))))))
            (def (extract-spec spec base)
              (cond
               ((string? spec)
                (let* ((with-ext (if (string-suffix? ".ss" spec) spec (string-append spec ".ss")))
                       (full (path-normalize (path-expand with-ext base)))
                       (prefix (string-append
                                 (path-strip-trailing-directory-separator (path-normalize root))
                                 "/")))
                  (if (string-prefix? prefix full)
                    (list (path-strip-extension (substring full (string-length prefix) (string-length full))))
                    '())))
               ((symbol? spec)
                (let (s (symbol->string spec))
                  (if (string-prefix? ":tao3k/yuanxu/" s)
                    (list (substring s (string-length ":tao3k/yuanxu/") (string-length s)))
                    '())))
               ((pair? spec)
                (case (car spec)
                  ((only-in except-in except-out rename-in prefix-in)
                   (if (pair? (cdr spec)) (extract-spec (cadr spec) base) '()))
                  ((for-syntax for-template runtime: spec-in)
                   (apply append (map (cut extract-spec <> base) (cdr spec))))
                  ((phi:)
                   (if (and (pair? (cdr spec)) (pair? (cddr spec)))
                     (apply append (map (cut extract-spec <> base) (cddr spec)))
                     '()))
                  (else '())))
               (else '())))
            (def (walk target)
              (unless (hash-key? seen target)
                (hash-put! seen target #t)
                (let (file (path-expand (string-append target ".ss") root))
                  (when (file-exists? file)
                    (let ((base (path-directory file)))
                      (for-each
                        (lambda (form)
                          (when (and (pair? form) (eq? (car form) 'import))
                            (for-each
                              (lambda (spec)
                                (for-each walk (extract-spec spec base)))
                              (cdr form))))
                        (read-forms file)))
                    (set! out (cons target out))))))
            (for-each walk roots)
            (reverse out))
          (def bootstrap
            (local-import-targets fixture-root '("prelude" "core-spec")))
          (def targets
            (if sample bootstrap
              (append bootstrap
                '("module-system/bootstrap/body-inclusion"
                  "module-system/schema/slot-contracts"
                  "module-system/source/build-binding" "module-system/source/role-forms"
                  "object/syntax"
                  "types/contracts" "types/facts" "types/ports"
                  "observability/funcs" "observability/objects" "observability/types"
                  "utilities/algorithms" "utilities/functional"))))
          (write `(def core-spec ',targets) port)))
      (.o root: fixture-root state: fixture-state cold: #t))))

(def (link-fixture-dependencies source target)
  ;; Preserve installed dependency namespaces intact, instead of replacing
  ;; every compiled input with a new leaf symlink. Neither metadata nor runtime
  ;; code is copied or rewritten. Partition only namespaces containing Core.
  (def (excluded? relative)
    (or (member relative '("core" "yuanxu" "tao3k/yuanxu"))
        (and (equal? (path-directory relative) "static/")
             (let (name (path-strip-directory relative))
               (or (string-prefix? "core__" name)
                   (string-prefix? "yuanxu__" name)
                   (string-prefix? "tao3k__yuanxu__" name))))))
  (def (link! relative)
    (unless (excluded? relative)
      (let ((from (path-expand relative source))
            (to (path-expand relative target)))
      (if (member relative '("" "tao3k" "static"))
        (begin
          (create-directory* to)
          (for-each (lambda (name)
                      (link! (if (string-empty? relative) name
                               (string-append relative "/" name))))
                    (directory-files from)))
        (create-symbolic-link from to)))))
  (link! ""))
