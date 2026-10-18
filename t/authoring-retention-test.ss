;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; A diagnostic reachability control, not an alternative AWS acceptance mode.
(import :std/test :clan/poo/object
        (only-in :core/observability/testing-fixture poo-flow-test-fixture)
        (only-in :core/observability/testing-case
                 poo-flow-default-testing-case-profile poo-flow-test-checkpoint)
        (only-in :core/module-system/source/interface poo-flow-module-interface)
        (only-in :core/module-system/authoring/admission
                 poo-flow-module-authoring-admit-datum
                 poo-flow-module-authoring-admission-accepted?))
(export authoring-retention-test)

(.def (Retained @ poo-flow-default-testing-case-profile)
  identity: 'qualification/authoring-reachability
  collect-before-sample?: #t
  emit?: #t)
(.def Resource .acquire: void .release: (lambda (_resource) (void)))
(def Interface (poo-flow-module-interface "retention" (.o) '()))

;; Keep allocation in a completed lexical frame. Only weak keys escape;
;; retaining the last local datum would make the reachability control invalid.
(def (exercise weak)
  (do ((index 0 (1+ index))) ((= index 100))
    (let* ((datum `(def (sample x) (quote ,(make-u8vector 65536 0))))
           (admission (poo-flow-module-authoring-admit-datum Interface 'funs datum)))
      (check-equal? (poo-flow-module-authoring-admission-accepted? admission) #t)
      (hash-put! weak datum #t)))
  (void))

(def authoring-retention-test
  (test-suite "Source authoring transient arguments"
    (poo-flow-test-fixture "completed multi-dispatch does not retain source datums"
      profile: Retained (resource Resource)
      (def weak (make-hash-table test: eq? weak-keys: #t))
      (exercise weak)
      ;; Collection is the existing diagnostic Case policy. It is never enabled
      ;; for the original Ops gate and does not change its heap or deadline.
      (poo-flow-test-checkpoint 'authoring-returned)
      (check-equal? (length (hash-keys weak)) 0))))
