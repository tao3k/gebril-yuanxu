;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal?)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        :yuanxu/module-system/source/objects)

(export module-source-test)

(def module-source-test
  (test-suite "Core Module SourceRef identity"
    (yuanxu-test-case "native source family and resolver identity"
      (let* ((left (make-yuanxu-module-source-ref
                    'local "module/interface.ss" '((origin . first))))
             (right (make-yuanxu-module-source-ref
                     'local "module/interface.ss" '((origin . second)))))
        (check-equal? (yuanxu-module-source-ref? left) #t)
        (check-equal? (yuanxu-module-source-ref=? left right) #t)
        (check-equal? (yuanxu-module-source-ref->alist left)
                      '((kind . local)
                        (value . "module/interface.ss")
                        (metadata (origin . first))))))
    (yuanxu-test-case "source kinds remain inert values"
      (check-equal?
       (yuanxu-module-source-ref-kind
        (make-yuanxu-module-standard-library-source 'std/test))
       'standard-library)
      (check-equal?
       (yuanxu-module-source-ref-metadata
        (make-yuanxu-module-standard-library-source 'std/test))
       '((library . standard))))))
