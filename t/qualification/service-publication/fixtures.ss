;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Test resources only: native POO acquisition/preparation/release, no runner.
(import :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :std/func compose)
        (only-in :std/encoding/json write-json)
        (only-in :std/error Error? Error-message Error-irritants)
        (only-in :yuanxu/observability/testing-fixture with-yuanxu-fixture)
        (only-in :std/test check-equal?)
        (prefix-in :clan/poo/declarative-metadata metadata.)
        (only-in :gerbil/expander eval-syntax current-expander-context make-top-context
                 read-syntax-from-file syntax->list)
        (only-in :yuanxu/admission/publication AdmissionPublication.)
        (only-in :yuanxu/module-system/source/link yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/admission module-source-read))
(export DirectoryFixture DirectoryFailureFixture ServicesFixture RepositoryServicesFixture RelocatedServicesFixture
        relocate-services write-source read-overrides refused)

(def source-root (path-expand "../../../scenarios/gitea-postgresql" (path-directory (this-source-file))))
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

(def (select-services workspace source)
  (def selection (yuanxu-load-modules (path-expand "init.ss" source)))
  (.cc workspace source: source selection: selection
    publication: (.call AdmissionPublication. .for-export selection
                   'applications/gitea-postgresql 'Application)))

(def (prepare-services workspace postgres-ports gitea-ports client-port null-settings?)
  (def root (.get workspace root))
  (write-source (path-expand "gerbil.pkg" root)
    (string-append "(package: " (symbol->string (gensym 'service-test-))
      " prelude: :yuanxu/module-system/source/module-prelude)"))
  ;; Real maintained roles, isolated only for destructive source controls.
  (for-each
    (lambda (name ports)
      (def directory (path-expand (string-append "modules/services/" name) root))
      (for-each
        (lambda (role)
          (def filename (string-append role ".ss"))
          (def source (path-expand (string-append name "/" filename) source-root))
          (when (file-exists? source)
            (write-source (path-expand filename directory) (module-source-read source))))
        '("types" "objects" "func" "config" "interface"))
      (write-source (path-expand (string-append name ".json") directory)
        (call-with-output-string
          (lambda (out)
            (display "{" out)
            (display (if (string=? name "postgresql")
                       (if null-settings? "\"settings\":null" "\"settings\":{\"port\":5432}")
                       "\"database\":{") out)
            (unless (string=? name "postgresql")
              (when client-port
                (display "\"port\":" out)
                (if (eq? client-port 'null) (display "null" out) (write-json out client-port)))
              (display "}" out))
            (display ",\"allowed-ports\":" out)
            (write-json out (list->vector ports))
            (display "}" out)))))
    '("postgresql" "gitea") (list postgres-ports gitea-ports))
  (write-source (path-expand "modules/services/postgresql/unread.json" root) "not JSON")
  (for-each
    (lambda (role)
      (write-source
        (path-expand (string-append "modules/applications/gitea-postgresql/" role ".ss") root)
        (module-source-read
          (path-expand (string-append role ".ss") source-root))))
    '("types" "objects" "config" "interface"))
  (write-source (path-expand "init.ss" root)
    "(yuanxu! mode: explicit (closed-package disable: #t) :services (postgresql) (gitea) (unused disable: #t) :applications (gitea-postgresql))")
  (write-source (path-expand "modules/services/unused/interface.ss" root) "(((cold")
  (select-services workspace root))

(.def (ServicesFixture @ DirectoryFixture)
  postgres-ports: '(5432 5433)
  gitea-ports: '(5432 5433)
  client-port: #f
  null-settings?: #f
  .prepare: (lambda (workspace)
              (prepare-services workspace postgres-ports gitea-ports client-port null-settings?)))

(def (prepare-repository-services workspace)
  (def root (.get workspace root))
  (create-directory* (path-expand "modules" root))
  (write-source (path-expand "gerbil.pkg" root)
    (string-append "(package: " (symbol->string (gensym 'service-defaults-)) ")"))
  (write-source (path-expand "init.ss" root)
    (call-with-output-string
      (lambda (out)
        (display "(yuanxu! mode: explicit :services (postgresql @ " out)
        (write (path-expand "postgresql" source-root) out)
        (display ") (gitea @ " out)
        (write (path-expand "gitea" source-root) out)
        (display ") :applications (gitea-postgresql @ " out)
        (write source-root out)
        (display "))" out))))
  (select-services workspace root))
(.def (RepositoryServicesFixture @ DirectoryFixture)
  .prepare: prepare-repository-services)

(def (relocate-services workspace)
  (def root (.get workspace root))
  (def original (.get workspace selection))
  (def output (path-expand "package" root))
  (def receipt (.call (.get original build-graph) .package output))
  (def moved (path-expand "relocated" root))
  (rename-file output moved)
  (clear-temporary-file! (path-expand "modules" (.get workspace source)))
  (.cc (select-services workspace moved)
    original-selection: original package-receipt: receipt))
(def (relocated-preparation prepare) (compose relocate-services prepare))
(.def (RelocatedServicesFixture @ ServicesFixture)
  (.prepare => relocated-preparation))

;; SDK expansion of real files; no manufactured location rows.
(def (read-overrides path (names '(release explicit)))
  (parameterize ((current-expander-context (make-top-context)))
    (eval-syntax '(import :gerbil/core))
    (eval-syntax '(import :yuanxu/object-syntax/path-slots))
    (for-each eval-syntax (syntax->list (read-syntax-from-file path)))
    (apply values (map eval-syntax names))))
(def (cause failure)
  (if (metadata.failure? failure) (cause (metadata.failure-cause failure)) failure))
(def (refused publication parent candidate (message #f) (expected-source #f))
  (defvalues (receipt next failure) (.call publication .publish parent candidate))
  (check-equal? receipt #f)
  (check-equal? (eq? next parent) #t)
  (check-equal? (metadata.failure? failure) #t)
  (when message
    (check-equal? (and (Error? (cause failure)) (Error-message (cause failure))) message))
  (when expected-source
    (check-equal? (Error-irritants (cause failure))
                  (list (path-normalize expected-source) 'source-bytes-changed))))
