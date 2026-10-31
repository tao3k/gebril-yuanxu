;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal?)
        (only-in :clan/poo/object .o .get .cc)
        (only-in :clan/poo/mop make-instance element?)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/catalog/objects)

(export module-catalog-test)

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
    (yuanxu-test-case "native Catalog validation rejects malformed entries without loading sources"
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
      (check-equal? (element? ModuleCatalog next) #t))))
