;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Direct-source adapter refusals; no compiler invocation or source generation.
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/error Error? Error-message)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :clan/poo/object .get .o .+)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/admission module-source-read)
        (only-in :yuanxu/module-system/building/build-projection yuanxu-project-source-spec))
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
            (def installed-core? (file-exists? (path-expand "lib/yuanxu" (getenv "GERBIL_PATH"))))
            (def view (yuanxu-load-modules (path-expand "init.ss" root)))
            (def selected (.get view build-graph))
            (def entry (path-expand "build.ss" root))
            (def (project roots (source-root root) (source-entry entry) (source view))
              (yuanxu-project-source-spec source roots source-root source-entry))
            (def artifact (project '("utilities/algorithms" "object-types/contracts")))
            (check-equal? (eq? (.get artifact build-graph) selected) #t)
            (check-equal? (.get artifact source-root) root)
            (check-equal? (file-exists? (path-expand ".gerbil/module-build" root)) #f)
            (check-equal? (length (filter (lambda (row) (equal? (cadr row) "object-types/contracts"))
                                        (.get artifact spec))) 1)
            (check-equal? (rejects? "conflicting retained compiler options"
                            (lambda () (project '((gxc: "object-types/contracts" "-debug"))))) #t)
            (check-equal? (rejects? "duplicate retained compiler target"
                            (lambda () (project '("object-types/contracts" "object-types/contracts")))) #t)
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
                   (link (path-expand "object-types/contracts.ss" links))
                   (build (path-expand "build.ss" links)))
              (create-directory* (path-expand "object-types" links))
              (write-source (path-expand "gerbil.pkg" links) "(package: yuanxu)\n")
              (write-source build "(export #t)")
              (dynamic-wind
                (lambda () (create-symbolic-link (path-expand "object-types/contracts.ss" root) link))
                (lambda () (check-equal? (rejects? "non-regular or a symlink"
                                          (lambda () (project '("object-types/contracts") links build))) #t))
                (lambda () (delete-file link))))
            (let* ((foreign (path-expand "foreign" temporary))
                   (build (path-expand "build.ss" foreign)))
              (write-source (path-expand "gerbil.pkg" foreign) "(package: other)\n")
              (write-source build "(export #t)")
              (write-source (path-expand "owned.ss" foreign) "(export #t)")
              (def dependency-projection (project '("owned") foreign build))
              (check-equal? (.get dependency-projection spec) '((gxc: "owned")))
              (check-equal? (.get dependency-projection compiler-identities) '(other/owned))
              (check-equal? (eq? (.get dependency-projection build-graph) selected) #t)
              ((.get dependency-projection admit-current))
              (def invoked? #f)
              (check-equal? (rejects? "requires all package owners"
                              (lambda ()
                                ((.get dependency-projection .compile) temporary
                                  (lambda () (set! invoked? #t))))) #t)
              (check-equal? invoked? #f)
              ;; A foreign dependency remains observed after target partitioning.
              (let* ((dependency (.get (car (.get selected entries)) path))
                     (original (module-source-read dependency)))
                (dynamic-wind
                  (lambda () (write-source dependency (string-append original "\n;; stale dependency\n")))
                  (lambda () (check-equal? (rejects? "stale"
                                            (.get dependency-projection admit-current)) #t))
                  (lambda () (write-source dependency original))))
              ;; Same declared compiler identity with different physical bytes is
              ;; not a deduplication opportunity.
              (set! foreign (path-expand "collision" temporary))
              (set! build (path-expand "build.ss" foreign))
              (write-source build "(export #t)")
              (write-source (path-expand "gerbil.pkg" foreign) "(package: yuanxu)\n")
              (write-source (path-expand "object-types/contracts.ss" foreign)
                            (module-source-read (path-expand "object-types/contracts.ss" root)))
              (check-equal? (rejects? "conflicting compiler inputs"
                              (lambda () (project '("object-types/contracts") foreign build))) #t))
            (check-equal? (file-exists? (path-expand "lib/yuanxu" (getenv "GERBIL_PATH"))) installed-core?)))))
    (begin
      (displayln "SKIP module-build-spec: CORE_QUALIFICATION_ROOT is unset")
      (test-suite "module-build-spec (source-only opt-in)" (void)))))
