;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/error Error-irritants)
        (only-in :yuanxu/observability/testing-fixture
                 yuanxu-test-fixture with-yuanxu-fixture)
        (only-in :yuanxu/t/qualification/service-publication/fixtures
                 DirectoryFixture DirectoryFailureFixture ServicesFixture RelocatedServicesFixture write-source))
(export service-publication-fixture-test)
(def (check-distinct-verification-state first second releases)
  (check-equal? (eq? first second) #f)
  (for-each
    (lambda (field)
      (check-equal? (eq? (.ref first field) (.ref second field)) #f))
    '(primary-error secondary-error))
  (for-each
    (lambda (field)
      (check-equal? (equal? (.ref first field) (.ref second field)) #f))
    '(failed-directory sibling-directory))
  (for-each
    (lambda (observation)
      (def causes (Error-irritants (.get observation failure)))
      (check-equal? (length causes) 2)
      (check-equal? (eq? (car causes) (.get observation primary-error)) #t)
      (check-equal? (eq? (cadr causes) (.get observation secondary-error)) #t)
      (check-equal? (.get observation release-count) releases)
      (check-equal? (.get observation cleanup-paths)
                    (list (.get observation failed-directory))))
    (list first second)))

(def (check-independent-verifications first second releases)
  (check-distinct-verification-state first second releases)
  (for-each
    (lambda (observation)
      (for-each
        (lambda (field)
          (check-equal? (file-exists? (.ref observation field)) #f))
        '(failed-directory sibling-directory)))
    (list first second)))

(def (retry-same-resource _fixture resource verify)
  (verify resource))
(def (retry-acquired-resource fixture _resource verify)
  (with-yuanxu-fixture (next fixture) (verify next)))

(def (check-interrupted-recovery control phase with-retry)
  (def control-root (.get control root))
  (def marker (path-expand "keep/input" control-root))
  (write-source marker "keep")
  (def interruption
    (with-catch values (lambda () (error "verification interrupted before recovery"))))
  (def checkpoints 0)
  (def interrupted #f)
  (def recovered #f)
  (def owner-root #f)
  (def retry-root #f)
  (def (interrupt-once observation)
    (set! checkpoints (+ checkpoints 1))
    (when (= checkpoints 1)
      (set! interrupted observation)
      (check-equal? (file-exists? (.get observation failed-directory)) #t)
      (check-equal? (file-exists? (.get observation sibling-directory)) #t)
      (raise interruption)))
  (def Fixture
    (.cc DirectoryFailureFixture failure-phase: phase
      prefix: (path-expand "recovery-" control-root)
      .after-failure: interrupt-once))
  (with-yuanxu-fixture (probe Fixture)
    (set! owner-root (.get probe root))
    (def caught (with-catch values (lambda () (.call probe .verify))))
    (check-equal? (eq? caught interruption) #t)
    (check-equal? (.get interrupted owner-root) owner-root)
    (check-equal? (file-exists? (.get interrupted failed-directory)) #t)
    (check-equal? (file-exists? (.get interrupted sibling-directory)) #f)
    (def residual-marker
      (path-expand "partial/input" (.get interrupted failed-directory)))
    (with-retry Fixture probe
      (lambda (retry)
        (set! retry-root (.get retry root))
        (check-equal? (equal? retry-root owner-root) (eq? retry probe))
        (set! recovered (.call retry .verify))
        (check-distinct-verification-state interrupted recovered
          (if (eq? phase 'body) 1 0))
        (check-equal? (.get recovered owner-root) retry-root)
        (check-equal? (file-exists? (.get recovered failed-directory)) #f)
        (check-equal? (file-exists? (.get recovered sibling-directory)) #f)
        (check-equal? (file-exists? (.get interrupted failed-directory)) #t)
        (check-equal? (call-with-input-file residual-marker read-line) "partial")))
    (check-equal? checkpoints 2)
    (check-equal? (eq? caught interruption) #t)
    (check-equal? (file-exists? retry-root) (equal? retry-root owner-root))
    (check-equal? (file-exists? owner-root) #t)
    (check-equal? (call-with-input-file residual-marker read-line) "partial")
    (check-equal? (call-with-input-file marker read-line) "keep"))
  (check-equal? (file-exists? owner-root) #f)
  (check-equal? (file-exists? retry-root) #f)
  (for-each
    (lambda (observation)
      (for-each
        (lambda (field)
          (check-equal? (file-exists? (.ref observation field)) #f))
        '(failed-directory sibling-directory)))
    (list interrupted recovered))
  (check-equal? (file-exists? control-root) #t)
  (check-equal? (call-with-input-file marker read-line) "keep"))

(def service-publication-fixture-test
  (test-suite "Native service Fixture ownership"
    (yuanxu-test-fixture "declaration is inert and cached acquire creates independently owned resources"
      (control DirectoryFixture)
      (def preparations 0)
      (def first-root #f)
      (def second-root #f)
      (.def (Observed @ DirectoryFixture)
        .prepare: (lambda (resource) (set! preparations (+ preparations 1)) resource))
      (check-equal? (eq? (.get Observed .acquire) (.get Observed .acquire)) #t)
      (check-equal? preparations 0)
      (with-yuanxu-fixture (first Observed)
        (set! first-root (.get first root))
        (write-source (path-expand "first/nested/input.json" first-root) "{}")
        (with-yuanxu-fixture (second Observed)
          (set! second-root (.get second root))
          (check-equal? (equal? first-root second-root) #f)
          (write-source (path-expand "second/input.json" second-root) "{}"))
        (check-equal? (file-exists? second-root) #f)
        (check-equal? (file-exists? first-root) #t))
      (check-equal? preparations 2)
      (check-equal? (file-exists? first-root) #f)
      (check-equal? (file-exists? (.get control root)) #t))
    (yuanxu-test-fixture "a real service body failure cleans its tree and a later acquisition still admits"
      (control DirectoryFixture)
      (def sentinel (gensym 'body-failure))
      (def failed-root #f)
      (def healthy-root #f)
      (def caught
        (with-catch values
          (lambda ()
            (with-yuanxu-fixture (resource ServicesFixture)
              (set! failed-root (.get resource root))
              (check-equal? (file-exists? (path-expand "modules/services/postgresql/postgresql.json" failed-root)) #t)
              (write-source (path-expand "partial/nested/result" failed-root) "partial")
              (raise sentinel)))))
      (check-equal? (eq? caught sentinel) #t)
      (check-equal? (file-exists? failed-root) #f)
      (with-yuanxu-fixture (resource ServicesFixture)
        (set! healthy-root (.get resource root))
        (check-equal? (equal? failed-root healthy-root) #f)
        (def publication (.get resource publication))
        (def evidence
          (.call (.get publication contract) .admit
            (.get publication value) (.get publication context)))
        (check-equal? (.get evidence accepted?) #t))
      (check-equal? (file-exists? healthy-root) #f)
      (check-equal? (file-exists? (.get control root)) #t))
    (yuanxu-test-fixture "failed relocated preparation rolls back before returning a resource"
      (control DirectoryFixture)
      (def sentinel (gensym 'preparation-failure))
      (def failed-root #f)
      (def released? #f)
      (def (fail-after-preparation prepare)
        (lambda (resource)
          (set! failed-root (.get resource root))
          (def prepared (prepare resource))
          (check-equal? (file-exists? (path-expand "init.ss" (.get prepared source))) #t)
          (check-equal? (file-exists? (path-expand "modules" failed-root)) #f)
          (raise sentinel)))
      (.def (Broken @ RelocatedServicesFixture)
        (.prepare => fail-after-preparation)
        .release: (lambda (_resource) (set! released? #t)))
      (def caught
        (with-catch values
          (lambda ()
            (with-yuanxu-fixture (_resource Broken)
              (error "failed acquisition unexpectedly returned")))))
      (check-equal? (eq? caught sentinel) #t)
      (check-equal? released? #f)
      (check-equal? (file-exists? failed-root) #f)
      (check-equal? (file-exists? (.get control root)) #t))
    (yuanxu-test-fixture "preparation and rollback failures preserve causes and sibling ownership"
      (probe (.cc DirectoryFailureFixture failure-phase: 'preparation))
      (.call probe .verify))
    (yuanxu-test-fixture "body and release failures preserve causes and sibling ownership"
      (probe (.cc DirectoryFailureFixture failure-phase: 'body))
      (.call probe .verify))
    (yuanxu-test-fixture "two verifies of the same resource keep fresh exceptions counters and directories"
      (control DirectoryFixture)
      (for-each
        (lambda (phase)
          (with-yuanxu-fixture
            (probe (.cc DirectoryFailureFixture failure-phase: phase
                     prefix: (path-expand "repeat-" (.get control root))))
            (check-equal? (eq? (.get probe .verify) (.get probe .verify)) #t)
            (def first (.call probe .verify))
            (def second (.call probe .verify))
            (check-independent-verifications first second (if (eq? phase 'body) 1 0))
            (check-equal? (.get first owner-root) (.get probe root))
            (check-equal? (.get second owner-root) (.get probe root))))
        '(preparation body)))
    (yuanxu-test-fixture "independent acquisitions of one Fixture isolate their verification state"
      (control DirectoryFixture)
      (for-each
        (lambda (phase)
          (def Fixture
            (.cc DirectoryFailureFixture failure-phase: phase
              prefix: (path-expand "independent-" (.get control root))))
          (def first-root #f)
          (def second-root #f)
          (with-yuanxu-fixture (first Fixture)
            (set! first-root (.get first root))
            (def first-observation (.call first .verify))
            (with-yuanxu-fixture (second Fixture)
              (set! second-root (.get second root))
              (check-equal? (equal? (.get first root) second-root) #f)
              (def second-observation (.call second .verify))
              (check-independent-verifications first-observation second-observation
                (if (eq? phase 'body) 1 0))
              (check-equal? (.get first-observation owner-root) (.get first root))
              (check-equal? (.get second-observation owner-root) second-root))
            (check-equal? (file-exists? second-root) #f)
            (check-equal? (file-exists? (.get first root)) #t))
          (check-equal? (file-exists? first-root) #f)
          (check-equal? (file-exists? second-root) #f))
        '(preparation body)))
    (yuanxu-test-fixture "interrupted verification leaves residual cleanup to its outer owner"
      (control DirectoryFixture)
      (def marker (path-expand "keep/input" (.get control root)))
      (write-source marker "keep")
      (for-each
        (lambda (phase)
          (def sentinel (gensym 'verification-interrupted))
          (def observed #f)
          (def probe-root #f)
          (def (interrupt observation)
            (set! observed observation)
            (check-equal? (file-exists? (.get observation failed-directory)) #t)
            (check-equal? (file-exists? (.get observation sibling-directory)) #t)
            (raise sentinel))
          (def caught
            (with-catch values
              (lambda ()
                (with-yuanxu-fixture
                  (probe (.cc DirectoryFailureFixture failure-phase: phase
                           prefix: (path-expand "interrupted-" (.get control root))
                           .after-failure: interrupt))
                  (set! probe-root (.get probe root))
                  (.call probe .verify)))))
          (check-equal? (eq? caught sentinel) #t)
          (check-equal? (.get observed owner-root) probe-root)
          (check-equal? (file-exists? probe-root) #f)
          (check-equal? (file-exists? (.get observed failed-directory)) #f)
          (check-equal? (file-exists? (.get observed sibling-directory)) #f)
          (check-equal? (file-exists? (.get control root)) #t)
          (check-equal? (call-with-input-file marker read-line) "keep"))
        '(preparation body)))
    (yuanxu-test-fixture "same resource verifies again without consuming interrupted residuals"
      (control DirectoryFixture)
      (for-each
        (lambda (phase)
          (check-interrupted-recovery control phase retry-same-resource))
        '(preparation body)))
    (yuanxu-test-fixture "same Fixture reacquires without consuming another owner's interrupted residuals"
      (control DirectoryFixture)
      (for-each
        (lambda (phase)
          (check-interrupted-recovery control phase retry-acquired-resource))
        '(preparation body)))))
