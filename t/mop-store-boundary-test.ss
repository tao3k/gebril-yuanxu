;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Run only through the bounded compilation qualification recipe.
(import :std/test :clan/poo/object
        (only-in :clan/poo/slot-observation call-with-slot-read-observer)
        (prefix-in (only-in :gerbil/runtime/mop slot-set!) runtime.)
        (only-in :std/error Error? Error-message)
        (only-in :std/encoding/json write-json)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        "qualification/mop-state/store-policy"
        "qualification/mop-state/precompiled-stores"
        "qualification/mop-state/unlowered-store")
(export mop-store-boundary-test test-cleanup!)
(def completed 0)
(def observations '())
(def (record thunk)
  (def roots '())
  (call-with-slot-read-observer (lambda (read) (set! roots (cons read roots))) thunk)
  (reverse roots))
;; Existing APIs; the compiler owns the common check.
(def (generated-store! spec value) ($self-slot-spec-fun-set! spec value))
(def (reflective-store! spec value) (runtime.slot-set! spec 'fun value))
(def (inline-store! spec value) (struct-instance-init! spec value))
(def (refusal label write)
  (.def Parent port: 5432 unused: (error "unselected branch forced"))
  (.def (Hot @ Parent))
  (.def (Cold @ Parent))
  (def Copy (.cc Parent))
  (def Merged (.+ (.o) Parent))
  (def Direct (make-object slots: (object-slots Parent)))
  (def spec (cdr (assq 'port (object-slots Parent))))
  (def owners (specification-owners spec))
  (for-each (lambda (owner) (check-equal? (and (memq owner owners) #t) #t))
    (list Parent Hot Cold Copy Merged Direct))
  (def cached (.get Parent port))
  (def roots (record (cut .get Hot port)))
  (def revision (object-revision Parent))
  (def original ($self-slot-spec-fun spec))
  (def forced 0)
  (def result
    (with-catch values
      (cut replay-slot-reads! roots
        (lambda (_owner _key)
          (dynamic-wind
            (lambda () (write spec (lambda (_self) 5440)))
            (lambda () (set! forced (+ forced 1)) (.get Cold port))
            (lambda () (write spec original)))))))
  (check-equal? (Error? result) #t)
  (check-equal? (Error-message result) "object mutation during read replay")
  (check-equal? (store-frame-depth) 0)
  (check-equal? forced 0)
  (check-equal? (object-%instance Cold) #f)
  (check-equal? (eq? ($self-slot-spec-fun spec) original) #t)
  (check-equal? (object-revision Parent) revision)
  (check-equal? (.get Parent port) cached)
  (check-equal? (.get Hot port) 5432)
  (check-equal? (.get Cold port) 5432)
  (check-equal? (.get Copy port) 5432)
  ;; The copied receiver has no ancestry edge to Parent. Its selected read
  ;; must protect the same carrier without a caller-supplied owner assertion.
  (def copy-result (with-catch values
    (cut replay-slot-reads! (record (cut .get Copy port))
      (lambda (_owner _key) (write spec original)))))
  (check-equal? (Error? copy-result) #t)
  (check-equal? (Error-message copy-result) "object mutation during read replay")
  (set! observations (cons (vector label (length owners) forced cached
                             (.get Hot port) (.get Cold port)) observations)))
(def mop-store-boundary-test
 (test-suite "Compiler-lowered native owned stores"
  (yuanxu-test-case "generated setter refuses before a first store"
    (refusal "generated" generated-store!)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "SDK reflective store body shares the same refusal"
    (refusal "reflective" reflective-store!)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "constructor inlining cannot erase the store check"
    (refusal "inline" inline-store!)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "precompiled generated callback guards its own store through an unlowered caller"
    (def invoke (unlowered-invoker))
    (def writer (precompiled-store 'generated))
    (refusal "precompiled-generated" (cut invoke writer <> <>))
    (set! completed (+ completed 1)))
  (yuanxu-test-case "precompiled reflection callback guards its own store through an unlowered caller"
    (def invoke (unlowered-invoker))
    (def writer (precompiled-store 'reflective))
    (refusal "precompiled-reflective" (cut invoke writer <> <>))
    (set! completed (+ completed 1)))
  (yuanxu-test-case "precompiled inline callback guards its own store through an unlowered caller"
    (def invoke (unlowered-invoker))
    (def writer (precompiled-store 'inline))
    (refusal "precompiled-inline" (cut invoke writer <> <>))
    (set! completed (+ completed 1)))
  (yuanxu-test-case "precompiled unlowered code remains a domain-closure counterexample"
    (.def Parent port: 5432 unused: (error "unselected branch forced"))
    (.def (Hot @ Parent))
    (.def (Cold @ Parent))
    (.get Parent port)
    (def roots (record (cut .get Hot port)))
    (def spec (cdr (assq 'port (object-slots Parent))))
    (def original ($self-slot-spec-fun spec))
    (def escape (unlowered-store-callback))
    (def changed? #f)
    (replay-slot-reads! roots
      (lambda (_owner _key)
        (unless changed?
          (set! changed? #t)
          (dynamic-wind
            (lambda () (escape spec (lambda (_self) 5440)))
            (lambda () (.get Cold port))
            (lambda () (escape spec original))))))
    (check-equal? (.get Parent port) 5432)
    (check-equal? (.get Hot port) 5432)
    (check-equal? (.get Cold port) 5440)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "nested frames and exception identity restore after refusal"
    (.def Outer port: 5432)
    (.def Inner port: 5433)
    (def outer (record (cut .get Outer port)))
    (def inner (record (cut .get Inner port)))
    (def spec (cdr (assq 'port (object-slots Outer))))
    (def original ($self-slot-spec-fun spec))
    (def problem (with-catch values (lambda () (error "store sentinel"))))
    (replay-slot-reads! outer
      (lambda (_owner _key)
        (check-equal? (store-frame-depth) 1)
        (def failure (with-catch values
          (cut replay-slot-reads! inner
            (lambda (_owner _key)
              (check-equal? (store-frame-depth) 2)
              (generated-store! spec original)))))
        (check-equal? (Error-message failure) "object mutation during read replay")
        (check-equal? (store-frame-depth) 1)
        (check-equal? (eq? problem (with-catch values
          (cut replay-slot-reads! inner (lambda (_owner _key) (raise problem))))) #t)
        (check-equal? (store-frame-depth) 1)))
    (check-equal? (store-frame-depth) 0)
    (generated-store! spec original)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "inline receiver and value expressions are evaluated once before refusal"
    (.def Root port: 5432 unused: (error "unselected branch forced"))
    (def roots (record (cut .get Root port)))
    (def spec (cdr (assq 'port (object-slots Root))))
    (def receiver-count 0)
    (def value-count 0)
    (def failure (with-catch values
      (cut replay-slot-reads! roots
        (lambda (_owner _key)
          (struct-instance-init!
            (begin (set! receiver-count (+ receiver-count 1)) spec)
            (begin (set! value-count (+ value-count 1)) (lambda (_self) 5440)))))))
    (check-equal? (Error-message failure) "object mutation during read replay")
    (check-equal? receiver-count 1)
    (check-equal? value-count 1)
    (check-equal? (.get Root port) 5432)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "an unregistered carrier refuses before its first store"
    (def roots (record unlowered-store-callback))
    (def spec (unlowered-carrier))
    (def invoked? #f)
    (def failure (with-catch values
      (cut replay-slot-reads! roots
        (lambda (_owner _key)
          (generated-store! spec (lambda (_self) 5440))
          (set! invoked? #t)))))
    (check-equal? (Error? failure) #t)
    (check-equal? (Error-message failure) "unregistered specification allocation")
    (check-equal? invoked? #f)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "an unread carrier still shares the selected receiver's invalidation scope"
    (.def Parent port: 5432 spare: 1 unused: (error "unselected branch forced"))
    (.def (Hot @ Parent))
    (def roots (record (cut .get Hot port)))
    (def spec (cdr (assq 'spare (object-slots Parent))))
    (def failure (with-catch values
      (cut replay-slot-reads! roots
        (lambda (_owner _key) (generated-store! spec (lambda (_self) 2))))))
    (check-equal? (Error-message failure) "object mutation during read replay")
    (check-equal? (.get Hot spare) 1)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "ordinary default data is not classified as a slot specification"
    (.def Root (port ? 5432) unused: (error "unselected branch forced"))
    (def roots (record (cut .get Root port)))
    (check-equal? (specification-owners 5432) '())
    (replay-slot-reads! roots (lambda (_owner _key) (void)))
    (check-equal? (.get Root port) 5432)
    (set! completed (+ completed 1)))))
(def (test-cleanup!)
  (check-equal? completed 12)
  (let (root (getenv "CORE_STORE_ROOT"))
    (call-with-output-file (list path: (path-expand "observations.json" root) truncate: #t)
      (lambda (port) (write-json port (list->vector (reverse observations))))))
  (displayln "STORE-BOUNDARY: 12 cases; independently compiled callbacks guarded; old callback counterexample retained"))
