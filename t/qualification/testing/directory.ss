;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Directory ownership and failure controls, independent of service publications.
(import :clan/poo/object
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :std/error Error? Error-message Error-irritants)
        (only-in :std/test check-equal?)
        (only-in :yuanxu/observability/testing-fixture with-yuanxu-fixture))
(export DirectoryFixture DirectoryFailureFixture write-source)

(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def (rollback-directory! remove-directory root cause)
  (with-catch
    (lambda (cleanup) (error "fixture preparation and rollback failed" cause cleanup))
    (lambda () (remove-directory root)))
  (raise cause))

(.def DirectoryFixture
  prefix: "core-service-"
  .prepare: values
  .remove-directory: clear-temporary-file!
  .acquire:
  (lambda ()
    (def directory (make-temporary-file-name prefix))
    ;; Only a successfully created directory is owned by this acquisition.
    (create-directory directory)
    (with-catch (cut rollback-directory! .remove-directory directory <>)
      (lambda ()
        (def resource (.prepare (.o root: directory)))
        (unless (and (object? resource) (.slot? resource 'root)
                     (equal? (.get resource root) directory))
          (error "fixture preparation must retain its owned root"))
        resource)))
  .release: (lambda (resource) (.remove-directory (.get resource root))))

;; All mutable observations belong to one explicit verification, never cached
;; on a Fixture prototype. The outer workspace owns every injected-failure path.
(def (check-dual-failure failure message primary secondary)
  (check-equal? (Error? failure) #t)
  (check-equal? (Error-message failure) message)
  (def causes (Error-irritants failure))
  (check-equal? (length causes) 2)
  (check-equal? (eq? (car causes) primary) #t)
  (check-equal? (eq? (cadr causes) secondary) #t))

(def (verify-directory-failure workspace phase checkpoint)
  (def root (.get workspace root))
  (with-yuanxu-fixture
    (sibling (.cc DirectoryFixture prefix: (path-expand "sibling-" root)))
    (def primary (with-catch values (lambda () (error "injected primary failure" phase))))
    (def secondary (with-catch values (lambda () (error "injected cleanup failure" phase))))
    (def failed-root #f)
    (def cleanup-targets '())
    (def releases 0)
    (def marker (path-expand "keep/input" (.get sibling root)))
    (write-source marker "keep")
    (def (observe-release release)
      (lambda (resource)
        (set! releases (+ releases 1))
        (release resource)))
    (.def (Broken @ DirectoryFixture)
      prefix: (path-expand "broken-" root)
      .prepare:
      (lambda (resource)
        (set! failed-root (.get resource root))
        (write-source (path-expand "partial/input" failed-root) "partial")
        (when (eq? phase 'preparation) (raise primary))
        resource)
      .remove-directory:
      (lambda (directory)
        (set! cleanup-targets (cons directory cleanup-targets))
        (raise secondary))
      (.release => observe-release))
    (def caught
      (with-catch values
        (lambda ()
          (with-yuanxu-fixture (_resource Broken)
            (unless (eq? phase 'body)
              (error "failed preparation unexpectedly returned"))
            (raise primary)))))
    (check-dual-failure caught
      (case phase
        ((preparation) "fixture preparation and rollback failed")
        ((body) "fixture body and cleanup failed"))
      primary secondary)
    (check-equal? releases (if (eq? phase 'body) 1 0))
    (check-equal? cleanup-targets (list failed-root))
    (check-equal? (equal? failed-root (.get sibling root)) #f)
    (check-equal? (file-exists? failed-root) #t)
    (def observation
      (.o owner-root: root
          failure-phase: phase
          failure: caught
          primary-error: primary
          secondary-error: secondary
          failed-directory: failed-root
          sibling-directory: (.get sibling root)
          release-count: releases
          cleanup-paths: cleanup-targets))
    ;; Test-only checkpoint: an interruption here leaves the broken directory
    ;; for the outer resource owner, while sibling dynamic-wind still releases.
    (checkpoint observation)
    (.call DirectoryFixture .release (.o root: failed-root))
    (check-equal? (file-exists? failed-root) #f)
    (check-equal? (file-exists? (.get sibling root)) #t)
    (check-equal? (call-with-input-file marker read-line) "keep")
    (check-equal? (file-exists? root) #t)
    observation))

(.def (DirectoryFailureFixture @ DirectoryFixture)
  failure-phase: 'preparation
  .after-failure: values
  .prepare:
  (lambda (workspace)
    (unless (memq failure-phase '(preparation body))
      (error "unsupported Fixture failure phase" failure-phase))
    (.cc workspace
      .verify: (lambda () (verify-directory-failure workspace failure-phase .after-failure)))))
