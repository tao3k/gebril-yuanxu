;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; An import closure describes code use, not all effects of Scheme.
(import :std/test :clan/poo/object
        (only-in :clan/poo/type Record)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads
                 slot-read-receiver slot-read-key slot-read-dependencies)
        (only-in :std/error Error? Error-message)
        (only-in "./qualification/module-publication/fixtures.ss" with-publication-source write-file)
        (only-in :tao3k/yuanxu/module-system/authoring/roles make-default-module-authoring-profile)
        (only-in :tao3k/yuanxu/module-system/source/reader module-publication-reader)
        (only-in :tao3k/yuanxu/module-system/source/admission module-source-read)
        (only-in :tao3k/yuanxu/module-system/source/interface yuanxu-module-interface)
        (only-in :tao3k/yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :tao3k/yuanxu/module-system/types ModuleSourceRoleContract)
        (only-in :clan/poo/read-projection
                 call-with-owned-read-projection current-owned-read-open-guard)
        (only-in :tao3k/yuanxu/object-types/contracts
                 yuanxu-classification-evidence yuanxu-validation-evidence)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case))
(export module-reader-effect-support-test)
(def (find-issued-read roots matches?)
  (def seen (make-hash-table-eq))
  (def (visit read)
    (and (not (hash-key? seen read))
         (begin
           (hash-put! seen read #t)
           (if (matches? read) read (ormap visit (slot-read-dependencies read))))))
  (ormap visit roots))

(def module-reader-effect-support-test
  (test-suite "Reader import support versus ambient effects"
    (yuanxu-test-case "entry and return retain ambient source obligations"
      (for-each
        (lambda (phase)
          (with-publication-source
            (lambda (root first-root _source _view)
              (def second-root (path-expand "modules/custom/other" root))
              (def first-config (path-expand "config.ss" first-root))
              (def marker (path-expand "second-initialized" root))
              (def replacement "(def Greeting \"changed\") (export Greeting)")
              (for-each
                (lambda (role)
                  (write-file (path-expand role second-root)
                    (module-source-read (path-expand role first-root))))
                '("types.ss" "objects.ss"))
              ;; There is deliberately NO import of the first Module. A runtime
              ;; initializer can still change its source through ordinary IO.
              (write-file (path-expand "config.ss" second-root)
                (string-append
                  (if (eq? phase 'return)
                    (string-append "(call-with-output-file (list path: "
                      (object->string first-config) " truncate: #t) (lambda (p) (display "
                      (object->string replacement) " p))) ") "")
                  "(call-with-output-file " (object->string marker)
                  " (lambda (p) (display \"initialized\" p))) "
                  "(def Greeting \"other\") (export Greeting)"))
              (write-file (path-expand "interface.ss" second-root)
                "(.def Module identity: 'custom/other core: (.o scope-contract: FixtureContract exports: (.o greeting: Greeting)) features: (.o))")
              (def view (yuanxu-load-modules (path-expand "modules" root)))
              (def locate (.get view context locate))
              (def reader (module-publication-reader))
              (.call reader read (locate 'custom/example))
              (when (eq? phase 'entry) (write-file first-config replacement))
              (check-exception
                (call-with-values
                  (lambda () (.call reader read-located (lambda () (locate 'custom/other))))
                  (lambda (_source _value) 'unexpected-success)) error?)
              ;; Entry refusal is before the initializer; return refusal is
              ;; after its real effect. Neither publishes a successful value.
              (check-equal? (file-exists? marker) (eq? phase 'return))
              (check-exception (.call reader admit-current) error?))))
        '(entry return)))
    (yuanxu-test-case "a published Graph retains the signed Profile receipt available to later readers"
      (with-publication-source
        (lambda (_root _module _source view)
          (def graph (.get view selected-graph))
          ;; Construction finished without a slot observer. Read the already
          ;; published value again to obtain its actual issued dependency root.
          (defvalues (same roots)
            (%call-with-recorded-slot-reads (lambda () (.get view selected-graph))))
          (check-equal? (eq? same graph) #t)
          (def profile
            (find-issued-read roots
              (lambda (read) (eq? (slot-read-key read) '%authoring-interface))))
          (check-equal? (if profile #t #f) #t)
          (def receipt
            (find-issued-read (list profile)
              (lambda (read)
                (let (slots (object-%instance (slot-read-receiver read)))
                  (and slots (eq? (slot-read-key read) 'accepted?)
                       (eq? (hash-get slots 'kind) 'yuanxu.contract.validation-evidence))))))
          (check-equal? (if receipt #t #f) #t)
          ;; Change only the issued token's route, leaving the receiver
          ;; revision and every external role unchanged.
          (def records (object-%reads (slot-read-receiver receipt)))
          (def key (slot-read-key receipt))
          (check-equal? (eq? (hash-ref records key) receipt) #t)
          (.call graph admit-current)
          (dynamic-wind
            (lambda () (hash-remove! records key))
            (lambda ()
              (check-exception (.call graph admit-current)
                (lambda (failure)
                  (and (Error? failure) (string=? (Error-message failure) "stale slot dependency")))))
            (lambda () (hash-put! records key receipt))))))
    (yuanxu-test-case "a replaced role producer crosses the guard before creating evidence"
      (def raw (make-default-module-authoring-profile))
      (def schema (Record))
      (def maintained (.ref ModuleSourceRoleContract '.admit))
      (def calls 0)
      (def checks 0)
      (def previous-checks 0)
      (def escaped #f)
      (def (run entry)
        (parameterize ((current-owned-read-open-guard entry))
          (call-with-owned-read-projection '() void
            (lambda () (yuanxu-module-interface "role-effect" schema '() authoring: raw)))))
      (dynamic-wind
        (lambda ()
          (.put! ModuleSourceRoleContract '.admit
            (lambda (value context)
              (check-equal? (> checks previous-checks) #t)
              (set! previous-checks checks)
              (set! calls (+ calls 1))
              (def classification
                (yuanxu-classification-evidence 'module-source-role value #t '() context))
              (set! escaped
                (yuanxu-validation-evidence ModuleSourceRoleContract value
                  classification '() #t '() context))
              escaped)))
        (lambda ()
          (check-exception (run (lambda () (error "stale role producer entry")))
            (lambda (failure)
              (and (Error? failure) (string=? (Error-message failure) "stale role producer entry"))))
          (check-equal? calls 0)
          (check-equal? escaped #f)
          (def interface
            (run (lambda () (set! checks (+ checks 1)))))
          (check-equal? (eq? (.get interface authoring) raw) #t)
          (check-equal? (> calls 0) #t)
          (check-equal? (object? escaped) #t))
        (lambda () (.put! ModuleSourceRoleContract '.admit maintained))))))
