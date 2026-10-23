;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .o .+ .cc .ref .get)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)
        :yuanxu/feature-system/model
        :yuanxu/module-system/source/init
        :yuanxu/module-system/source/objects
        (only-in :yuanxu/module-system/source/selection select-module-graph)
        :yuanxu/module-system/interface)
(export module-selected-graph-test)
(def Scope
  (yuanxu-predicate-contract 'test/selected-scope (lambda (_value) #t) (lambda (_v _c) '())))
(def (publication id requirement-values feature-values (factory (lambda (_dependencies) (.o ready: #t))))
  (.o identity: id features: feature-values
      core: (.o requires: requirement-values scope-contract: Scope link: factory)))
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
(def module-selected-graph-test
  (test-suite "One selected Graph for init, mandatory Core and optional Features"
    (yuanxu-test-case "dynamic eligibility cannot mutate sources before publication initialization"
      (def current? #t)
      (def reads 0)
      (def c
        (.cc (context (.o app/web: (publication 'app/web (.o) (.o)))
               '((yuanxu! mode: auto))
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
        (.o identity: 'app/web features: (.o)
            core: (begin
                    (set! current? #f)
                    (.o requires: (.o)
                        scope-contract: Scope
                        link: (lambda (_dependencies) (.o))))))
      (def c
        (.cc (context (.o app/web: p)
               '((yuanxu! mode: explicit :app (web))))
          'current? (lambda (_generation) current?)))
      (def v (yuanxu-load-modules c))
      (check-exception (.get v selected-graph) error?)
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
                '((yuanxu! source: "modules" mode: explicit :app (web +early)))))
      (check-exception
        (select-module-graph c '(app/web)
          (lambda (_id) (set! reads (+ reads 1)) p) current!) error?)
      (check-equal? reads 1)
      (check-equal? checks 1))
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
                  '((yuanxu! mode: explicit :app (web +late +early -off) :core (schema) :unused (bomb -future disable: #t)))
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
                  '((yuanxu! mode: explicit :app (web) :core (schema disable: #t)))
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
       '(((yuanxu! mode: explicit :app (web +late -early)))
         ((yuanxu! mode: explicit :app (web +late))))))
    (yuanxu-test-case "Feature conflicts reject before executable scope exposure"
      (let (v (view (.o early: (descriptor 'early '() '(app/web/late)) late: (descriptor 'late))
                    '((yuanxu! mode: explicit :app (web +early +late)))))
        (check-exception (.get v selected-records) error?)
        (check-exception ((.get v admit-current)) error?)))
    (yuanxu-test-case "unknown positive and negative names are rejected"
      (for-each (lambda (flag)
                  (let (v (view (.o) `((yuanxu! mode: explicit :app (web ,flag)))))
                    (check-exception (.get v selected-graph) error?))) '(+typo -typo)))
    (yuanxu-test-case "publication owner identity cannot be forged by a Feature"
      (let (v (view (.o early: (.+ (descriptor 'early) (.o owner-module-id: 'other/module)))
                    '((yuanxu! mode: explicit :app (web +early)))))
        (check-exception (.get v selected-graph) error?)))
    (yuanxu-test-case "Feature cycles and mandatory Core cycles use the existing resolver"
      (let (v (view (.o early: (descriptor 'early '(app/web/late))
                        late: (descriptor 'late '(app/web/early)))
                    '((yuanxu! mode: explicit :app (web +early +late)))))
        (check-exception (.get v selected-graph) error?))
      (let (v (view (.o) '((yuanxu! mode: explicit :app (web))) (.o Self: (requirement 'app/web))))
        (check-exception (.get v selected-graph) error?)))
    (yuanxu-test-case "optional dependencies only order Features actually selected"
      (let (v (view (.o early: (descriptor 'early)
                        late: (.+ (descriptor 'late) (.o optional-requires: '(app/web/early))))
                    '((yuanxu! mode: explicit :app (web +late -early)))))
        (check-equal? (.get v selected-graph feature-order) '(app/web/late))))
    (yuanxu-test-case "independent Features retain explicit init order"
      (let (v (view (.o early: (descriptor 'early) late: (descriptor 'late))
                    '((yuanxu! mode: explicit :app (web +late +early)))))
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
                  '((yuanxu! mode: explicit :app (web +late) :core (schema +validate)))))))
        (check-equal? (.get v selected-graph feature-order) '(core/schema/validate app/web/late))
        (check-equal? (.get v selected-graph feature-contributions components) '(validate late))))
    (yuanxu-test-case "selected metadata does not force contribution payloads"
      (let (v (view (.o early: (.+ (descriptor 'early)
                                  (.o components: (error "payload demanded"))))
                    '((yuanxu! mode: explicit :app (web +early)))))
        (check-equal? (.get v selected-graph feature-order) '(app/web/early))
        (check-equal? (and (string-contains
                           (failure-message (lambda () (.get v selected-graph feature-contributions)))
                           "payload demanded") #t) #t)))
    (yuanxu-test-case "required negative diagnostics retain requester, target and denying origin"
      (let* ((v (view (.o early: (error "negative descriptor demanded")
                         late: (descriptor 'late '(app/web/early)))
                     '((yuanxu! mode: explicit :app (web +late -early)))))
             (message (failure-message (lambda () (.get v selected-graph)))))
        (for-each (lambda (text) (check-equal? (and (string-contains message text) #t) #t))
                  '("selected Graph rejected" "fixture/init.ss" "selected-v1" "app/web/late" "app/web/early" "denied?"))))
    (yuanxu-test-case "same-layer contradictions and reserved identity paths reject at init"
      (for-each
       (lambda (row) (check-exception (module-init-intent `((yuanxu! mode: explicit :app ,row)) "init.ss") error?))
       '((web +early -early) (web +early +early) (web +nested/name) (web +:core)))))
)
