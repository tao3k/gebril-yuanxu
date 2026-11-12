;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :std/error Error? Error-message)
        (only-in :clan/poo/object .o .get .cc)
        (only-in :clan/poo/mop make-instance element?)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case)
        :tao3k/yuanxu/module-system/source/objects
        :tao3k/yuanxu/module-system/catalog/metadata
        :tao3k/yuanxu/module-system/catalog/objects)

(export module-catalog-test)

(def (metadata-catalog releases)
  (module-metadata-catalog
    (lambda ()
      (if (null? releases) #!eof
        (begin0 (car releases) (set! releases (cdr releases)))))))

(def module-catalog-test
  (test-suite "Core Module Catalog"
    (yuanxu-test-case "first SourceRef match ignores provenance metadata"
      (let* ((source (make-yuanxu-module-source-ref
                      'local "feature/interface.ss" '((origin . first))))
             (same-source (make-yuanxu-module-source-ref
                           'local "feature/interface.ss" '((origin . later))))
             (first (.o name: 'first))
             (later (.o name: 'later
                       deferred: (error "unselected Catalog module was forced")))
             (catalog
              (make-instance ModuleCatalog name: 'test
               entries: (list (make-instance ModuleSourceBinding source: source module: first)
                              (make-instance ModuleSourceBinding source: same-source module: later)))))
        (check-equal? (resolve-yuanxu-module-source/default
                       catalog same-source 'missing)
                      first)
        (check-equal? (yuanxu-module-catalog-modules catalog)
                      (list first later))
        (check-equal? (yuanxu-module-catalog->alist catalog)
                      '((name . test)
                        (entries
                         ((source (kind . local)
                                  (value . "feature/interface.ss")
                                  (metadata (origin . first)))
                          (module . first))
                         ((source (kind . local)
                                  (value . "feature/interface.ss")
                                  (metadata (origin . later)))
                          (module . later)))))))
    (yuanxu-test-case "missing source returns caller default without I/O"
      (let* ((catalog (make-instance ModuleCatalog name: 'empty entries: '()))
             (source (make-yuanxu-module-package-source 'absent)))
        (check-equal? (resolve-yuanxu-module-source/default
                       catalog source 'not-found)
                      'not-found)))
    (yuanxu-test-case "runtime Catalog validation rejects malformed entries without loading sources"
      (check-equal? (element? ModuleCatalog (.o name: 17 entries: '())) #f)
      (check-equal? (element? ModuleCatalog (.o name: 'invalid entries: '(not-an-entry))) #f)
      (check-equal? (element? ModuleSourceBinding (.o source: #f module: (.o))) #f))
    (yuanxu-test-case "adding entries preserves inherited Catalog fields and isolates the parent"
      (def source (make-yuanxu-module-package-source 'absent))
      (def parent (make-instance ModuleCatalog name: 'base entries: '()))
      (def cached (.get parent entries))
      (def child (.cc parent tenant: 'release))
      (def entry (make-instance ModuleSourceBinding source: source module: (.o name: 'loaded)))
      (def next (yuanxu-module-catalog-add child entry))
      (check-equal? (.get next tenant) 'release)
      (check-equal? (.get next entries) (list entry))
      (check-equal? (.get parent entries) cached)
      (check-equal? (.get child entries) '())
      (check-equal? (element? ModuleCatalog next) #t))
    (yuanxu-test-case "version metadata is ordered and dependency demand reads only the selected release"
      (def first (module-catalog-release ':example/module 'v1 'deps-first))
      (def second (module-catalog-release ':example/module 'v2 'deps-second))
      (def other (module-catalog-release ':else/module 'v1 'deps-other))
      (def catalog (metadata-catalog (list second other first)))
      (def reads 0)
      (def (read-dependencies name version ref)
        (set! reads (+ reads 1))
        (list name version ref))
      (check-equal? (module-metadata-versions catalog ':example/module) '(v1 v2))
      (check-equal? (module-metadata-versions catalog ':absent/module) '())
      (check-equal? (module-metadata-resolve catalog ':example/module 'v3) #f)
      (def selected (module-metadata-resolve catalog ':example/module 'v2))
      (check-equal? (eq? selected second) #t)
      (check-equal? reads 0)
      (check-equal? (module-metadata-dependencies catalog selected read-dependencies)
                    '(:example/module v2 deps-second))
      (check-equal? reads 1)
      (check-exception (metadata-catalog (list first first)) error?))
    (yuanxu-test-case "incremental catalog publication isolates snapshots and refuses a conflicting batch"
      (def old (module-catalog-release ':example/module 'v1 'old))
      (def new (module-catalog-release ':example/module 'v1 'new))
      (def added (module-catalog-release ':example/module 'v2 'added))
      (def other (module-catalog-release ':else/module 'v1 'other))
      (def base (metadata-catalog (list old other)))
      (def add (module-catalog-edit #f added))
      (def replace (module-catalog-edit old new))
      (check-exception (module-metadata-publish base (list add add)) error?)
      (check-equal? (module-metadata-versions base ':example/module) '(v1))
      (def published (module-metadata-publish base (list add replace)))
      (def rebuilt (metadata-catalog (list added other new)))
      (for-each
        (lambda (name)
          (def versions (module-metadata-versions rebuilt name))
          (check-equal? (module-metadata-versions published name) versions)
          (for-each
            (lambda (version)
              (check-equal? (eq? (module-metadata-resolve published name version)
                                 (module-metadata-resolve rebuilt name version)) #t))
            versions))
        '(:example/module :else/module))
      (check-exception (module-metadata-publish published (list replace)) error?)
      (check-exception (module-metadata-dependencies published old
                         (lambda _ (error "stale release reached dependency reader")))
                       (lambda (failure)
                         (and (Error? failure) (equal? (Error-message failure) "stale catalog release"))))
      (check-equal? (module-metadata-dependencies base old (lambda (_name _version ref) ref)) 'old)
      (def removed (module-metadata-publish published (list (module-catalog-edit other #f))))
      (check-equal? (module-metadata-versions removed ':else/module) '())
      (check-equal? (module-metadata-versions published ':else/module) '(v1)))))
