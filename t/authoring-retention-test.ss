;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; A diagnostic reachability control, not an alternative AWS acceptance mode.
(import :std/test :clan/poo/object
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/observability/testing-case
                 yuanxu-default-testing-case-profile yuanxu-test-checkpoint)
        (only-in :yuanxu/module-system/source/interface yuanxu-module-interface)
        (only-in :yuanxu/module-system/authoring/admission
                 yuanxu-module-authoring-admit-datum
                 yuanxu-module-authoring-admission-accepted?))
(export authoring-retention-test)

(.def (Retained @ yuanxu-default-testing-case-profile)
  identity: 'qualification/authoring-reachability
  collect-before-sample?: #t
  emit?: #t)
(.def Resource .acquire: void .release: (lambda (_resource) (void)))
(def Interface (yuanxu-module-interface "retention" (.o) '()))

;; Keep allocation in a completed lexical frame. Only weak keys escape;
;; retaining the last local datum would make the reachability control invalid.
(def (exercise weak)
  (do ((index 0 (1+ index))) ((= index 100))
    (let* ((datum `(def (sample x) (quote ,(make-u8vector 65536 0))))
           (admission (yuanxu-module-authoring-admit-datum Interface 'funs datum)))
      (check-equal? (yuanxu-module-authoring-admission-accepted? admission) #t)
      (hash-put! weak datum #t)))
  (void))

(def authoring-retention-test
  (test-suite "Source authoring transient arguments"
    (yuanxu-test-fixture "completed multi-dispatch does not retain source datums"
      profile: Retained (resource Resource)
      (def weak (make-hash-table test: eq? weak-keys: #t))
      (exercise weak)
      ;; Collection is the existing diagnostic Case policy. It is never enabled
      ;; for the original Ops gate and does not change its heap or deadline.
      (yuanxu-test-checkpoint 'authoring-returned)
      (check-equal? (length (hash-keys weak)) 0))))
