;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Core-owned native build completion; never intercept Gerbil loading.
(import :clan/poo/object
        (only-in :std/string/path path-force-extension)
        (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :std/io/tempfile make-temporary-file-name call-with-temporary-directory)
        (only-in :std/misc/ports read-all-as-u8vector read-all-as-string)
        (only-in :std/misc/process run-process)
        (only-in :yuanxu/module-system/source/admission module-source-type module-source-admit-current!))
(export call-with-build-artifact-issuance admit-build-artifacts! invalidate-build-artifacts! clean-build-artifacts!
        current-build-output-directory run-build-artifact-process
        accept-build-artifact-handoff! read-build-artifact-handoff
        build-artifact-publication-current admit-build-artifact-publication!
        build-artifact-handoff)

;; Retained job results are authoritative; the exported record is not an issuer.
;; Keys are exact build Graph receivers, not names or mutable disk labels.
(defstruct issued-build (generation identities inputs libdir files record record-digest approval-current package-current) transparent: #f)
;; Approval guards retain the selected external Source, not this Graph. A saved
;; publication keeps its own receiver alive; guards must not capture that key.
(def issued (make-hash-table-eq weak-keys: #t))
(def restoring (make-parameter '()))
;; Native make consumes an output DIRECTORY, not an asserted trust flag. Fresh
;; ownership makes missing outputs trigger the installed compiler naturally.
(def current-build-output-directory (make-parameter #f))
(def (digest-file path)
  (unless (eq? (module-source-type path) 'regular)
    (error "compiled artifact is missing, non-regular or a symlink" path))
  (hex-encode (sha256 (call-with-input-file path read-all-as-u8vector))))
(def (numeric? text)
  (and (not (string-empty? text)) (andmap char-numeric? (string->list text))))
(def (output-stem file)
  (let (suffix (find (cut string-suffix? <> file) '(".ssxi.ss" ".ssi" ".scm" ".c")))
    (if suffix (substring file 0 (- (string-length file) (string-length suffix)))
      (let (dot (string-rindex file #\.))
        (and dot (string-prefix? ".o" (substring file dot (string-length file)))
             (numeric? (substring file (+ dot 2) (string-length file)))
             (substring file 0 dot))))))
(def (selected-stem? stem names)
  (and stem
    (or (hash-key? names stem)
        (let (separator (string-rindex stem #\~))
          (and separator (selected-stem? (substring stem 0 separator) names))))))
(def (artifact-files identities libdir (complete? #t))
  ;; Index selected names, then visit each selected directory ONCE per check.
  ;; Native named runtime sections (name~Type~0) belong to that selected unit.
  (def directories (make-hash-table))
  (for-each (lambda (identity)
    (def base (path-expand (symbol->string identity) libdir))
    (def directory (path-directory base))
    (when (and complete?
               (not (and (file-exists? (string-append base ".ssi"))
                         (file-exists? (string-append base ".o1")))))
      (error "build-required: selected compiler output is missing" identity))
    (unless (hash-key? directories directory)
      (hash-put! directories directory (make-hash-table)))
    (hash-put! (hash-ref directories directory) (path-strip-directory base) #t))
    identities)
  (def files '())
  (hash-for-each (lambda (directory names)
    (for-each (lambda (file)
      (when (selected-stem? (output-stem file) names)
        (set! files (cons (path-expand file directory) files))))
      (if (file-exists? directory) (directory-files directory) '()))) directories)
  ;; Installed std/make's gxc-outputs requires BOTH .ssi and a static .scm.
  ;; A fresh publication must not depend on leftovers from an earlier raw build.
  ;; Inspect exact selected paths only; do not traverse the static catalogue.
  (def static-owners (make-hash-table))
  (for-each
    (lambda (identity)
      (def path (path-expand
        (path-force-extension
          (string-append "static/"
            (string-join (string-split (symbol->string identity) #\/) "__")) ".scm") libdir))
      (when (and (hash-key? static-owners path)
                 (not (eq? (hash-ref static-owners path) identity)))
        (error "selected compiler identities share a static output" identity))
      (hash-put! static-owners path identity)
      (let (type (module-source-type path))
        (when (or complete? type)
          (unless (eq? type 'regular)
            (error "build-required: selected compiler static output is missing" identity))
          (set! files (cons path files))))) identities)
  (list-sort string<? files))
(def (clean-build-artifacts! identities libdir)
  ;; Native clean can leave hot-import .oN generations and obsolete named
  ;; runtime sections. Explicit Core clean owns this exact selected family.
  (for-each
    (lambda (path)
      (unless (eq? (module-source-type path) 'regular)
        (error "selected compiler output is not a regular file" path))
      (delete-file path))
    (artifact-files identities libdir #f)))
(def (observed-files identities libdir)
  (map (lambda (path) (cons path (digest-file path))) (artifact-files identities libdir)))
(def (invalidate-build-artifacts! graph)
  (hash-put! issued graph 'build-required))
(def (retain-inputs inputs)
  (map (lambda (entry)
    (cons (string-copy (car entry)) (and (cdr entry) (string-copy (cdr entry))))) inputs))
(def (ordinary-object-generation? path)
  (let (extension (path-extension path))
    (or (not (string-prefix? ".o" extension)) (equal? extension ".o1"))))
(def (publish-products files staging libdir)
  (def prefix (string-append (path-strip-trailing-directory-separator (path-expand staging)) "/"))
  (map (lambda (row)
    (def source (car row))
    (unless (string-prefix? prefix source) (error "compiler output escaped its build directory" source))
    (def data (call-with-input-file source read-all-as-u8vector))
    (unless (equal? (hex-encode (sha256 data)) (cdr row))
      (error "compiler output changed during publication" source))
    (def target (path-expand (substring source (string-length prefix) (string-length source)) libdir))
    (create-directory* (path-directory target))
    (when (and (module-source-type target) (not (eq? (module-source-type target) 'regular)))
      (error "compiler output target is not a regular file" target))
    (call-with-output-file (list path: target truncate: #t)
      (lambda (port) (write-subu8vector data 0 (u8vector-length data) port)))
    (cons target (cdr row))) files))
(def (admit-build-artifacts! graph)
  ;; Only an explicitly selected upstream publication can recover this receiver.
  ;; Normal source-only graphs have no recovery effect. Recursive recovery is
  ;; refused before demanding the Source, not handled by an implicit fallback.
  (unless (hash-get issued graph)
    (when (.slot? graph 'build-publication)
      (when (memq graph (restoring)) (error "recursive Core build recovery"))
      (parameterize ((restoring (cons graph (restoring))))
        (with-catch
          (lambda (failure) (invalidate-build-artifacts! graph) (raise failure))
          (lambda ()
            (let (source (.get graph build-publication))
              (when source
                (.call source .restore-build graph)
                (unless (issued-build? (hash-get issued graph))
                  (error "selected build publication did not restore issuance")))))))))
  (let (state (hash-get issued graph))
    ;; No issued build means ordinary source publication. Native loader cache
    ;; state does not grant Core publication authority and is not inspected.
    (when state
      (unless (issued-build? state) (error "build-required: Core build did not complete"))
      ((issued-build-approval-current state))
      ((.get graph compiler-current))
      (unless (equal? (.get graph generation) (issued-build-generation state))
        (error "Core build belongs to a different source generation"))
      (module-source-admit-current! (issued-build-inputs state) "Core compiled source changed")
      (unless (equal? (digest-file (issued-build-record state)) (issued-build-record-digest state))
        (error "Core build issuance record changed" (issued-build-record state)))
      (unless (equal? (observed-files (issued-build-identities state) (issued-build-libdir state))
                      (issued-build-files state))
        (error "Core compiled artifacts changed"))
      (module-source-admit-current! (issued-build-inputs state) "Core compiled source changed")
      ((.get graph compiler-current))
      ((issued-build-approval-current state)))))

;; Effectful package checks belong to root publication boundaries, never to
;; the source-read cache used by nested Contract analysis.
(def (build-artifact-publication-current graph)
  (def state (hash-get issued graph))
  (and (issued-build? state)
       (not (eq? (issued-build-package-current state) void))
       (issued-build-package-current state)))
(def (admit-build-artifact-publication! graph)
  (admit-build-artifacts! graph)
  (def check! (build-artifact-publication-current graph))
  (when check! (check!))
  (admit-build-artifacts! graph))

;; Internal build-supervisor protocol, NOT a disk-record import API. The parent
;; owns the child's stdin pipe and sends retained issuance, never disk-derived
;; expectations. Both executables and the host/process channel remain trusted.
(def (build-artifact-handoff graph libdir)
  (admit-build-artifacts! graph)
  (def state (hash-get issued graph))
  (unless (and (issued-build? state)
               (equal? libdir (issued-build-libdir state)))
    (error "build-required: no completed build for process handoff"))
  ;; A wire value must not expose mutable references to private expectations.
  (call-with-input-string
    (call-with-output-string
      (lambda (port)
        (write (list 'yuanxu-build-handoff-v1
                     (issued-build-identities state) (issued-build-inputs state)
                     libdir (issued-build-files state)
                     (issued-build-record state) (issued-build-record-digest state)) port)))
    read))
(def (run-build-artifact-process projection libdir command)
  (def graph (.get projection build-graph))
  (admit-build-artifact-publication! graph)
  (def packet (build-artifact-handoff graph libdir))
  (def transcript #f)
  (def result
    (run-process command
      check-status: (lambda (status _settings)
        (unless (zero? status) (error "Core build worker failed" status transcript)))
      coprocess: (lambda (process)
        (write packet process) (newline process) (force-output process)
        (close-output-port process)
        (set! transcript (read-all-as-string process))
        transcript)))
  ;; Child execution is an effect boundary; never reuse its entry check here.
  (admit-build-artifact-publication! graph)
  result)

(def (read-build-artifact-handoff)
  (def packet (read))
  (unless (and (list? packet) (= (length packet) 7)
               (eq? (car packet) 'yuanxu-build-handoff-v1)
               (eof-object? (read))
               (list? (list-ref packet 1)) (andmap symbol? (list-ref packet 1))
               (list? (list-ref packet 2))
               (andmap (lambda (row) (and (pair? row) (string? (car row))
                                          (or (not (cdr row)) (string? (cdr row)))))
                       (list-ref packet 2))
               (string? (list-ref packet 3)))
    (error "invalid Core build handoff"))
  packet)
(def (accept-build-artifact-handoff! projection libdir (approval-current! void) (package-current! void))
  (def graph (.get projection build-graph))
  (when (hash-get issued graph)
    (error "build handoff cannot replace an existing graph issuance"))
  ;; Refusal must not turn the same graph back into source-only publication.
  (invalidate-build-artifacts! graph)
  (def packet (read-build-artifact-handoff))
  ((.get projection admit-current))
  (unless (and (equal? (list-ref packet 1) (.get projection compiler-identities))
               (equal? (list-ref packet 2) (.get projection source-inputs))
               (equal? (list-ref packet 3) libdir))
    (error "Core build handoff does not match selected projection"))
  ;; Graph generations are process-local. Rebind only after matching the exact
  ;; selected compiler identities, source observations and output directory.
  (def generation (.get graph generation))
  (hash-put! issued graph
    (make-issued-build
      (if (string? generation) (string-copy generation) generation)
      (list-ref packet 1) (list-ref packet 2) libdir
      (list-ref packet 4) (list-ref packet 5) (list-ref packet 6) approval-current! package-current!))
  (with-catch
    (lambda (failure) (invalidate-build-artifacts! graph) (raise failure))
    (lambda ()
      (admit-build-artifacts! graph)
      ((.get projection admit-current)))))
(def (call-with-build-artifact-issuance projection libdir action)
  (def graph (.get projection build-graph))
  ((.get projection admit-current))
  (def previous (hash-get issued graph))
  ;; Recompilation is not permission to discard a restored release's approval.
  (def approval-current! (if (issued-build? previous)
                          (issued-build-approval-current previous) void))
  (def package-current! (if (issued-build? previous)
                         (issued-build-package-current previous) void))
  (package-current!)
  (def reusable?
    (and (issued-build? (hash-get issued graph))
         (with-catch (lambda (_failure) #f)
           (lambda () (admit-build-artifacts! graph) #t))))
  (invalidate-build-artifacts! graph)
  (def (complete output)
   (parameterize ((current-build-output-directory output))
    (call-with-values action
    (lambda results
      ((.get projection admit-current))
      (def identities (.get projection compiler-identities))
      (def produced (observed-files identities output))
      ;; This adapter owns ordinary native gxc .o1 outputs. A later generation
      ;; cannot be blessed just because it was already beside a fresh .o1.
      ;; Preserve it and require an explicit clean/rebuild; never delete another
      ;; job's output or infer producer identity from a writable record.
      (unless (andmap (lambda (row) (ordinary-object-generation? (car row))) produced)
        (error "build-required: unissued native object generation; clean selected outputs"))
      (def files (if reusable? produced (publish-products produced output libdir)))
      (def published (observed-files identities libdir))
      (unless (equal? files published)
        (error "build-required: selected outputs outside completed build; clean selected outputs"
               (list 'missing (filter (lambda (row) (not (assoc (car row) published))) files))
               (list 'unissued (filter (lambda (row) (not (assoc (car row) files))) published))
               (list 'changed
                     (filter (lambda (row)
                               (let (actual (assoc (car row) published))
                                 (and actual (not (equal? (cdr row) (cdr actual)))))) files))))
      (when (and (issued-build? previous) (not (eq? package-current! void))
                 (not (equal? published (issued-build-files previous))))
        (error "approved Core build outputs changed; require a new publication"))
      (create-directory* libdir)
      (def record (make-temporary-file-name (path-expand ".yuanxu-build-issuance-" libdir)))
      (call-with-output-file (list path: record truncate: #t)
        (lambda (port)
          (write (list 'yuanxu-build-v1 (.get graph generation) files) port)
          (newline port)))
      (def generation (.get graph generation))
      (def state (make-issued-build
                    (if (string? generation) (string-copy generation) generation)
                    (append identities '()) (retain-inputs (.get projection source-inputs))
                    libdir files record (digest-file record) approval-current! package-current!))
      (hash-put! issued graph state)
      (with-catch
        (lambda (failure) (invalidate-build-artifacts! graph) (raise failure))
        (lambda () (admit-build-artifact-publication! graph)))
      (apply values results)))))
  (if reusable? (complete libdir)
    (call-with-temporary-directory "core-build-output-" complete)))
