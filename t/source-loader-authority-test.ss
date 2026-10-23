;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Native loader SOURCE compiled before procedure capture; no SDK rebinding.
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :std/encoding/json write-json)
        (only-in :std/misc/ports read-all-as-u8vector)
        (only-in :std/io/tempfile call-with-temporary-file-name)
        (only-in :clan/poo/slot-observation call-with-slot-read-observer)
        (only-in :gerbil/runtime/loader load-module load-path set-load-path!)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/t/qualification/service-publication/fixtures DirectoryFixture)
        "qualification/mop-state/artifact-authority"
        "qualification/mop-state/artifact-closure")
(export source-loader-authority-test test-cleanup!)
(extern namespace: #f
  yuanxu/t/qualification/mop-state/source-loader#load-module
  yuanxu/t/qualification/mop-state/source-loader#reload-module!
  yuanxu/t/qualification/mop-state/source-loader#set-load-path!)
(extern namespace: yuanxu/t/qualification/mop-state/precompiled-stores
  precompiled-subjects precompiled-store)
(def root (path-expand (getenv "CORE_STORE_ROOT")))
(def original-path (load-path))
(def old-sdk-entry load-module)
(def observations '())
(.def (SourceLoaderFixture @ DirectoryFixture)
  prefix: (path-expand "source-issuer-" root)
  .prepare:
  (lambda (resource)
    (.cc resource issuer: (compile-authority (.get resource root)))))
(create-directory* root)
(def resource (.call SourceLoaderFixture .acquire))
(def state (.get resource issuer))
(displayln "AUTHORITY-PHASE fixture-ready") (force-output)
(def artifacts (authority-artifacts state))
(def entry "yuanxu/t/qualification/mop-state/precompiled-stores")
(def (bytes path) (call-with-input-file path read-all-as-u8vector))
(def (write-bytes path data)
  ;; Replace the pathname, not the backing inode of a resident ELF mapping.
  ;; In-place truncation can crash Linux before the admission is exercised.
  ;; Bytes/record tampering and restoration still pass through every guard.
  (call-with-temporary-file-name (string-append path ".replacement-")
    (lambda (temporary)
      (call-with-output-file temporary
        (lambda (port) (write-subu8vector data 0 (u8vector-length data) port)))
      (rename-file temporary path #t))))
(def (expect-refusal label invoke)
  (def before (length (.get (authority-status state) consumed)))
  (def events-before (length (.get (authority-status state) events)))
  (def result (with-catch values (cut invoke entry)))
  (check-equal? (Error? result) #t)
  (check-equal? (Error-message result) "issued source or record changed")
  (check-equal? (length (.get (authority-status state) consumed)) before)
  (set! observations (cons
    (vector label (Error-message result)
      (- (length (.get (authority-status state) events)) events-before)
      (- (length (.get (authority-status state) consumed)) before)) observations)))
(def source-loader-authority-test
 (test-suite "Native-source loader call edges"
  (yuanxu-test-case "saved compiled entry and reload retain admission"
    (prepare-source-authority! state)
    (yuanxu/t/qualification/mop-state/source-loader#set-load-path! (load-path))
    ;; Capture the actual compiled native entry BEFORE first target loading.
    (def saved yuanxu/t/qualification/mop-state/source-loader#load-module)
    (check-equal? (eq? load-module old-sdk-entry) #t)
    (displayln "AUTHORITY-PHASE saved-entry-start") (force-output)
    (check-equal? (string? (saved entry)) #t)
    (displayln "AUTHORITY-PHASE saved-entry-complete") (force-output)
    (def loaded-count (length (.get (authority-status state) consumed)))
    (def before (length (.get (authority-status state) events)))
    (check-equal? (string? (saved entry)) #t)
    (check-equal? (> (length (.get (authority-status state) events)) before) #t)
    (check-equal? (length (.get (authority-status state) consumed)) loaded-count)
    (set! observations (cons
      (vector "saved-hot-valid" ""
        (- (length (.get (authority-status state) events)) before)
        (- (length (.get (authority-status state) consumed)) loaded-count)) observations))
    (def record (path-expand "compiler-closure.ss" artifacts))
    (def original-record (bytes record))
    (def binary (path-expand (string-append "lib/" entry "~0.o1") artifacts))
    (def original-binary (bytes binary))
    (dynamic-wind
      (lambda ()
        (write-bytes binary (bytes (path-expand
          "lib/yuanxu/t/qualification/mop-state/unlowered-store~0.o1" artifacts)))
        (call-with-output-file (list path: record truncate: #t)
          (cut write (compiler-code-facts entry '()) <>)))
      (lambda ()
        (expect-refusal "saved-hot-changed-record" saved)
        (expect-refusal "direct-hot-changed-record"
          yuanxu/t/qualification/mop-state/source-loader#load-module)
        ;; Same-path reload is itself a cached early-return path in the SDK.
        (expect-refusal "reload-hot-changed-record"
          yuanxu/t/qualification/mop-state/source-loader#reload-module!))
      (lambda () (write-bytes record original-record) (write-bytes binary original-binary)))
    (check-equal? (string? (saved entry)) #t)
    (check-equal? (eq? load-module old-sdk-entry) #t)
    ;; The genuinely loaded lowered callback still refuses shared-owner writes.
    (def subjects (precompiled-subjects))
    (def Parent (.get subjects parent))
    (def Hot (.get subjects hot))
    (def Cold (.get subjects cold))
    (check-equal? (.get Parent port) 5432)
    (def roots '())
    (call-with-slot-read-observer
      (lambda (read) (set! roots (cons read roots))) (cut .get Hot port))
    (def spec (cdr (assq 'port (object-slots Parent))))
    (def writer (precompiled-store 'generated))
    (def refusal (with-catch values
      (cut replay-slot-reads! roots (lambda (_owner _key) (writer spec (lambda (_self) 5440))))))
    (check-equal? (Error-message refusal) "object mutation during read replay")
    (check-equal? (object-%instance Cold) #f)
    (check-equal? (.get Parent port) 5432)
    (check-equal? (.get Hot port) 5432)
    (check-equal? (.get Cold port) 5432)
    (displayln "SOURCE-LOADER: saved source-built entry, direct entry and reload checked; SDK globals untouched"))))
(def (test-cleanup!)
  (deactivate-authority!)
  (set-load-path! original-path)
  (setenv "CORE_STORE_ROOT" root)
  (call-with-output-file (list path: (path-expand "source-loader-observations.json" root) truncate: #t)
    (lambda (port) (write-json port (list->vector (reverse observations)))))
  (.call SourceLoaderFixture .release resource))
