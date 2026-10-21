;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal?)
        (only-in :clan/poo/object .o)
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
             (later (.o name: 'later))
             (catalog
              (make-yuanxu-module-catalog
               'test
               (list (make-yuanxu-module-catalog-entry source first)
                     (make-yuanxu-module-catalog-entry same-source later)))))
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
      (let* ((catalog (make-yuanxu-module-catalog 'empty '()))
             (source (make-yuanxu-module-package-source 'absent)))
        (check-equal? (resolve-yuanxu-module-source/default
                       catalog source 'not-found)
                      'not-found)))))
