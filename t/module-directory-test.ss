;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .o .+ .get .ref .slot? .ref/cached .all-slots/sort)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)
        :yuanxu/feature-system/model
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/source/init
        "./qualification/module-directory/init.ss"
        :yuanxu/module-system/selection/init-syntax
        :yuanxu/module-system/interface)
(export module-directory-test)
;; Compiler declaration and filesystem preparation share the same pure lowering.
(def Intent
  (module-init-intent
    '((yuanxu! mode: explicit source: "./modules" :custom (guestbook -smoke))) #f))
(def DirectoryScope
  (yuanxu-predicate-contract 'test/directory-scope (lambda (_value) #t) (lambda (_v _c) '())))
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
  (.o identity: id features: (.o smoke: (error "negative Feature descriptor forced"))
      core: (.o requires: (if (eq? id 'custom/guestbook)
                            (.o Schema: (.o module-id: 'core/schema contract: DirectoryScope)) (.o))
                scope-contract: DirectoryScope
                link: (lambda (_dependencies) (.o owner: id)))))
(def (fixture-reader reads)
  (lambda (source)
    (let (id (cdr (assq 'module-id (yuanxu-module-source-ref-metadata source))))
      (reads id) (fixture-publication id))))
(def module-directory-test
  (test-suite "Directory and init source preparation without a runtime Loader"
    (yuanxu-test-case "hygienic init declaration lowers without filesystem access"
      (check-equal? (procedure? (.get yuanxu/t/qualification/module-directory.init.exports std-make-spec)) #t)
      (check-equal? (procedure? (.get yuanxu/t/qualification/module-directory.init.exports admit-current)) #t)
      (check-equal? (.get Intent mode) 'explicit)
      (check-equal? (.get Intent root) "./modules")
      (check-equal? (.get (.ref (car (.get Intent decisions)) 'selection) selection-flags) '(-smoke)))
    (yuanxu-test-case "filesystem init feeds the same Core and Feature selected Graph"
      (with-sources
       (lambda (root)
         (let (init-path (path-expand "init.ss" root))
           (write-source init-path "(yuanxu! mode: explicit :core (schema) :custom (guestbook +smoke -cold) :unused (bomb disable: #t))")
           (let* ((v (yuanxu-load-modules init-path
                       read-publication:
                       (lambda (source)
                         (let (id (cdr (assq 'module-id (yuanxu-module-source-ref-metadata source))))
                           (.+ (fixture-publication id)
                               (.o features:
                                   (.o smoke: (feature-descriptor
                                               (.o feature-id: 'custom/guestbook/smoke
                                                   owner-module-id: 'custom/guestbook
                                                   projections: '(smoke)))
                                       cold: (error "negative payload forced"))))))))
                  (graph (.get v selected-graph)))
             (check-equal? (.get graph module-order) '(core/schema custom/guestbook))
             (check-equal? (.get graph feature-order) '(custom/guestbook/smoke))
             (check-equal? (.get graph denied-features) '(custom/guestbook/cold))
             (check-equal? (.get graph feature-contributions projections) '(smoke))
             (write-source init-path "(yuanxu! mode: explicit :custom (guestbook disable: #t))")
             (check-exception ((.get graph admit-current)) error?))))))
    (yuanxu-test-case "negative init probes and source edits invalidate old views"
      (with-sources
       (lambda (root)
         (let (view (yuanxu-load-modules (path-expand "modules" root)))
           ((.get view admit-current))
           (write-source (path-expand "init.ss" root) "(yuanxu! mode: auto source: \"./modules\")")
           (check-exception ((.get view admit-current)) error?)))))
    (yuanxu-test-case "ambiguous authority is refused unless the exact init is supplied"
      (with-sources
       (lambda (root)
         (write-source (path-expand "init.ss" root) "(yuanxu! mode: auto)")
         (write-source (path-expand "modules/init.ss" root) "(yuanxu! mode: auto)")
         (check-exception (yuanxu-load-modules (path-expand "modules" root)) error?)
         (let (view (yuanxu-load-modules (path-expand "modules/init.ss" root)))
           ((.get view admit-current))))))
    (yuanxu-test-case "symlink module entries cannot escape the source root"
      (with-sources
       (lambda (root)
         (create-symbolic-link (path-expand "modules/custom/guestbook" root)
                               (path-expand "modules/escape" root))
         (check-exception (yuanxu-load-modules (path-expand "modules" root)) error?))))
    (yuanxu-test-case "explicit init retains negatives and links only the selected closure"
      (with-sources
       (lambda (root)
         (write-source (path-expand "init.ss" root)
                       "(yuanxu! mode: explicit source: \"./modules\" :core (schema) :custom (guestbook -smoke) :unused (bomb disable: #t))")
         (let* ((reads '())
                (view (yuanxu-load-modules (path-expand "init.ss" root)
                        read-publication: (fixture-reader (lambda (id) (set! reads (cons id reads)))))))
           (check-equal? reads '())
           (check-equal? (.get view context denied-modules) '(unused/bomb))
           (check-equal? (.get (.ref (find (lambda (row) (eq? (.get row identity) 'custom/guestbook))
                                        (.get view context intent decisions)) 'selection) selection-flags) '(-smoke))
           (check-equal? (.get view modules custom guestbook owner) 'custom/guestbook)
           (check-equal? (.get view dependency-order) '(core/schema custom/guestbook))
           ;; Metadata discovery order is not dependency/link order. Check
           ;; exact membership and multiplicity; dependency-order is above.
           (check-equal?
             (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) reads)
             '(core/schema custom/guestbook))
           (check-equal? (.slot? (.get view modules) 'unused) #f)
           ((.get view admit-current))
           (write-source (path-expand "modules/custom/guestbook/config.ss" root) "changed")
           (check-exception ((.get view admit-current)) error?)))))
    (yuanxu-test-case "module views reuse qualified namespace leaves without forcing scopes"
      (with-sources
       (lambda (root)
         (write-source (path-expand "init.ss" root)
           "(yuanxu! mode: explicit source: \"./modules\" :core (schema) :custom (guestbook -smoke))")
         (let* ((reads '())
                (view
                  (yuanxu-load-modules (path-expand "init.ss" root)
                    read-publication: (fixture-reader (lambda (id) (set! reads (cons id reads))))
                    module-view:
                    (lambda (id scope!)
                      (.o identity: id scope: (scope!) tests: 'projection-probe))))
                (modules (.get view modules))
                (module (.get modules custom guestbook)))
           (check-equal? (.get module identity) 'custom/guestbook)
           (check-equal? (eq? module (.get modules custom guestbook)) #t)
           (check-equal? (.get module tests) 'projection-probe)
           (check-equal? reads '())
           (check-equal? (.ref/cached module 'scope) #f)
           (check-equal? (.get module scope owner) 'custom/guestbook)
           (def schema (.get modules core schema))
           (check-equal? (.get schema scope owner) 'core/schema)
           (check-equal? (.ref/cached schema 'tests) #f)
           (check-equal? (.get view dependency-order) '(core/schema custom/guestbook))))))
    (yuanxu-test-case "automatic namespace reflection discovers keys without resolving leaf values"
      (with-sources
       (lambda (root)
         (write-source (path-expand "init.ss" root)
           "(yuanxu! mode: auto source: \"./modules\")")
         (let* ((reads '())
                (view
                  (yuanxu-load-modules (path-expand "init.ss" root)
                    read-publication: (fixture-reader (lambda (id) (set! reads (cons id reads))))
                    module-view:
                    (lambda (id scope!)
                      (.o identity: id scope: (scope!) tests: (error "test projection forced")))))
                (modules (.get view modules)))
           (check-equal? (.all-slots/sort modules) '(core custom unused))
           (check-equal? (.slot? modules 'custom) #t)
           (check-equal? (.slot? modules 'missing) #f)
           (check-equal? (.ref/cached modules 'custom) #f)
           (let (branch (.get modules custom))
             (check-equal? (.all-slots/sort branch) '(guestbook))
             (check-equal? (.slot? branch 'guestbook) #t)
             (check-equal? (.ref/cached branch 'guestbook) #f)
             (let (module (.get branch guestbook))
               (check-equal? (.all-slots/sort module) '(identity scope tests))
               (check-equal? (.slot? module 'tests) #t)
               (check-equal? (.ref/cached module 'scope) #f)
               (check-equal? (.ref/cached module 'tests) #f)))
           (check-equal? reads '())
           ((.get view admit-current))))))
    (yuanxu-test-case "automatic namespace expands one branch and detects changed directory metadata"
      (with-sources
       (lambda (root)
         (write-source (path-expand "init.ss" root)
                       "(yuanxu! mode: auto source: \"./modules\")")
         (let* ((reads '())
                (view (yuanxu-load-modules (path-expand "modules" root)
                        read-publication: (fixture-reader (lambda (id) (set! reads (cons id reads)))))))
           (check-equal? reads '())
           (check-equal? (.get view modules custom guestbook owner) 'custom/guestbook)
           (check-equal? reads '(core/schema custom/guestbook))
           (check-equal? (.get view modules custom guestbook owner) 'custom/guestbook)
           (write-source (path-expand "modules/unused/bomb/config.ss" root) "unselected and unobserved")
           ((.get view admit-current))
           (create-directory (path-expand "modules/new-category" root))
           (check-exception ((.get view admit-current)) error?)))))
    (yuanxu-test-case "module-local init is relative to its own source, required disable fails"
      (with-sources
       (lambda (root)
         (write-source (path-expand "modules/init.ss" root)
                       "(yuanxu! mode: explicit :custom (guestbook) :core (schema disable: #t))")
         (let* ((reads '())
                (view (yuanxu-load-modules (path-expand "modules" root)
                        read-publication: (fixture-reader (lambda (id) (set! reads (cons id reads)))))))
           (check-exception (.get view selected-records) error?)
           (check-equal? reads '(custom/guestbook))
           (check-exception ((.get view admit-current)) error?)))))
    (yuanxu-test-case "an explicit false disable is retained rather than omitted"
      (let* ((intent (module-init-intent '((yuanxu! mode: explicit :custom (guestbook disable: #f))) "init.ss"))
             (row (car (.get intent decisions))))
        (check-equal? (.get row disabled?) #f)
        (check-equal? (.get row disable-specified?) #t)
        (check-equal? (.get row identity) 'custom/guestbook)))
    (yuanxu-test-case "malformed and computed init are refused, never evaluated"
      (for-each
       (lambda (form) (check-exception (module-init-intent form "init.ss") error?))
       '(((yuanxu! mode: explicit :custom (guestbook +smoke -smoke)))
         ((yuanxu! source: "./modules" (guestbook)))
         ((yuanxu! mode: explicit :custom (guestbook disable: t)))
         ((yuanxu! mode: explicit :custom (guestbook) (guestbook)))
         ((def arbitrary (error "must not execute")) (yuanxu!))
         ((yuanxu! mode: unexpected)))))
    (yuanxu-test-case "without a publication capability directory preparation cannot load code"
      (with-sources
       (lambda (root)
         (let (view (yuanxu-load-modules (path-expand "modules" root)))
           (check-exception (.get view modules custom guestbook) error?)))))
    (yuanxu-test-case "required role absence is an admission error on selected demand"
      (with-sources
       (lambda (root)
         (delete-file (path-expand "modules/custom/guestbook/types.ss" root))
         (let (view (yuanxu-load-modules (path-expand "modules" root)
                     read-publication: (fixture-reader void)))
           (check-exception (.get view modules custom guestbook) error?)))))))
