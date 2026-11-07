;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .o)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        :yuanxu/module-system/loader/load-path)

(export module-load-path-test)

(def (source identity-value entries)
  (.o (:: @ yuanxu-module-source-collection-prototype)
      (identity identity-value)
      (locate (lambda (_ key roles)
                (if (and (equal? key '(custom . found))
                         (equal? roles '(interface)))
                  entries
                  '())))))

(def module-load-path-test
  (test-suite "Core ordered Module LoadPath"
    (yuanxu-test-case "first matching collection wins and extension appends"
      (let* ((empty (source 'empty '()))
             (first (source 'first '(primary)))
             (second (source 'second '(fallback)))
             (base (make-yuanxu-module-load-path 'base (list empty first)))
             (extended (extend-yuanxu-module-load-path
                        base 'extended (list second))))
        (check-equal? (yuanxu-module-load-path? extended) #t)
        (check-equal? (yuanxu-module-load-path-identity extended) 'extended)
        (check-equal? (map yuanxu-module-source-collection-identity
                           (yuanxu-module-load-path-collections extended))
                      '(empty first second))
        (check-equal? (yuanxu-module-load-path-locate
                       extended '(custom . found))
                      '(primary))
        (check-equal? (yuanxu-module-load-path-locate
                       extended '(custom . absent))
                      '())))
    (yuanxu-test-case "duplicate identities and noncollections are rejected"
      (let (first (source 'same '(primary)))
        (check-exception
         (make-yuanxu-module-load-path 'bad (list first first))
         (lambda (_) #t))
        (check-exception
         (make-yuanxu-module-load-path 'bad (list first 'not-a-source))
         (lambda (_) #t))))
    (yuanxu-test-case "one thousand overlays preserve last-resort lookup"
      (let* ((empty-sources
              (map (lambda (index)
                     (source (string->symbol
                              (string-append "overlay-" (number->string index)))
                             '()))
                   (iota 1000)))
             (path
              (make-yuanxu-module-load-path
               'many (append empty-sources (list (source 'last '(located)))))))
        (check-equal? (length (yuanxu-module-load-path-collections path))
                      1001)
        (check-equal? (yuanxu-module-load-path-locate
                       path '(custom . found))
                      '(located))))))
