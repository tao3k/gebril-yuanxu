;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .o .ref .get .call object? object-slots $constant-slot-spec?)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/interface)
(export module-scope-link-test)
(def ObjectScope
  (yuanxu-predicate-contract 'test/scope object? (lambda (_v _c) '())))
(def (publication id requirements link-function)
  (.o identity: id features: (.o)
      core: (.o requires: requirements scope-contract: ObjectScope link: link-function)))
(def (context declarations selected-values denied read-count current-predicate)
  (.o generation: "fixture-v1" module-ids: '(core/schema custom/guestbook unused)
      selected: selected-values denied-modules: denied
      locate: (lambda (id) (make-yuanxu-module-generated-source id))
      read-publication: (lambda (source)
                          (let (id (yuanxu-module-source-ref-value source))
                            (read-count id) (.ref declarations id)))
      current?: current-predicate))
(def module-scope-link-test
  (test-suite "Core selected native module scopes without a Loader backend"
    (yuanxu-test-case "selected-record retains cold factory and warm source refusal"
      (let* ((current #t) (links 0) (checks 0)
             (declarations
              (.o custom/guestbook:
                  (publication 'custom/guestbook (.o)
                    (lambda (_deps) (set! links (+ links 1)) (.o ready: #t)))))
             (view (yuanxu-load-modules
                     (context declarations '(custom/guestbook) '() void
                              (lambda (_generation)
                                (set! checks (+ checks 1)) current)))))
        (def first (.call view .selected-record 'custom/guestbook))
        ;; Link records hold already admitted values. Inspecting the native
        ;; slot specs checks that no linking-frame initializer is retained.
        (check-equal? (andmap (lambda (entry) ($constant-slot-spec? (cdr entry)))
                        (object-slots first)) #t)
        (def before checks)
        (check-equal? (eq? first (.call view .selected-record 'custom/guestbook)) #t)
        ;; A cached Graph/record lookup has one fresh eligibility check; there
        ;; is no effect requiring a preceding duplicate Graph guard.
        (check-equal? (- checks before) 1)
        (check-equal? links 1)
        (set! current #f)
        (check-exception (.call view .selected-record 'custom/guestbook) error?))
      (let* ((current #t)
             (declarations
              (.o custom/guestbook:
                  (publication 'custom/guestbook (.o)
                    (lambda (_deps) (set! current #f) (.o ready: #t)))))
             (view (yuanxu-load-modules
                     (context declarations '(custom/guestbook) '() void
                              (lambda (_generation) current)))))
        (check-exception (.call view .selected-record 'custom/guestbook) error?)
        (check-exception ((.get view admit-current)) error?)))
    (yuanxu-test-case "selected scopes demand dependencies once, leave siblings cold"
      (let* ((reads '()) (links 0) (current #t)
             (declarations
              (.o core/schema: (publication 'core/schema (.o) (lambda (_deps) (.o schema: 'ready)))
                  custom/guestbook:
                  (publication 'custom/guestbook
                   (.o Schema: (.o module-id: 'core/schema contract: ObjectScope))
                   (lambda (deps) (set! links (+ links 1)) (.o schema: (.get deps Schema schema))))
                  unused: (error "unselected publication forced")))
             (view (yuanxu-load-modules
                    (context declarations '(custom/guestbook) '()
                             (lambda (id) (set! reads (cons id reads)))
                             (lambda (_generation) current)))))
        (check-equal? reads '())
        (check-equal? (.get view modules custom guestbook schema) 'ready)
        (check-equal? reads '(core/schema custom/guestbook))
        (check-equal? (.get view dependency-order) '(core/schema custom/guestbook))
        (check-equal? links 1)
        (check-equal? (length (.get view selected-records)) 1)
        (set! current #f)
        (check-exception ((.get view admit-current)) error?)))
    (yuanxu-test-case "consumer requirement Contracts are checked before linking"
      (let* ((strict (yuanxu-predicate-contract
                      'test/strict (lambda (_scope) #f) (lambda (_v _c) '())))
             (linked #f)
             (declarations
              (.o core/schema: (publication 'core/schema (.o) (lambda (_deps) (.o)))
                  custom/guestbook:
                  (publication 'custom/guestbook
                   (.o Schema: (.o module-id: 'core/schema contract: strict))
                   (lambda (_deps) (set! linked #t) (.o)))))
             (view (yuanxu-load-modules
                    (context declarations '(custom/guestbook) '() void
                             (lambda (_generation) #t)))))
        (check-exception (.get view selected-records) error?)
        (check-equal? linked #f)))
    (yuanxu-test-case "disable and source owner mismatches refuse scope publication"
      (let* ((reads 0)
             (declarations (.o custom/guestbook:
                             (publication 'custom/guestbook
                              (.o Schema: (.o module-id: 'core/schema contract: ObjectScope))
                              (lambda (_deps) (error "link must not run")))))
             (view (yuanxu-load-modules
                    (context declarations '(custom/guestbook) '(core/schema)
                             (lambda (_id) (set! reads (+ reads 1)))
                             (lambda (_generation) #t)))))
        (check-exception (.get view selected-records) error?)
        (check-equal? reads 1)
        (check-exception ((.get view admit-current)) error?))
      (let (view (yuanxu-load-modules
                 (context (.o custom/guestbook:
                           (publication 'wrong (.o) (lambda (_deps) (.o))))
                          '(custom/guestbook) '() void (lambda (_generation) #t))))
        (check-exception (.get view selected-records) error?)))
    (yuanxu-test-case "cycles fail without retaining a usable partial session"
      (let* ((declarations
              (.o core/schema:
                  (publication 'core/schema
                   (.o App: (.o module-id: 'custom/guestbook contract: ObjectScope))
                   (lambda (_deps) (.o)))
                  custom/guestbook:
                  (publication 'custom/guestbook
                   (.o Schema: (.o module-id: 'core/schema contract: ObjectScope))
                   (lambda (_deps) (.o)))))
             (view (yuanxu-load-modules
                    (context declarations '(custom/guestbook) '() void
                             (lambda (_generation) #t)))))
        (check-exception (.get view selected-records) error?)
        (check-exception (.get view modules custom guestbook) error?)))))
