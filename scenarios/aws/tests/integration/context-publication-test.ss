;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Real provider packages and maintained AWS publication; no cloud effects.
(import :std/test :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :std/error Error? Error-message)
        (only-in :core/observability/testing-fixture poo-flow-test-fixture)
        (only-in :core/module-system/source/admission
                 module-source-read current-module-source-observer)
        (only-in :core/modules/nix/func current-nix-process-completion-observer)
        (only-in :core/observability/debug poo-flow-debug-memory-snapshot)
        (only-in "./fixtures.ss"
                 Workspace prepare-aws-selection! realize-aws-selection write-aws-version!)
        (only-in :core/admission/publication AdmissionPublication.)
        (only-in :core/types poo-flow-validation-evidence-accepted?)
        (prefix-in :clan/poo/declarative-metadata metadata.))
(export aws-context-publication-test)

(def (refused previous evidence next failure)
  (check-equal? evidence #f)
  (check-equal? (eq? previous next) #t)
  (check-equal? (metadata.failure? failure) #t))

;; Negative control over the public publication protocol; no imported test suite.
(def (replay previous checked descriptor context-value evidence)
  (def call
    (metadata.with-meaning
      (metadata.contract
        (metadata.predicate "configuration" object?)
        (metadata.predicate "accepted evidence" poo-flow-validation-evidence-accepted?)
        (lambda (_key _request _evidence) #t) (metadata.atom 'context-current))
      (lambda (_key _request _evidence) ((.get context-value admit-current)) #t) #f))
  (def bound
    (metadata.bind-evidence call checked descriptor context-value
      (lambda (receipt)
        (.o subject: (.get receipt candidate)
            descriptor: (.get receipt admission-contract)
            context: (.get receipt context)))))
  (metadata.publish bound previous (lambda (_value) (values evidence checked)) checked))

(def aws-context-publication-test
  (test-suite "AWS public fields, contextual child admission and publication"
    (poo-flow-test-fixture "real Schema upgrade refuses stale evidence and keeps accepted values"
      (root Workspace)
      ;; Opt-in counters use the existing source observer. They hold no accepted
      ;; results and never reuse currentness across Nix or Contract callbacks.
      (def tracing? (getenv "CORE_AWS_TRACE" #f))
      (def counters (make-hash-table))
      (def files (make-hash-table))
      (def guard-origins '())
      (def guards (make-hash-table))
      (def (observe-source key amount)
        (cond
         ((symbol? key) (hash-update! counters key (cut + <> amount) 0))
         ((and (pair? key) (eq? (car key) 'file-read))
          (hash-update! files (cdr key) (cut + <> amount) 0))
         ((and (pair? key) (eq? (car key) 'source-import-redirect))
          (hash-update! counters 'source-redirects (cut + <> amount) 0))
         ((and (pair? key) (eq? (car key) 'publication-guard-start))
          (set! guard-origins (cons (cadr key) guard-origins)))
         ((and (pair? key) (eq? (car key) 'publication-guard-end))
          (set! guard-origins (cdr guard-origins)))
         ((and (pair? key) (eq? (car key) 'publication-guard-run))
          (hash-update! guards (car guard-origins) (cut + <> amount) 0))))
      (def (source-phase name)
        (when tracing?
          (displayln "AWS-SOURCE " name " "
            (map (lambda (key) (cons key (hash-ref counters key 0)))
                 '(reads read-requests checks check-seconds stats source-redirects)))
          (displayln "AWS-GUARDS " name " " (hash->list guards))
          (let top ((rows (list-sort (lambda (a b) (> (cdr a) (cdr b)))
                                    (hash->list files)))
                    (remaining 3))
            (unless (or (null? rows) (zero? remaining))
              (displayln "AWS-SOURCE-TOP " name " " (car rows))
              (top (cdr rows) (- remaining 1))))
          (hash-clear! counters)
          (hash-clear! files)
          (hash-clear! guards)
          (force-output)))
      (parameterize
        ((current-module-source-observer
           (if tracing? observe-source (current-module-source-observer)))
         (current-nix-process-completion-observer
           (if tracing?
             (lambda (argv seconds completed?)
               (displayln "AWS-NIX " (path-strip-directory (car argv))
                          " mode=" (cond
                                     ((member "--realise" argv) 'realize)
                                     ((member "--check-validity" argv) 'store-validity)
                                     ((member "--read-write-mode" argv) 'register)
                                     (else 'query))
                          " seconds=" seconds " completed=" completed?)
               (source-phase 'nix-completed)
               (force-output))
             (current-nix-process-completion-observer))))
        (def started (real-time))
        (def previous started)
        (def (phase name)
          (when (getenv "CORE_AWS_TRACE" #f)
            (let (sample (poo-flow-debug-memory-snapshot name))
              (def now (real-time))
              (displayln "AWS-INTEGRATION " name " elapsed=" (- now started)
                         " step=" (- now previous) " heap=" (.get sample heap-size-bytes)
                         " live=" (.get sample live-bytes) " max-heap=" (##get-max-heap))
              (set! previous now)
              (source-phase name)
              (force-output))))
        (phase 'start)
        (def fixture (prepare-aws-selection! root))
        (phase 'prepared)
        (def project (.get fixture project))
        (def config (path-expand "../../config.ss" (path-directory (this-source-file))))
        (def config-before (module-source-read config))
        (def selection
          (realize-aws-selection fixture (path-expand "packages-old" root) phase))
        (phase 'parent-selected)
        ;; No Schema list, descriptor reconstruction or handwritten admission paths.
        (def publication (.call AdmissionPublication. .for-export selection 'aws 'Scenario))
        (phase 'parent-bound)
        (def contract (.get publication contract))
        (def child-contract (.get contract responsibilities profile))
        (check-equal? (.get selection modules aws provider version) "5.99.0")
        (check-equal? (eq? contract (.get selection modules aws types Scenario)) #t)
        (check-equal? (.get child-contract value-contract) #f)
        (check-equal? (length (.get publication context schema-inputs)) 3)

        (def WebProfile (.get selection modules aws Profiles Web))
        (def Scenario (.get publication value))
        (def parent-cached (.get Scenario resource))
        (check-equal? (.get parent-cached instance_type) "t3.small")
        (.def (Production @ WebProfile) instance_type: "t3.medium")
        (.def (Release @ Scenario) profile: Production)
        (defvalues (receipt next failure) (.call publication .publish Scenario Release))
        (phase 'parent-published)
        (check-equal? failure #f)
        (check-equal? (poo-flow-validation-evidence-accepted? receipt) #t)
        (check-equal? (.get next resource instance_type) "t3.medium")
        (check-equal? (.get parent-cached instance_type) "t3.small")
        (check-equal? (eq? (.get receipt candidate) next) #t)
        (check-equal? (eq? (.get next profile) (.get next resource)) #t)
        (def child (car (.get receipt responsibility-evidence)))
        (check-equal? (eq? (.get child candidate) (.get next profile)) #t)
        (check-equal? (eq? (.get child admission-contract) child-contract) #t)
        (check-equal? (eq? (.get child context) (.get publication context)) #t)
        ;; Sharing a label does not grant another descriptor admission authority.
        (check-exception
          (.call (.get publication context) .contract-obligations
                 (.cc child-contract) (.get next profile))
          (lambda (exception)
            (and (Error? exception)
                 (string=? (Error-message exception)
                           "admission descriptor differs from selected publication"))))
        (phase 'descriptor-clone-refused)

        ;; A policy probe extends the actual platform Context, retaining its
        ;; original method and guards. It is not a production AWS authorization rule.
        (def observed '())
        (.def (RejectProfile @ (.get publication context))
          .contract-obligations: =>
          (lambda (previous)
            (lambda (actual candidate)
              (set! observed (cons actual observed))
              (append (previous actual candidate)
                (if (eq? actual child-contract)
                  (list (.o kind: 'test-profile-context-refused)) '())))))
        (defvalues (denied kept rejection)
          (.call (.cc publication context: RejectProfile) .publish next Release))
        (phase 'context-denial-returned)
        (refused next denied kept rejection)
        (check-equal? (and (memq child-contract observed) #t) #t)

        ;; Replace the package selection, never modify the immutable Nix store.
        (write-aws-version! project "child")
        (phase 'source-mutated)
        (defvalues (stale kept-old stale-failure) (.call publication .publish next Release))
        (refused next stale kept-old stale-failure)
        (phase 'old-source-refused)
        (def fresh-selection
          (realize-aws-selection fixture (path-expand "packages-new" root) phase))
        (phase 'child-selected)
        (def fresh-publication
          (.call AdmissionPublication. .for-export fresh-selection 'aws 'Scenario))
        (phase 'child-bound)
        (check-equal? (.get fresh-selection modules aws provider version) "5.100.0")
        (defvalues (replayed kept-replay replay-failure)
          (replay next next (.get fresh-publication contract)
            (.get fresh-publication context) receipt))
        (refused next replayed kept-replay replay-failure)
        (phase 'replay-refused)
        (defvalues (fresh latest fresh-failure) (.call fresh-publication .publish next Release))
        (phase 'child-published)
        (check-equal? fresh-failure #f)
        (check-equal? (.get latest resource instance_type) "t3.medium")
        (check-equal? (eq? (.get fresh context) (.get receipt context)) #f)
        (def fresh-child (car (.get fresh responsibility-evidence)))
        (check-equal? (eq? (.get fresh-child candidate) (.get latest profile)) #t)
        (check-equal? (module-source-read config) config-before)

        (.def (Typo @ Production) instnace_type: "t3.large")
        (.def (Invalid @ Scenario) profile: Typo)
        (defvalues (bad kept-valid bad-failure) (.call fresh-publication .publish latest Invalid))
        (refused latest bad kept-valid bad-failure)
        (phase 'typo-refused)

        ;; The contextual requirement snapshot is guarded too. Editing its map
        ;; cannot silently authorize a replacement after publication preparation.
        (.put! (.get fresh-publication contract responsibilities)
               'profile (.cc child-contract))
        (defvalues (replaced kept-requirements requirements-failure)
          (.call fresh-publication .publish latest Release))
        (refused latest replaced kept-requirements requirements-failure)
        (phase 'requirements-refused)

        (check-equal? (module-source-read config) config-before)))))
