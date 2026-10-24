;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; One trusted compiler child, private in-memory issuance, actual native loader.
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :std/encoding/json write-json)
        (only-in :std/misc/ports read-all-as-u8vector)
        (only-in :clan/poo/slot-observation call-with-slot-read-observer)
        (only-in :gerbil/runtime/loader load-module load-path set-load-path!)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/t/qualification/service-publication/fixtures DirectoryFixture)
        "qualification/mop-state/artifact-authority"
        "qualification/mop-state/artifact-closure")
(export artifact-authority-test test-cleanup!)
(extern namespace: yuanxu/t/qualification/mop-state/precompiled-stores precompiled-store precompiled-subjects)
(def root (path-expand (getenv "CORE_STORE_ROOT")))
(def original-path (load-path))
(def captured-sdk-entry load-module)
(def observations '())
(def legacy-observation #f)
(def entry "yuanxu/t/qualification/mop-state/precompiled-stores")
(def runtime-entry (string-append entry "~0"))
(def prefix "yuanxu/t/qualification/mop-state/")
(def (bytes path) (call-with-input-file path read-all-as-u8vector))
(def (write-bytes path data)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (write-subu8vector data 0 (u8vector-length data) port))))
(def (write-datum path datum)
  (call-with-output-file (list path: path truncate: #t) (cut write datum <>)))
(def (record-hot! receiver observer)
  (call-with-slot-read-observer observer (cut .get receiver port)))
(def (latest phase)
  (let loop ((events (reverse (.get (authority-status state) events))))
    (cond ((null? events) #f)
          ((and (eq? (caar events) phase) (equal? (cadar events) entry)) (caddar events))
          (else (loop (cdr events))))))
(def (observe label accepted transfers)
  (def facts (latest 'authorization))
  (def snapshot (or (latest 'snapshot-check) (vector "" "")))
  (def consumed (latest 'consumed))
  (unless facts (error "missing actual native authorization observation" label))
  (set! observations (cons
    (vector label (vector-ref facts 0) (vector-ref facts 1)
      (vector-ref facts 2) (vector-ref facts 3)
      (vector-ref snapshot 0) (vector-ref snapshot 1)
      accepted transfers (if consumed (vector-ref consumed 2) #t)) observations)))
(.def (AuthorityFixture @ DirectoryFixture)
  prefix: (path-expand "issuer-" root)
  .prepare:
  (lambda (resource)
    (def state (compile-authority (.get resource root)))
    (.cc resource issuer: state)))
;; Native fixture acquisition owns rollback. Compilation is before case
;; execution; the existing whole-test heap/timeout fence remains authoritative.
(create-directory* root)
(def resource (.call AuthorityFixture .acquire))
(def state (.get resource issuer))
(def artifacts (authority-artifacts state))
(def (path name suffix) (path-expand (string-append "lib/" prefix name suffix) artifacts))
(def (attempt label action expected-message)
  (def before (length (.get (authority-status state) consumed)))
  (def result (with-catch values action))
  (def after (length (.get (authority-status state) consumed)))
  (check-equal? (Error? result) #t)
  (check-equal? (Error-message result) expected-message)
  (check-equal? before after)
  (observe label #f (- after before))
  (reset-native-errors! state))
(def artifact-authority-test
 (test-suite "Native issuance and load consumption"
  (yuanxu-test-case "sidecar forgery and actual native transfer seams"
    (install-authority! state)
    ;; Mutate both record and artifact, retaining neither as an authority.
    (def record (path-expand "compiler-closure.ss" artifacts))
    (def binary (path "precompiled-stores" "~0.o1"))
    (def original-record (bytes record))
    (def original-binary (bytes binary))
    (dynamic-wind
      (lambda ()
        (write-bytes binary (bytes (path "unlowered-store" "~0.o1")))
        ;; A structurally coherent fresh record for the modified tree, not an
        ;; invalid syntax marker. It still cannot replace parent pipe issuance.
        (write-datum record (compiler-code-facts entry '())))
      (lambda () (attempt "record-and-binary" (cut load-module entry) "issued source or record changed"))
      (lambda () (write-bytes record original-record) (write-bytes binary original-binary)))
    ;; Native resolver sees a different selected path even for identical bytes.
    (def higher (path "precompiled-stores" ".o2"))
    (dynamic-wind
      (lambda () (write-bytes higher (bytes (path "precompiled-stores" ".o1"))))
      (lambda () (attempt "higher-object" (cut load-module entry) "issued native artifact changed"))
      (lambda () (delete-file higher)))
    ;; After request authorization and native resolution, before the load site.
    (def root-binary (path "precompiled-stores" ".o1"))
    (def root-original (bytes root-binary))
    (dynamic-wind void
      (lambda ()
        (parameterize ((current-transfer-probe
          (lambda (phase name selected)
            (when (and (eq? phase 'resolved) (string=? name entry))
              (write-bytes selected #u8(0))))))
          (attempt "after-resolution" (cut load-module entry) "issued native artifact changed")))
      (lambda () (write-bytes root-binary root-original)))
    (def dependency (path "store-policy" "~0.o1"))
    (def dependency-original (bytes dependency))
    (dynamic-wind void
      (lambda ()
        (parameterize ((current-transfer-probe
          (lambda (phase name _selected)
            (when (and (eq? phase 'snapshot) (string=? name entry))
              (write-bytes dependency #u8(0))))))
          (attempt "dependency-at-handoff" (cut load-module entry) "issued native artifact changed")))
      (lambda () (write-bytes dependency dependency-original)))
    ;; Even after copying verified bytes, a changed source refuses before load.
    (dynamic-wind void
      (lambda ()
        (parameterize ((current-transfer-probe
          (lambda (phase name selected)
            (when (and (eq? phase 'snapshot) (string=? name entry))
              (write-bytes selected #u8(0))))))
          (attempt "after-snapshot" (cut load-module entry) "issued native artifact changed")))
      (lambda () (write-bytes root-binary root-original)))
    ;; The authority-private copy is also checked before native consumption.
    (def pool (authority-private-pool state))
    (def pool-file #f)
    (def pool-original #f)
    (dynamic-wind void
      (lambda ()
        (parameterize ((current-transfer-probe
          (lambda (phase name _selected)
            (when (and (eq? phase 'snapshot) (string=? name entry))
              (set! pool-file (path-expand
                (string-append (file-digest root-binary) "/" (path-strip-directory root-binary)) pool))
              (set! pool-original (bytes pool-file))
              ;; Same-host trusted test has stronger rights than artifact-tree
              ;; writer; permissions alone are NOT a sandbox against it.
              (delete-file pool-file)
              (write-bytes pool-file #u8(0))))))
          (attempt "private-copy-before-consumption" (cut load-module entry) "private native snapshot changed")))
      (lambda ()
        (when pool-file (delete-file pool-file) (write-bytes pool-file pool-original))))
    ;; Unselected module remains outside the resolver/issuer traversal.
    (def unused (path "unselected" ".scm"))
    (write-datum unused '(error "unselected artifact executed"))
    ;; Valid load: after the FINAL source check, replace only public artifact
    ;; bytes. The actual native load consumes the retained private valid copy.
    ;; This is a negative control for latest-path currentness, not an atomicity
    ;; claim. It demonstrates byte-snapshot safety under private-pool authority.
    (dynamic-wind void
      (lambda ()
        (parameterize ((current-transfer-probe
          (lambda (phase name selected)
            (when (and (eq? phase 'consuming) (string=? name entry))
              (write-bytes selected #u8(0))))))
          (load-module entry)))
      (lambda () (write-bytes root-binary root-original)))
    (def transfers (.get (authority-status state) consumed))
    (check-equal? (and (member entry (map cadr transfers)) #t) #t)
    (check-equal? (and (member runtime-entry (map cadr transfers)) #t) #t)
    ;; Invoke the genuinely loaded callback: parent cache and cold receiver.
    (def subjects (precompiled-subjects))
    (def Parent (.get subjects parent))
    (def Hot (.get subjects hot))
    (def Cold (.get subjects cold))
    (.get Parent port)
    (def roots '())
    ;; Native observation helper imported below through its actual API.
    (record-hot! Hot (lambda (read) (set! roots (cons read roots))))
    (def spec (cdr (assq 'port (object-slots Parent))))
    (def writer (precompiled-store 'generated))
    (def refusal (with-catch values
      (cut replay-slot-reads! roots (lambda (_owner _key) (writer spec (lambda (_self) 5440))))))
    (check-equal? (Error-message refusal) "object mutation during read replay")
    (check-equal? (object-%instance Cold) #f)
    (check-equal? (.get Parent port) 5432)
    (check-equal? (.get Hot port) 5432)
    (check-equal? (.get Cold port) 5432)
    (observe "private-snapshot-late-public-change" #t (length transfers))
    (def loaded-count (length (.get (authority-status state) consumed)))
    (check-equal? (string? (load-module entry)) #t)
    (check-equal? (length (.get (authority-status state) consumed)) loaded-count)
    (observe "cached-valid" #t 0)
    ;; Native loaded-module caching must not bypass the issuer on a later hit.
    (dynamic-wind
      (lambda ()
        (write-bytes binary (bytes (path "unlowered-store" "~0.o1")))
        (write-datum record (compiler-code-facts entry '())))
      (lambda ()
        (attempt "cached-record-replacement" (cut load-module entry) "issued source or record changed")
        ;; Measurement, not a claimed safe route: an SDK procedure value saved
        ;; before installation may retain an old compiled internal call edge.
        (def before (length (.get (authority-status state) events)))
        (def result (with-catch values (cut captured-sdk-entry entry)))
        (def after (length (.get (authority-status state) events)))
        (if (Error? result)
          (check-equal? (Error-message result) "issued source or record changed")
          (check-equal? (string? result) #t))
        (set! legacy-observation (vector (not (Error? result)) (> after before))))
      (lambda () (write-bytes record original-record) (write-bytes binary original-binary))))))
(def (test-cleanup!)
  (deactivate-authority!)
  (set-load-path! original-path)
  (setenv "CORE_STORE_ROOT" root)
  (call-with-output-file (list path: (path-expand "authority-observations.json" root) truncate: #t)
    (lambda (port) (write-json port (list->vector (reverse observations)))))
  (call-with-output-file (list path: (path-expand "legacy-dispatch.json" root) truncate: #t)
    (lambda (port) (write-json port legacy-observation)))
  (.call AuthorityFixture .release resource)
  (check-equal? (length observations) 9)
  (displayln "ARTIFACT-AUTHORITY: 9 native controls; late-public-change snapshot limit retained"))
