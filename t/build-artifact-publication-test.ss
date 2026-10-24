;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Installed Gerbil compilation, Core issuance, real service publication.
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :std/misc/ports read-all-as-u8vector)
        (only-in :std/encoding/json write-json)
        (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture with-yuanxu-fixture)
        (only-in :yuanxu/t/qualification/service-publication/fixtures ServicesFixture write-source)
        (only-in :yuanxu/module-system/building/artifacts
          call-with-build-artifact-issuance admit-build-artifacts!
          run-build-artifact-process)
        "./qualification/build-publication/projection"
        (only-in :yuanxu/admission/publication AdmissionPublication.))
(export build-artifact-publication-test test-cleanup!)
(def observations '())
(def handoff-observations '())
(def completed 0)
(def (bytes path) (call-with-input-file path read-all-as-u8vector))
(.def (CompiledServicesFixture @ ServicesFixture)
  .prepare:
  (lambda (workspace)
    (def services (.call ServicesFixture .prepare workspace))
    (def root (.get services root))
    (def prefix (cadr (call-with-input-file (path-expand "gerbil.pkg" root) read)))
    (def identity (string->symbol (string-append (symbol->string prefix) "/probe")))
    (def source (path-expand "probe.ss" root))
    (write-source source "(export answer) (def answer 42)\n")
    (def projection (probe-projection (.get services selection) root identity))
    (def lib (path-expand "lib" root))
    (def run (probe-build root lib))
    (def binary (path-expand (string-append (symbol->string identity) "~0.o1") lib))
    ;; A writable native cache without prior Core issuance cannot be adopted.
    (run "compile")
    (write-artifact-bytes binary #u8(0))
    ;; This is the production completion function used by projection .compile.
    ;; Only the one-unit compiler projection is a fixture; compiler and service
    ;; graph/publication/admission implementations are the installed/real ones.
    (call-with-build-artifact-issuance projection lib (cut run "compile"))
    (check-equal? (equal? (bytes binary) #u8(0)) #f)
    (.cc services lib: lib projection: projection native-main: run
      binary: binary
      record: (path-expand
        (find (cut string-prefix? ".yuanxu-build-issuance-" <>)
          (directory-files (list path: lib ignore-hidden: #f))) lib))))
(def (invoke-publication publish parent candidate)
  (defvalues (receipt next failure) (publish parent candidate))
  (values receipt next failure))
(def build-artifact-publication-test
 (test-suite "Core native-build issuance and cached publication"
  (yuanxu-test-fixture "saved publication rejects joint record/artifact replacement"
    (fixture CompiledServicesFixture)
    (with-slots (selection publication binary record) fixture
      (def Parent (.get publication value))
      (def parent-plan (.get Parent plan))
      (def saved (.get publication .publish))
      (.def (Release @ Parent)
        config: =>.+ (.o postgresql: =>.+ (.o settings: =>.+ (.o port: 5433))))
      (def (accepted label)
        (defvalues (receipt next failure) (invoke-publication saved Parent Release))
        (check-equal? failure #f)
        (check-equal? (.get receipt accepted?) #t)
        (check-equal? (.get next plan postgresql port) 5433)
        (check-equal? (.get next plan gitea database-port) 5433)
        (check-equal? (.get parent-plan postgresql port) 5432)
        (check-equal? (length (.get publication context contributions)) 2)
        (set! observations (cons (vector label (.get receipt accepted?)) observations)))
      (accepted "saved-cold")
      (accepted "saved-hot")
      ;; Fresh exec processes receive authority only over the owned parent pipe.
      (for-each (lambda (mode marker)
        (def output
          (run-build-artifact-process (.get fixture projection) (.get fixture lib)
            (list "just" "build-publication-worker" (.get fixture root) (.get fixture lib)
                  (symbol->string (car (.get fixture projection compiler-identities)))
                  mode record)))
        (check-equal? (not (not (string-contains output marker))) #t)
        (set! handoff-observations
          (cons (vector mode (equal? mode "warm")) handoff-observations)))
        '("warm" "joint" "mismatch")
        '("HANDOFF-WARM-OK" "HANDOFF-JOINT-REFUSED" "HANDOFF-MISMATCH-REFUSED"))
      (def original-binary (bytes binary))
      (def original-record (bytes record))
      (def record-data (call-with-input-file record read))
      (dynamic-wind
        (lambda ()
          (write-artifact-bytes binary #u8(0))
          ;; Coherent record for the changed bytes; neither is authoritative.
          (call-with-output-file (list path: record truncate: #t)
            (lambda (port)
              (write (list (car record-data) (cadr record-data)
                (map (lambda (row)
                  (if (equal? (car row) binary)
                    (cons binary (hex-encode (sha256 #u8(0)))) row))
                  (caddr record-data))) port)
              (newline port))))
        (lambda ()
          (defvalues (receipt next failure) (invoke-publication saved Parent Release))
          (check-equal? receipt #f)
          (check-equal? (eq? next Parent) #t)
          (check-equal? (not (not failure)) #t)
          (set! observations (cons (vector "saved-hot-joint-replacement" (not failure)) observations))
          (def refused (with-catch values
            (cut .call AdmissionPublication. .for-export selection 'applications/gitea-postgresql 'Application)))
          (check-equal? (Error? refused) #t)
          (check-equal? (Error-message refused) "Core build issuance record changed")
          (set! observations (cons (vector "for-export-joint-replacement" (not (Error? refused))) observations)))
        (lambda () (write-artifact-bytes binary original-binary) (write-artifact-bytes record original-record)))
      (accepted "saved-restored")
      ;; Changing only bytes must fail even when the disk record is untouched.
      (dynamic-wind
        (cut write-artifact-bytes binary #u8(0))
        (lambda ()
          (def refused (with-catch values (cut admit-build-artifacts! (.get selection build-graph))))
          (check-equal? (Error-message refused) "Core compiled artifacts changed"))
        (cut write-artifact-bytes binary original-binary))
      ;; Native resolution could select a new .o2; enumerate selected families
      ;; again instead of hashing only the original fixed list.
      (def higher (string-append (substring binary 0 (- (string-length binary) 1)) "2"))
      (dynamic-wind
        (cut write-artifact-bytes higher original-binary)
        (lambda ()
          (def refused (with-catch values (cut admit-build-artifacts! (.get selection build-graph))))
          (check-equal? (Error-message refused) "Core compiled artifacts changed"))
        (cut delete-file higher))
      ;; An unrelated graph/build uses its own output and retained issuance.
      (with-yuanxu-fixture (peer CompiledServicesFixture)
        (admit-build-artifacts! (.get peer selection build-graph))
        (accepted "saved-after-peer-build"))
      (def warm-output
        (call-with-output-string
          (lambda (port)
            (parameterize ((current-output-port port))
              (call-with-build-artifact-issuance (.get fixture projection) (.get fixture lib)
                (cut (.get fixture native-main) "compile"))))))
      (check-equal? (not (not (string-contains warm-output "... compile probe"))) #f)
      (check-equal? (bytes binary) original-binary)
      (def probe-source (path-expand "probe.ss" (.get fixture root)))
      (def original-source (bytes probe-source))
      (dynamic-wind void
        (lambda ()
          (def refused (with-catch values
            (cut run-build-artifact-process (.get fixture projection) (.get fixture lib)
              (list "just" "build-publication-worker" (.get fixture root) (.get fixture lib)
                    (symbol->string (car (.get fixture projection compiler-identities)))
                    "source-change" record))))
          (check-equal? (Error? refused) #t)
          (check-equal? (Error-message refused) "Core compiled source changed")
          (set! handoff-observations
            (cons (vector "source-change" #f) handoff-observations)))
        (cut write-artifact-bytes probe-source original-source))
      ;; A failed attempt cannot fall back to the prior successful seal.
      (def failed (with-catch values
        (cut call-with-build-artifact-issuance (.get fixture projection) (.get fixture lib)
          (lambda () (error "native build failed")))))
      (check-equal? (Error-message failed) "native build failed")
      (def blocked (with-catch values (cut admit-build-artifacts! (.get selection build-graph))))
      (check-equal? (Error-message blocked) "build-required: Core build did not complete")
      (set! completed (+ completed 1))))))
(def (test-cleanup!)
  (check-equal? completed 1)
  (let (trace (getenv "CORE_BUILD_HANDOFF_TRACE" #f))
    (when trace
      (call-with-output-file (list path: trace truncate: #t)
        (lambda (port) (write-json port (list->vector (reverse handoff-observations)))))))
  (let (trace (getenv "CORE_BUILD_PUBLICATION_TRACE" #f))
    (when trace
      (call-with-output-file (list path: trace truncate: #t)
        (lambda (port) (write-json port (list->vector (reverse observations)))))))
  (displayln "CORE-BUILD-PUBLICATION: installed compiler, saved publication, independent builds and failed-build refusal"))
