;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .o .get .ref .slot?)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :core/types poo-flow-predicate-contract)
        :core/module-system/source/objects
        :core/module-system/source/init
        :core/module-system/selection/init-syntax
        :core/module-system/interface)
(export module-directory-test)
;; Compiler declaration and filesystem preparation share the same pure lowering.
(poo-flow! mode: explicit source: "./modules" :custom (guestbook -smoke))
(def DirectoryScope
  (poo-flow-predicate-contract 'test/directory-scope (lambda (_value) #t) (lambda (_v _c) '())))
(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (lambda (port) (display text port))))
(def (remove-tree path)
  (if (eq? (file-info-type (file-info path #f)) 'directory)
    (begin (for-each (lambda (name) (remove-tree (path-expand name path))) (directory-files path))
           (delete-directory path))
    (delete-file path)))
(def (with-sources test)
  (let (root (make-temporary-file-name "module-directory-"))
    (dynamic-wind
     (lambda ()
       (for-each
        (lambda (id)
          (for-each (lambda (role) (write-source (path-expand (string-append "modules/" id "/" role) root)
                                                "(error \"inert source must never execute\")\n"))
                    '("types.ss" "objects.ss" "config.ss" "interface.ss")))
        '("core/schema" "custom/guestbook" "unused/bomb")))
     (lambda () (test root))
     (lambda () (remove-tree root)))))
(def (fixture-publication id)
  (.o identity: id features: (.o)
      core: (.o requires: (if (eq? id 'custom/guestbook)
                            (.o Schema: (.o module-id: 'core/schema contract: DirectoryScope)) (.o))
                scope-contract: DirectoryScope
                link: (lambda (_dependencies) (.o owner: id)))))
(def (fixture-reader reads)
  (lambda (source)
    (let (id (cdr (assq 'module-id (poo-flow-module-source-ref-metadata source))))
      (reads id) (fixture-publication id))))
(def module-directory-test
  (test-suite "Directory and init source preparation without a runtime Loader"
    (poo-flow-test-case "hygienic init declaration lowers without filesystem access"
      (check-equal? (.get poo-flow-module-init mode) 'explicit)
      (check-equal? (.get poo-flow-module-init root) "./modules")
      (check-equal? (.get (.ref (car (.get poo-flow-module-init decisions)) 'selection) selection-flags) '(-smoke)))
    (poo-flow-test-case "negative init probes and source edits invalidate old views"
      (with-sources
       (lambda (root)
         (let (view (poo-flow-load-modules (path-expand "modules" root)))
           ((.get view admit-current))
           (write-source (path-expand "init.ss" root) "(poo-flow! mode: auto source: \"./modules\")")
           (check-exception ((.get view admit-current)) error?)))))
    (poo-flow-test-case "ambiguous authority is refused unless the exact init is supplied"
      (with-sources
       (lambda (root)
         (write-source (path-expand "init.ss" root) "(poo-flow! mode: auto)")
         (write-source (path-expand "modules/init.ss" root) "(poo-flow! mode: auto)")
         (check-exception (poo-flow-load-modules (path-expand "modules" root)) error?)
         (let (view (poo-flow-load-modules (path-expand "modules/init.ss" root)))
           ((.get view admit-current))))))
    (poo-flow-test-case "symlink module entries cannot escape the source root"
      (with-sources
       (lambda (root)
         (create-symbolic-link (path-expand "modules/custom/guestbook" root)
                               (path-expand "modules/escape" root))
         (check-exception (poo-flow-load-modules (path-expand "modules" root)) error?))))
    (poo-flow-test-case "explicit init retains negatives and links only the selected closure"
      (with-sources
       (lambda (root)
         (write-source (path-expand "init.ss" root)
                       "(poo-flow! mode: explicit source: \"./modules\" :custom (guestbook -smoke) :unused (bomb disable: #t))")
         (let* ((reads '())
                (view (poo-flow-load-modules (path-expand "init.ss" root)
                        read-publication: (fixture-reader (lambda (id) (set! reads (cons id reads)))))))
           (check-equal? reads '())
           (check-equal? (.get view context denied-modules) '(unused/bomb))
           (check-equal? (.get (.ref (car (.get view context intent decisions)) 'selection) selection-flags) '(-smoke))
           (check-equal? (.get view modules custom guestbook owner) 'custom/guestbook)
           (check-equal? (.get view dependency-order) '(core/schema custom/guestbook))
           (check-equal? reads '(core/schema custom/guestbook))
           (check-equal? (.slot? (.get view modules) 'unused) #f)
           ((.get view admit-current))
           (write-source (path-expand "modules/custom/guestbook/config.ss" root) "changed")
           (check-exception ((.get view admit-current)) error?)))))
    (poo-flow-test-case "automatic namespace expands one branch and detects changed directory metadata"
      (with-sources
       (lambda (root)
         (let* ((reads '())
                (view (poo-flow-load-modules (path-expand "modules" root)
                        read-publication: (fixture-reader (lambda (id) (set! reads (cons id reads)))))))
           (check-equal? reads '())
           (check-equal? (.get view modules custom guestbook owner) 'custom/guestbook)
           (check-equal? reads '(core/schema custom/guestbook))
           (check-equal? (.get view modules custom guestbook owner) 'custom/guestbook)
           (write-source (path-expand "modules/unused/bomb/config.ss" root) "unselected and unobserved")
           ((.get view admit-current))
           (create-directory (path-expand "modules/new-category" root))
           (check-exception ((.get view admit-current)) error?)))))
    (poo-flow-test-case "module-local init is relative to its own source, required disable fails"
      (with-sources
       (lambda (root)
         (write-source (path-expand "modules/init.ss" root)
                       "(poo-flow! :custom (guestbook) :core (schema disable: #t))")
         (let* ((reads '())
                (view (poo-flow-load-modules (path-expand "modules" root)
                        read-publication: (fixture-reader (lambda (id) (set! reads (cons id reads)))))))
           (check-exception (.get view selected-records) error?)
           (check-equal? reads '(custom/guestbook))
           (check-exception ((.get view admit-current)) error?)))))
    (poo-flow-test-case "an explicit false disable is retained rather than omitted"
      (let* ((intent (module-init-intent '((poo-flow! :custom (guestbook disable: #f))) "init.ss"))
             (row (car (.get intent decisions))))
        (check-equal? (.get row disabled?) #f)
        (check-equal? (.get row disable-specified?) #t)
        (check-equal? (.get row identity) 'custom/guestbook)))
    (poo-flow-test-case "malformed and computed init are refused, never evaluated"
      (for-each
       (lambda (form) (check-exception (module-init-intent form "init.ss") error?))
       '(((poo-flow! :custom (guestbook +smoke -smoke)))
         ((poo-flow! :custom (guestbook disable: t)))
         ((poo-flow! :custom (guestbook) (guestbook)))
         ((def arbitrary (error "must not execute")) (poo-flow!))
         ((poo-flow! mode: unexpected)))))
    (poo-flow-test-case "without a publication capability directory preparation cannot load code"
      (with-sources
       (lambda (root)
         (let (view (poo-flow-load-modules (path-expand "modules" root)))
           (check-exception (.get view modules custom guestbook) error?)))))
    (poo-flow-test-case "required role absence is an admission error on selected demand"
      (with-sources
       (lambda (root)
         (delete-file (path-expand "modules/custom/guestbook/types.ss" root))
         (let (view (poo-flow-load-modules (path-expand "modules" root)
                     read-publication: (fixture-reader void)))
           (check-exception (.get view modules custom guestbook) error?)))))))
