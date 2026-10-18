;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Direct-source adapter refusals; no compiler invocation or source generation.
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/error Error? Error-message)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :clan/poo/object .get .o .+)
        (only-in :core/module-system/interface poo-flow-load-modules)
        (only-in :core/module-system/source/admission module-source-read)
        (only-in :core/module-system/building/build-projection poo-flow-core-project-source-spec))
(export module-build-spec-test)
(def root (getenv "CORE_QUALIFICATION_ROOT" #f))
(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))
(def (rejects? pattern thunk)
  (with-catch
    (lambda (e)
      (if (and (Error? e) (pregexp-match pattern (Error-message e))) #t
          (begin (display-exception e) #f)))
      (lambda () (thunk) #f)))
  (def module-build-spec-test
    (if root
    (test-suite "Direct source build specification identity and validity"
      (test-case "one selected Graph, retained overlaps, conflicts and stale entry"
        (call-with-temporary-directory "build-spec-boundaries"
          (lambda (temporary)
            (def view (poo-flow-load-modules (path-expand "init.ss" root)))
            (def selected (.get view build-graph))
            (def entry (path-expand "build.ss" root))
            (def (project roots (source-root root) (source-entry entry) (source view))
              (poo-flow-core-project-source-spec source roots source-root source-entry))
            (def artifact (project '("utilities/algorithms" "types")))
            (check-equal? (eq? (.get artifact build-graph) selected) #t)
            (check-equal? (.get artifact source-root) root)
            (check-equal? (file-exists? (path-expand ".gerbil/module-build" root)) #f)
            (check-equal? (length (filter (lambda (row) (equal? (cadr row) "types"))
                                        (.get artifact spec))) 1)
            (check-equal? (rejects? "conflicting retained compiler options"
                            (lambda () (project '((gxc: "types" "-debug"))))) #t)
            (check-equal? (rejects? "duplicate retained compiler target"
                            (lambda () (project '("types" "types")))) #t)
            (check-equal? (rejects? "retained build entries require"
                            (lambda () (project #t))) #t)
            (let (original (module-source-read entry))
              (dynamic-wind
                (lambda () (write-source entry (string-append original "\n;; changed entry\n")))
                (lambda () (check-equal? (rejects? "stale selected build input"
                                          (.get artifact admit-current)) #t))
                (lambda () (write-source entry original))))
            ((.get artifact admit-current))
            (let* ((links (path-expand "links" temporary))
                   (link (path-expand "types.ss" links))
                   (build (path-expand "build.ss" links)))
              (write-source (path-expand "gerbil.pkg" links) "(package: core)\n")
              (write-source build "(export #t)")
              (dynamic-wind
                (lambda () (create-symbolic-link (path-expand "types.ss" root) link))
                (lambda () (check-equal? (rejects? "non-regular or a symlink"
                                          (lambda () (project '("types") links build))) #t))
                (lambda () (delete-file link))))
            (let* ((foreign (path-expand "foreign" temporary))
                   (build (path-expand "build.ss" foreign)))
              (write-source (path-expand "gerbil.pkg" foreign) "(package: other)\n")
              (write-source build "(export #t)")
              (check-equal? (rejects? "outside the build package prefix"
                              (lambda () (project '() foreign build))) #t)
              ;; Same declared compiler identity with different physical bytes is
              ;; not a deduplication opportunity.
              (set! foreign (path-expand "collision" temporary))
              (set! build (path-expand "build.ss" foreign))
              (write-source build "(export #t)")
              (write-source (path-expand "gerbil.pkg" foreign) "(package: core)\n")
              (write-source (path-expand "types.ss" foreign)
                            (module-source-read (path-expand "types.ss" root)))
              (check-equal? (rejects? "conflicting compiler inputs"
                              (lambda () (project '("types") foreign build))) #t))
            (check-equal? (file-exists? (path-expand "lib/core" (getenv "GERBIL_PATH"))) #f)))))
    (begin
      (displayln "SKIP module-build-spec: CORE_QUALIFICATION_ROOT is unset")
      (test-suite "module-build-spec (source-only opt-in)" (void)))))
