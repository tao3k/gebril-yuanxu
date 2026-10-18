;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object
        (only-in :std/misc/process run-process)
        (only-in :std/string/misc string-subst)
        (only-in :std/encoding/json write-json)
        (only-in :core/module-system/source/admission module-source-type module-source-read)
        (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode))
(export poo-flow-core-nix-flake-source-inputs poo-flow-core-nix-flake-instantiate current-nix-process-observer current-nix-process-completion-observer poo-flow-core-nix-instantiate poo-flow-core-nix-realize poo-flow-core-nix-source-inputs call-with-nix-derivation-query)
;; Optional build-tool observability at the actual process boundary. No cache or
;; Provider-specific instrumentation; default execution has no observer.
(def current-nix-process-observer (make-parameter #f))
(def current-nix-process-completion-observer (make-parameter #f))
;; A check evaluates the same function/arguments but must not register the same
;; derivation again. This is a process mode, not a currentness/evidence cache.
;; Keep dispatch through Source.instantiate so specialized Sources retain their
;; own identity rules (Flake Sources already use nix eval).
(def nix-derivation-query? (make-parameter #f))
(def (call-with-nix-derivation-query thunk)
  (parameterize ((nix-derivation-query? #t)) (thunk)))
(def (call-with-nix-process-observation argv thunk)
  (let (observer (current-nix-process-completion-observer))
    (if (not observer) (thunk)
      (let ((started (real-time)) (completed? #f))
        (dynamic-wind void
          (lambda () (let (value (thunk)) (set! completed? #t) value))
          (lambda () (observer argv (- (real-time) started) completed?)))))))
(def (store-path-command argv lookup?: (lookup? #f))
  (when (current-nix-process-observer) ((current-nix-process-observer) argv))
  (let* ((status #f)
         (result
          (call-with-nix-process-observation argv
            (lambda ()
              (run-process argv
                stdin-redirection: #f stderr-redirection: #f
                coprocess: read-line
                check-status:
                (if lookup? (lambda (code _settings) (set! status code)) #t))))))
    ;; Only construction's optional cache lookup may miss. A currentness query
    ;; keeps the original strict process failure; it never retries in write mode.
    (if (and lookup? (not (zero? status))) #f
      (begin
        (unless (and (string? result) (string-prefix? "/nix/store/" result))
          (error "invalid Nix artifact response" result))
        result))))

(def (nix-store-path-valid? executable path)
  (def argv (list executable "--check-validity" path))
  (def status #f)
  (when (current-nix-process-observer) ((current-nix-process-observer) argv))
  (call-with-nix-process-observation argv
    (lambda ()
      (run-process argv stdin-redirection: #f stderr-redirection: #t
        check-status: (lambda (code _settings) (set! status code)))))
  (zero? status))

(def (poo-flow-core-nix-instantiate executable expression arguments
                                   (store-command (lambda () "nix-store")))
  ;; Nix owns the cache. Always evaluate the CURRENT expression/arguments first;
  ;; do not reuse a Scheme result or assume our source list closes Nix imports.
  (def command
    (append (list executable "--eval" "--raw" "--attr" "drvPath")
      (list expression)
      (foldr append '()
        (map (lambda (name)
               (list "--argstr" (symbol->string name) (.ref arguments name)))
             (.all-slots arguments)))))
  (if (nix-derivation-query?)
    (store-path-command command)
    (let (candidate (store-path-command command lookup?: #t))
      (if (and candidate (nix-store-path-valid? (store-command) candidate))
        candidate
        ;; Missing store state (or evaluation requiring writable construction)
        ;; falls back to the original registration operation, not to acceptance.
        (let (registered
               (store-path-command (append command '("--read-write-mode"))))
          (when (and candidate (not (equal? candidate registered)))
            (error "Nix source changed during derivation registration" candidate registered))
          registered)))))
(def (nix-string text)
  ;; JSON and Nix differ at interpolation. Escape data, never concatenate data
  ;; into Nix syntax without quoting (including ordinary ${...} config values).
  (string-append "\""
    (string-subst
      (string-subst
        (string-subst (string-subst text "\\" "\\\\") "\"" "\\\"")
        "$" "\\$")
      "\n" "\\n") "\""))
(def (poo-flow-core-nix-flake-instantiate executable reference attribute (arguments (.o)))
  (let* ((applied? (pair? (.all-slots arguments)))
         (installable (string-append reference "#" attribute (if applied? "" ".drvPath")))
         (json (and applied?
                (call-with-output-string
                  (lambda (port)
                    (write-json port (list->hash-table (.alist/sort arguments))))))))
    (store-path-command
      (append
        (list executable "--extra-experimental-features" "nix-command flakes"
              ;; Nix 2.34 permits in-memory lock changes when --no-write-lock-file
              ;; is also set. --no-update-lock-file alone rejects them and never
              ;; writes a changed lock; keep this stronger boundary explicit.
              "eval" "--raw" "--no-update-lock-file" installable)
        (if applied?
          (list "--apply" (string-append "function: (function (builtins.fromJSON "
                                         (nix-string json) ")).drvPath"))
          '())))))
(def (poo-flow-core-nix-flake-source-inputs reference)
  ;; No tree scan. Native Nix checks transitive derivation dependencies. Remote
  ;; roots have no local byte observations; transport/pinning remains upstream.
  (let (root (cond ((string-prefix? "path:/" reference) (substring reference 5 (string-length reference)))
                  ((string-prefix? "/" reference) reference) (else #f)))
    (if root
      (map (lambda (name)
             (let (path (path-expand name root))
               (cons path (and (module-source-type path) (module-source-read path)))))
           '("flake.nix" "flake.lock"))
      '())))
(def (poo-flow-core-nix-realize executable derivation)
  (store-path-command (list executable "--realise" derivation)))

;; Project already-observed Core source bytes; no extra filesystem scan.
(def (poo-flow-core-nix-source-inputs observations)
  (list->vector
   (map (lambda (row)
          (list->hash-table
           (list (cons 'path (car row))
                 (cons 'present (if (cdr row) #t #f))
                 (cons 'sha256 (if (cdr row)
                                 (hex-encode (sha256 (string->utf8 (cdr row)))) "")))))
        observations)))
