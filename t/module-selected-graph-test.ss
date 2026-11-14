;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :std/error Error? Error-message)
        (only-in :std/list/list find)
        (only-in :std/source this-source-file)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax
                 core-import-module core-module->prelude-context)
        (only-in :clan/poo/object .o .+ .cc .ref .get .all-slots object::t object-slots
                 object-read-issued? object-construction-current?)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads
                 call-with-slot-read-observer slot-read-receiver slot-read-key slot-read-value)
        (prefix-in (only-in :gerbil/runtime/mop find-method bind-method!) runtime.)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :tao3k/yuanxu/ops/progress call-with-execution-progress
                 execution-progress-idle-milliseconds)
        (only-in :clan/poo/mop Type.)
        :tao3k/yuanxu/module-system/feature/model
        :tao3k/yuanxu/module-system/source/init
        :tao3k/yuanxu/module-system/source/objects
        (only-in :tao3k/yuanxu/module-system/source/selection select-module-graph)
        :tao3k/yuanxu/module-system/interface)
(export module-selected-graph-test)
(def Scope
  (.cc Type. identity: 'test/selected-scope .element?: (lambda (_value) #t)))
(def (publication id requirement-values feature-values (factory (lambda (_dependencies) (.o ready: #t))))
  (.o identity: id features: feature-values
      imports: (map (lambda (name) (.get (.ref requirement-values name) module-id)) (.all-slots requirement-values))
      core: (.o scope-contract: Scope exports: (factory #f))))
(def (requirement id) (.o module-id: id contract: Scope))
(def (descriptor name (required-ids '()) (conflict-ids '()))
  (feature-descriptor
   (.o feature-id: (string->symbol (string-append "app/web/" (symbol->string name)))
       owner-module-id: 'app/web requires: required-ids conflicts: conflict-ids
       components: (list name) projections: (list name))))
(def (context declarations forms (reader void))
  (let* ((intent-value (module-init-intent forms "fixture/init.ss"))
         (decisions (.get intent-value decisions))
         (selected-values (map (cut .ref <> 'identity)
                               (filter (lambda (row) (not (.get row disabled?))) decisions)))
         (denied-values (map (cut .ref <> 'identity)
                             (filter (lambda (row) (.get row disabled?)) decisions))))
    (.o generation: "selected-v1" init-source: "fixture/init.ss" intent: intent-value
        module-ids: '(app/web core/schema unused/bomb) selected: selected-values
        denied-modules: denied-values current?: (lambda (_generation) #t)
        import-owners: (lambda (source) (.get (.ref declarations (yuanxu-module-source-ref-value source)) imports))
        locate: make-yuanxu-module-generated-source
        read-publication: (lambda (source)
                            (let (id (yuanxu-module-source-ref-value source))
                              (reader id) (.ref declarations id))))))
(def (view features forms (requires (.o)))
  (yuanxu-load-modules
   (context (.o app/web: (publication 'app/web requires features)
                core/schema: (publication 'core/schema (.o) (.o))
                unused/bomb: (error "unselected publication forced")) forms)))
(def (failure-message thunk)
  (with-catch (lambda (exception)
                (call-with-output-string (lambda (port) (display-exception exception port))))
              (lambda () (thunk) "unexpected success")))
(def (core-sample (select select-module-graph))
  (def declarations
    (.o app/web: (publication 'app/web (.o Schema: (requirement 'core/schema))
                    (.o unused: (error "unselected Feature forced")))
        core/schema: (publication 'core/schema (.o) (.o))))
  (def c (context declarations '((yuanxu! :test-dir "./t" mode: explicit :core (schema) :app (web)))))
  (%call-with-recorded-slot-reads
    (lambda () (select c '(app/web) (cut .ref declarations <>) void
                 (lambda (id) (.get (.ref declarations id) imports))))
    unique-roots?: #t))
(def (core-spec-count reads)
  (def seen (make-hash-table-eq))
  (for-each
    (lambda (read)
      (check-equal? (object-read-issued? read) #t)
      (def receiver (slot-read-receiver read))
      (def names (map car (object-slots receiver)))
      (when (and (= (length names) 3)
                 (andmap (cut memq <> names) '(feature-id owner-module-id requires)))
        (hash-put! seen receiver #t))) reads)
  (hash-length seen))
(def module-selected-graph-test
  (test-suite "One selected Graph for init, mandatory Core and optional Features"
    (yuanxu-test-case "closed Core selection reuses defaults without temporary Feature specs"
      (defvalues (graph reads) (core-sample))
      (check-equal? (.get graph module-order) '(core/schema app/web))
      (check-equal? (.get graph feature-order) '())
      (check-equal? (core-spec-count reads) 0)
      (def core-reads
        (filter (lambda (read)
                  (and (eq? (slot-read-key read) 'feature-id)
                       (eq? (slot-read-value read) 'app/web/:core))) reads))
      (def descriptor
        (find (lambda (value) (eq? (.get value kind) 'feature-descriptor))
              (map slot-read-receiver core-reads)))
      (def expected (feature-descriptor
        (.o feature-id: 'app/web/:core owner-module-id: 'app/web requires: '(core/schema/:core))))
      (for-each (lambda (name) (check-equal? (.ref descriptor name) (.ref expected name)))
                (.all-slots expected)))
    (yuanxu-test-case "completed topology reports progress before final currentness"
      (def now 0)
      (def checks 0)
      (def refused (gensym 'stale-selection))
      (call-with-execution-progress #f #f
        (lambda (state)
          (set! now 10)
          (check-exception
            (core-sample
              (lambda (context roots read-publication _current! imported-owners)
                (select-module-graph context roots read-publication
                  (lambda ()
                    (set! checks (+ checks 1))
                    (case checks
                      ((1) (check-equal? (execution-progress-idle-milliseconds state) 10))
                      ((2) (check-equal? (execution-progress-idle-milliseconds state) 0)
                           (raise refused)))) imported-owners)))
            (lambda (error) (eq? error refused))))
        clock: (lambda () now))
      (check-equal? checks 2))
    (yuanxu-test-case "unknown observation retains ordinary Core Feature specifications"
      (call-with-slot-read-observer (lambda (_read) (void))
        (lambda ()
          (defvalues (graph reads) (core-sample))
          (check-equal? (.get graph module-order) '(core/schema app/web))
          (check-equal? (core-spec-count reads) 2))))
    (yuanxu-test-case "changed runtime initializer retains ordinary constructor effects"
      (def original (runtime.find-method object::t #f ':init!))
      (def calls 0)
      (dynamic-wind
        (lambda ()
          (runtime.bind-method! object::t ':init!
            (lambda (self . args) (set! calls (1+ calls)) (apply original self args)) #t))
        (lambda ()
          (check-equal? (object-construction-current?) #f)
          (defvalues (graph reads) (core-sample))
          (check-equal? (.get graph module-order) '(core/schema app/web))
          (check-equal? (core-spec-count reads) 2)
          (check-equal? (> calls 0) #t))
        (lambda () (runtime.bind-method! object::t ':init! original #t)))
      (check-equal? (object-construction-current?) #t))
    (yuanxu-test-case "restoring an initializer cannot certify an unsafe import origin"
      ;; Evaluate the ACTUAL module body through runtime module/import in an
      ;; independent lexical namespace. No copied guard or fabricated reads.
      (def body (call-with-input-file
        (path-expand "../module-system/source/selection.ss" (path-directory (this-source-file))) read-all))
      ;; Reproduce the source package's language, including its POO bindings.
      ;; A runtime-only import in the real body intentionally does not bind
      ;; syntax into an unrelated :gerbil/core-only evaluation context.
      (parameterize ((current-expander-context
                      (make-top-context
                        (core-module->prelude-context
                          (core-import-module ':tao3k/yuanxu/prelude)))))
        (def name (gensym 'core-feature-origin))
        (def original (runtime.find-method object::t #f ':init!))
        (dynamic-wind
          (lambda ()
            (runtime.bind-method! object::t ':init!
              (lambda (self . args) (apply original self args)) #t))
          (lambda ()
            (eval-syntax `(module ,name ,@body))
            (eval-syntax `(import (only-in ,name select-module-graph))))
          (lambda () (runtime.bind-method! object::t ':init! original #t)))
        (check-equal? (object-construction-current?) #t)
        (defvalues (graph reads) (core-sample (eval-syntax 'select-module-graph)))
        (check-equal? (.get graph module-order) '(core/schema app/web))
        (check-equal? (core-spec-count reads) 2)))
    (yuanxu-test-case "dynamic eligibility cannot mutate sources before publication initialization"
      (def current? #t)
      (def reads 0)
      (def c
        (.cc (context (.o app/web: (publication 'app/web (.o) (.o)))
               '((yuanxu! :test-dir "./t" mode: auto))
               (lambda (_id) (set! reads (+ reads 1))))
          'module-ids '() 'selected '()
          'current? (lambda (_generation) current?)
          'eligible? (lambda (_id) (set! current? #f) #t)
          'namespace (lambda (resolve) (.o subject: (resolve 'app/web)))))
      (def v (yuanxu-load-modules c))
      (check-exception (.get v modules subject) error?)
      (check-equal? reads 0))
    (yuanxu-test-case "publication admission may force author slots; its post-check remains independent"
      (def current? #t)
      (def p
        (.o identity: 'app/web features: (.o) imports: '()
            core: (begin
                    (set! current? #f)
                    (.o scope-contract: Scope exports: (.o)))))
      (def c
        (.cc (context (.o app/web: p)
               '((yuanxu! :test-dir "./t" mode: explicit :app (web))))
          'current? (lambda (_generation) current?)))
      (def v (yuanxu-load-modules c))
      (check-exception (.get v selected-graph)
        (lambda (cause)
          (and (Error? cause)
               (equal? (Error-message cause) "stale module scope generation"))))
      (check-equal? current? #f))
    (yuanxu-test-case "candidate Graph reuses publication identity and checks after lazy author code"
      (def reads 0)
      (def current? #t)
      (def checks 0)
      (def (current!)
        (set! checks (+ checks 1))
        (unless current? (error "source changed during Graph construction")))
      (def features
        (.o early: (begin (set! current? #f) (descriptor 'early))))
      (def p (publication 'app/web (.o) features))
      (def c (context (.o app/web: p)
                '((yuanxu! :test-dir "./t" source: "modules" mode: explicit :app (web +early)))))
      (check-exception
        (select-module-graph c '(app/web)
          (lambda (_id) (set! reads (+ reads 1)) p) current!) error?)
      (check-equal? reads 1)
      (check-equal? checks 2))
    (yuanxu-test-case "metadata admission stays cold until demanded and never runs scope factories"
      (let* ((reads '()) (factories 0)
             (declarations
              (.o app/web:
                  (publication 'app/web (.o Schema: (requirement 'core/schema))
                   (.o late: (descriptor 'late '(app/web/early)) early: (descriptor 'early)
                       off: (error "negative descriptor forced"))
                   (lambda (_deps) (set! factories (+ factories 1)) (.o ready: #t)))
                  core/schema: (publication 'core/schema (.o) (.o))
                  unused/bomb: (error "disabled publication forced")))
             (v (yuanxu-load-modules
                 (context declarations
                  '((yuanxu! :test-dir "./t" mode: explicit :app (web +late +early -off) :core (schema) :unused (bomb -future disable: #t)))
                  (lambda (id) (set! reads (cons id reads)))))))
        (check-equal? reads '())
        (let (graph (.get v selected-graph))
          (check-equal? (.get graph module-order) '(core/schema app/web))
          (check-equal? (.get graph feature-order) '(app/web/early app/web/late))
          (check-equal? (.get graph feature-contributions components) '(early late))
          (check-equal? (.get graph feature-contributions projections) '(early late))
          (check-equal? (.get graph denied-features) '(app/web/off unused/bomb/future))
          (check-equal? (.get graph denied-modules) '(unused/bomb))
          (check-equal? (.get graph init-source) "fixture/init.ss")
          (check-equal? (.get graph generation) "selected-v1")
          (check-equal? (length (.get graph decisions)) 3))
        (check-equal? reads '(core/schema app/web))
        (check-equal? factories 0)
        (check-equal? (.get v modules app web ready) #t)
        (check-equal? factories 1)
        (check-equal? (.get v dependency-order) '(core/schema app/web))
        (check-equal? reads '(core/schema app/web))))
    (yuanxu-test-case "required disabled Core refuses before either scope factory"
      (let* ((factories 0) (reads '())
             (v (yuanxu-load-modules
                 (context (.o app/web:
                           (publication 'app/web (.o Schema: (requirement 'core/schema)) (.o)
                            (lambda (_deps) (set! factories (+ factories 1)) (.o))))
                  '((yuanxu! :test-dir "./t" mode: explicit :app (web) :core (schema disable: #t)))
                  (lambda (id) (set! reads (cons id reads)))))))
        (check-exception (.get v selected-graph) error?)
        (check-equal? reads '(app/web))
        (check-equal? factories 0)
        (check-exception ((.get v admit-current)) error?)))
    (yuanxu-test-case "negative and absent required Features are never silently enabled"
      (for-each
       (lambda (forms)
         (let (v (view (.o early: (error "unselected descriptor forced")
                           late: (descriptor 'late '(app/web/early))) forms))
           (check-exception (.get v modules app web ready) error?)
           (check-exception ((.get v admit-current)) error?)))
       '(((yuanxu! :test-dir "./t" mode: explicit :app (web +late -early)))
         ((yuanxu! :test-dir "./t" mode: explicit :app (web +late))))))
    (yuanxu-test-case "Feature conflicts reject before executable scope exposure"
      (let (v (view (.o early: (descriptor 'early '() '(app/web/late)) late: (descriptor 'late))
                    '((yuanxu! :test-dir "./t" mode: explicit :app (web +early +late)))))
        (check-exception (.get v selected-records) error?)
        (check-exception ((.get v admit-current)) error?)))
    (yuanxu-test-case "unknown positive and negative names are rejected"
      (for-each (lambda (flag)
                  (let (v (view (.o) `((yuanxu! :test-dir "./t" mode: explicit :app (web ,flag)))))
                    (check-exception (.get v selected-graph) error?))) '(+typo -typo)))
    (yuanxu-test-case "publication owner identity cannot be forged by a Feature"
      (for-each
        (lambda (feature)
          (let (v (view (.o early: feature) '((yuanxu! :test-dir "./t" mode: explicit :app (web +early)))))
            (check-exception (.get v selected-graph) error?)))
        (list (.+ (descriptor 'early) (.o owner-module-id: 'other/module))
              (.o owner-module-id: 'other/module)
              (.o feature-id: 'other/module/early))))
    (yuanxu-test-case "Feature cycles and mandatory Core cycles use the existing resolver"
      (let (v (view (.o early: (descriptor 'early '(app/web/late))
                        late: (descriptor 'late '(app/web/early)))
                    '((yuanxu! :test-dir "./t" mode: explicit :app (web +early +late)))))
        (check-exception (.get v selected-graph) error?))
      (let (v (view (.o) '((yuanxu! :test-dir "./t" mode: explicit :app (web))) (.o Self: (requirement 'app/web))))
        (check-exception (.get v selected-graph) error?)))
    (yuanxu-test-case "optional dependencies only order Features actually selected"
      (let (v (view (.o early: (descriptor 'early)
                        late: (.+ (descriptor 'late) (.o optional-requires: '(app/web/early))))
                    '((yuanxu! :test-dir "./t" mode: explicit :app (web +late -early)))))
        (check-equal? (.get v selected-graph feature-order) '(app/web/late))))
    (yuanxu-test-case "independent Features retain explicit init order"
      (let (v (view (.o early: (descriptor 'early) late: (descriptor 'late))
                    '((yuanxu! :test-dir "./t" mode: explicit :app (web +late +early)))))
        (check-equal? (.get v selected-graph feature-order) '(app/web/late app/web/early))))
    (yuanxu-test-case "cross-owner Feature edges and contributions follow dependency order"
      (let* ((remote (feature-descriptor
                      (.o feature-id: 'core/schema/validate owner-module-id: 'core/schema
                          components: '(validate))))
             (v (yuanxu-load-modules
                 (context
                  (.o app/web:
                      (publication 'app/web (.o Schema: (requirement 'core/schema))
                       (.o late: (descriptor 'late '(core/schema/validate))))
                      core/schema: (publication 'core/schema (.o) (.o validate: remote)))
                  '((yuanxu! :test-dir "./t" mode: explicit :app (web +late) :core (schema +validate)))))))
        (check-equal? (.get v selected-graph feature-order) '(core/schema/validate app/web/late))
        (check-equal? (.get v selected-graph feature-contributions components) '(validate late))))
    (yuanxu-test-case "selected metadata does not force contribution payloads"
      (let (v (view (.o early: (.+ (descriptor 'early)
                                  (.o components: (error "payload demanded"))))
                    '((yuanxu! :test-dir "./t" mode: explicit :app (web +early)))))
        (check-equal? (.get v selected-graph feature-order) '(app/web/early))
        (check-equal? (and (string-contains
                           (failure-message (lambda () (.get v selected-graph feature-contributions)))
                           "payload demanded") #t) #t)))
    (yuanxu-test-case "required negative diagnostics retain requester, target and denying origin"
      (let* ((v (view (.o early: (error "negative descriptor demanded")
                         late: (descriptor 'late '(app/web/early)))
                     '((yuanxu! :test-dir "./t" mode: explicit :app (web +late -early)))))
             (message (failure-message (lambda () (.get v selected-graph)))))
        (for-each (lambda (text) (check-equal? (and (string-contains message text) #t) #t))
                  '("selected Graph rejected" "fixture/init.ss" "selected-v1" "app/web/late" "app/web/early" "denied?"))))
    (yuanxu-test-case "same-layer contradictions and reserved identity paths reject at init"
      (for-each
       (lambda (row) (check-exception (module-init-intent `((yuanxu! :test-dir "./t" mode: explicit :app ,row)) "init.ss") error?))
       '((web +early -early) (web +early +early) (web +nested/name) (web +:core)))))
)
