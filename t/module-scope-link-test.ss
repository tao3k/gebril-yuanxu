;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :std/error Error? Error-message Error-irritants)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (prefix-in (only-in :clan/poo/testing/property check-property make-specification) property.)
        (prefix-in (only-in :clan/poo/testing/property/generator generator-integer) generator.)
        (only-in :clan/poo/testing/property/test require-passed)
        (only-in :clan/poo/slot-observation call-with-slot-read-observer slot-read-key
                 %call-with-recorded-slot-reads)
        (only-in :clan/poo/object .o .ref .get .call .put! .all-slots object<-fun object? object-slots $constant-slot-spec?)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :clan/poo/mop Type.)
        (only-in :tao3k/yuanxu/module-system/source/admission current-module-source-observer module-source-admit-current!)
        (only-in :tao3k/yuanxu/module-system/source/publication module-scope-context?)
        (only-in :tao3k/yuanxu/module-system/source/role-context transfer-role-context)
        :tao3k/yuanxu/module-system/source/objects
        :tao3k/yuanxu/module-system/interface)
(export module-scope-link-test)
(def ObjectScope
  (.cc Type. identity: 'test/scope .element?: object?))
(def (publication id requirements link-function)
  (.o identity: id features: (.o)
      imports: (map (lambda (name) (.get (.ref requirements name) module-id)) (.all-slots requirements))
      core: (.o scope-contract: ObjectScope exports: (link-function #f))))
(def (context declarations selected-values denied read-count current-predicate
              (ids '(core/schema custom/guestbook unused)))
  (.o generation: "fixture-v1" module-ids: ids
      selected: selected-values denied-modules: denied
      locate: (lambda (id) (make-yuanxu-module-generated-source id))
      import-owners: (lambda (source)
                       (let (declaration (.ref declarations (yuanxu-module-source-ref-value source)))
                         (if (.slot? declaration 'imports) (.get declaration imports) '())))
      read-publication: (lambda (source)
                          (let (id (yuanxu-module-source-ref-value source))
                            (read-count id) (.ref declarations id)))
      current?: current-predicate))
(def module-scope-link-test
  (test-suite "Core selected runtime module scopes without a Loader backend"
    (yuanxu-test-case "a late destination conflict leaves the transfer uninstalled"
      (def occupied? #f)
      (def installed '())
      (def refused '())
      (def (transfer)
        (transfer-role-context 'root
          (lambda (root visit) (visit root) (visit 'dependency))
          (lambda (child)
            (values (.o path: child admit-current: void) 'owner '()
                    (lambda () (when (eq? child 'dependency) (set! occupied? #t)))))
          (lambda (_path) 'owner)
          (lambda (_child) #f)
          (lambda (path _child) (not (and occupied? (eq? path 'dependency))))
          (lambda (child _input _owner _assets _guard)
            (set! installed (cons child installed)))
          (lambda (reason) (set! refused (cons reason refused)))))
      (check-equal? (transfer) #f)
      (check-equal? installed '())
      (check-equal? refused '((context-conflict dependency))))
    (yuanxu-test-case "explicit POO input refinement leaves the provider intact"
      (def schema (.o name: "baseline"))
      (def refined (.cc schema name: "consumer"))
      (def provider (publication 'core/schema (.o) (lambda (_) schema)))
      (def consumer (publication 'custom/guestbook
                      (.o Schema: (.o module-id: 'core/schema))
                      (lambda (_) (.o schema: refined))))
      (def view
        (yuanxu-load-modules
          (context (.o core/schema: provider custom/guestbook: consumer)
                   '(custom/guestbook) '() void (lambda (_) #t))))
      (check-equal? (eq? (.get view modules custom guestbook schema) refined) #t)
      (check-equal? (.get refined name) "consumer")
      (check-equal? (eq? (.get (.call view .selected-record 'core/schema) scope) schema) #t)
      (check-equal? (.get schema name) "baseline"))
    (yuanxu-test-case "a current construction can depend on state outside POO"
      (def revision 1)
      (def factory
        (lambda (_dependencies)
          (let (captured revision)
            (.o revision: captured))))
      (def declarations (.o core/schema: (publication 'core/schema (.o) factory)))
      (def (select)
        (yuanxu-load-modules
          (context declarations '(core/schema) '() void (lambda (_generation) #t))))
      (def old (.call (select) .selected-record 'core/schema))
      (check-equal? (.get old scope revision) 1)
      (set! revision 2)
      ;; The standard read/source support remains current, even though running
      ;; the same factory again has a different observable result.
      ((.get old admit-construction-current))
      (def fresh (.call (select) .selected-record 'core/schema))
      (check-equal? (.get fresh scope revision) 2)
      (check-equal? (.get old scope revision) 1))
    (yuanxu-test-case "context identity index agrees with open per-read membership"
      (def names '(a b c))
      (require-passed
        (property.check-property
          (generator.generator-integer 0 31)
          (lambda (mask)
            (def selected
              (filter-map (lambda (entry)
                            (and (not (zero? (bitwise-and mask (car entry)))) (cdr entry)))
                          '((1 . a) (2 . b) (4 . c) (8 . absent) (16 . a))))
            (def candidate
              (context (.o) selected '() void (lambda (_generation) #t) names))
            (def closed (module-scope-context? candidate))
            (def open
              (call-with-slot-read-observer (lambda (_read) (void))
                (lambda () (module-scope-context? candidate))))
            (eq? closed open))
          (property.make-specification exact-integer? abs)
          seed: 3307 cases: 32 size: 8 shrink-budget: 32)))
    (yuanxu-test-case "open context observers retain every membership read"
      (def candidate (context (.o) '(c a b) '() void (lambda (_generation) #t) '(a b c)))
      (def reads 0)
      (check-equal?
        (call-with-slot-read-observer
          (lambda (read)
            (when (eq? (slot-read-key read) 'module-ids) (set! reads (1+ reads))))
          (lambda () (module-scope-context? candidate))) #t)
      ;; One shape/value check, then one original lookup for EACH selection.
      (check-equal? reads 4)
      (defvalues (closed original-reads)
        (%call-with-recorded-slot-reads (lambda () (module-scope-context? candidate))))
      (check-equal? closed #t)
      (check-equal? (length (filter (lambda (read) (eq? (slot-read-key read) 'module-ids))
                                   original-reads)) 2)
      (replay-slot-reads! original-reads void)
      ;; Exercise the real Context admission entry, not just its predicate.
      (def actual (context (.o) '(c a b) '() void (lambda (_generation) #t) '(a b c)))
      (defvalues (_view admission-reads)
        (%call-with-recorded-slot-reads (lambda () (yuanxu-load-modules actual))))
      (check-equal? (length (filter (lambda (read) (eq? (slot-read-key read) 'module-ids))
                                   admission-reads)) 2)
      (replay-slot-reads! admission-reads void)
      (def original (string->uninterned-symbol "same-module"))
      (def replacement (string->uninterned-symbol "same-module"))
      (check-equal? (module-scope-context?
                    (context (.o) (list replacement) '() void
                      (lambda (_generation) #t) (list original))) #f))
    (yuanxu-test-case "indexed namespace metadata leaves provider scopes cold"
      (def ids (map (lambda (n) (string->symbol (string-append "fleet/n" (number->string n))))
                   '(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)))
      (def reads '())
      (def forced '())
      (def declarations
        (object<-fun
          (lambda (id)
            (publication id (.o)
              (lambda (_deps) (set! forced (cons id forced)) (.o identity: id))))
          keys: ids))
      (def view
        (yuanxu-load-modules
          (context declarations ids '() (lambda (id) (set! reads (cons id reads)))
                   (lambda (_generation) #t) ids)))
      (check-equal? (length (.all-slots (.get view modules fleet))) 16)
      (check-equal? reads '())
      (check-equal? forced '())
      (def selected (.get view modules fleet n7))
      (check-equal? (.get selected identity) 'fleet/n7)
      (check-equal? (eq? selected (.get view modules fleet n7)) #t)
      ;; First scope demand admits ALL explicitly selected declarations; only
      ;; the requested provider's business scope is linked. Metadata laziness
      ;; must not turn complete selection into an implicit one-root selection.
      (check-equal? reads (reverse ids))
      (check-equal? forced '(fleet/n7)))
    (yuanxu-test-case "namespace leaf collision refuses without invoking providers"
      (def reads '())
      (def ids '(fleet fleet/child))
      (def view
        (yuanxu-load-modules
          (context (object<-fun (lambda (_id) (error "provider must remain cold")) keys: ids)
                   ids '() (lambda (id) (set! reads (cons id reads)))
                   (lambda (_generation) #t) ids)))
      (check-exception (.get view modules fleet) error?)
      (check-equal? reads '()))
    (yuanxu-test-case "selected-record retains cold factory and warm source refusal"
      (let* ((current #t) (links 0) (checks 0)
             (declarations
              (.o custom/guestbook:
                  (publication 'custom/guestbook (.o)
                    (lambda (_deps) (set! links (+ links 1)) (.o ready: #t)))))
             (view (yuanxu-load-modules
                     (context declarations '(custom/guestbook) '() void
                              (lambda (_generation)
                                (set! checks (+ checks 1)) current)))))
        (def first (.call view .selected-record 'custom/guestbook))
        ;; Link records hold already admitted values. Inspecting the runtime
        ;; slot specs checks that no linking-frame initializer is retained.
        (check-equal? (andmap (lambda (entry) ($constant-slot-spec? (cdr entry)))
                        (object-slots first)) #t)
        (def before checks)
        (check-equal? (eq? first (.call view .selected-record 'custom/guestbook)) #t)
        ;; A cached Graph/record lookup has one fresh eligibility check; there
        ;; is no effect requiring a preceding duplicate Graph guard.
        (check-equal? (- checks before) 1)
        (check-equal? links 1)
        (set! current #f)
        (check-exception (.call view .selected-record 'custom/guestbook) error?))
      (let* ((current #t)
             (declarations
              (.o custom/guestbook:
                  (publication 'custom/guestbook (.o)
                    (lambda (_deps) (set! current #f) (.o ready: #t)))))
             (view (yuanxu-load-modules
                     (context declarations '(custom/guestbook) '() void
                              (lambda (_generation) current)))))
        (check-exception (.call view .selected-record 'custom/guestbook) error?)
        (check-exception ((.get view admit-current)) error?)))
    (yuanxu-test-case "selected scopes demand dependencies once, leave siblings cold"
      (let* ((reads '()) (links 0) (current #t)
             (declarations
              (.o core/schema: (publication 'core/schema (.o) (lambda (_deps) (.o schema: 'ready)))
                  custom/guestbook:
                  (publication 'custom/guestbook
                   (.o Schema: (.o module-id: 'core/schema contract: ObjectScope))
                   (lambda (_) (set! links (+ links 1)) (.o schema: 'ready)))
                  unused: (error "unselected publication forced")))
             (view (yuanxu-load-modules
                    (context declarations '(custom/guestbook) '()
                             (lambda (id) (set! reads (cons id reads)))
                             (lambda (_generation) current)))))
        (check-equal? reads '())
        (check-equal? (.get view modules custom guestbook schema) 'ready)
        (check-equal? reads '(core/schema custom/guestbook))
        (check-equal? (.get view dependency-order) '(core/schema custom/guestbook))
        (check-equal? links 1)
        (check-equal? (length (.get view selected-records)) 1)
        (set! current #f)
        (check-exception ((.get view admit-current)) error?)))
    (yuanxu-test-case "scope factory source change refuses before normalization can restore it"
      (def current #t)
      (def factory-ran #f)
      (def normalized 0)
      (def contract
        (.cc Type. identity: 'test/restoring-scope
          .element?: (lambda (scope)
                       (when factory-ran
                         (set! normalized (+ normalized 1))
                         (set! current #t))
                       (object? scope))))
      (def declarations
        (.o custom/guestbook:
            (.o identity: 'custom/guestbook features: (.o)
                core: (.o scope-contract: contract
                          exports: (begin
                                     (set! factory-ran #t) (set! current #f) (.o ready: #t))))))
      (def view
        (yuanxu-load-modules
          (context declarations '(custom/guestbook) '() void (lambda (_generation) current))))
      (check-exception (.get view selected-records) error?)
      (check-equal? factory-ran #t)
      (check-equal? normalized 0))
    (yuanxu-test-case "factory refusal retains its original exception after changing source"
      (def current #t)
      (def original (gensym 'factory-refusal))
      (def declarations
        (.o custom/guestbook:
            (publication 'custom/guestbook (.o)
              (lambda (_deps) (set! current #f) (raise original)))))
      (def view
        (yuanxu-load-modules
          (context declarations '(custom/guestbook) '() void (lambda (_generation) current))))
      (def caught (with-catch identity (lambda () (.get view selected-records) #f)))
      (check-equal? (eq? caught original) #t))
    (yuanxu-test-case "factory and end observer refusals retain both original causes"
      (for-each
        (lambda (original)
          (def observer-failure (gensym 'end-observer-refusal))
          (def stage '(scope-factory custom/guestbook))
          (def calls 0)
          (def ends 0)
          (def declarations
            (.o custom/guestbook:
                (publication 'custom/guestbook (.o)
                  (lambda (_deps) (set! calls (+ calls 1)) (raise original)))))
          (def view
            (yuanxu-load-modules
              (context declarations '(custom/guestbook) '() void (lambda (_generation) #t))))
          (def caught
            (parameterize
              ((current-module-source-observer
                (lambda (key _amount)
                  (when (equal? key (list 'link-stage-end stage))
                    (set! ends (+ ends 1))
                    (raise observer-failure)))))
              (with-catch identity (lambda () (.get view selected-records) #f))))
          (check-equal? calls 1)
          (check-equal? ends 1)
          (check-equal? (Error? caught) #t)
          (when (Error? caught)
            (check-equal? (Error-message caught) "module link stage and observer failed")
            (check-equal? (car (Error-irritants caught)) stage)
            (check-equal? (eq? (cadr (Error-irritants caught)) original) #t)
            (check-equal? (eq? (caddr (Error-irritants caught)) observer-failure) #t)))
        ;; A raised false value is still an original exception, never a sentinel.
        (list (gensym 'factory-refusal) #f)))
    (yuanxu-test-case "end observer refusal after successful factory keeps its identity"
      (def original (gensym 'end-observer-refusal))
      (def calls 0)
      (def declarations
        (.o custom/guestbook:
            (publication 'custom/guestbook (.o)
              (lambda (_deps) (set! calls (+ calls 1)) (.o)))))
      (def view
        (yuanxu-load-modules
          (context declarations '(custom/guestbook) '() void (lambda (_generation) #t))))
      (def caught
        (parameterize
          ((current-module-source-observer
            (lambda (key _amount)
              (when (equal? key '(link-stage-end (scope-factory custom/guestbook)))
                (raise original)))))
          (with-catch identity (lambda () (.get view selected-records) #f))))
      (check-equal? calls 1)
      (check-equal? (eq? caught original) #t))
    (yuanxu-test-case "stage observer source changes refuse before the next callback"
      (for-each
        (lambda (event)
          (def current #t)
          (def linked #f)
          (def normalized 0)
          (def contract
            (.cc Type. identity: 'test/observer-scope
              .element?: (lambda (scope)
                           (when linked
                             (set! normalized (+ normalized 1))
                             (set! current #t))
                           (object? scope))))
          (def declarations
            (.o custom/guestbook:
                (.o identity: 'custom/guestbook features: (.o)
                    core: (.o scope-contract: contract
                              exports: (begin
                                       (set! linked #t) (set! current #t) (.o))))))
          (def view
            (yuanxu-load-modules
              (context declarations '(custom/guestbook) '() void (lambda (_generation) current))))
          (parameterize
            ((current-module-source-observer
              (lambda (key _amount)
                (when (equal? key (list event '(scope-factory custom/guestbook)))
                  (set! current #f)))))
            (check-exception (.get view selected-records) error?))
          (check-equal? linked (eq? event 'link-stage-end))
          (check-equal? normalized 0))
        '(link-stage-start link-stage-end)))
    (yuanxu-test-case "disable and source owner mismatches refuse scope publication"
      (let* ((reads 0)
             (declarations (.o custom/guestbook:
                             (publication 'custom/guestbook
                              (.o Schema: (.o module-id: 'core/schema contract: ObjectScope))
                              (lambda (_deps) (error "link must not run")))))
             (view (yuanxu-load-modules
                    (context declarations '(custom/guestbook) '(core/schema)
                             (lambda (_id) (set! reads (+ reads 1)))
                             (lambda (_generation) #t)))))
        (check-exception (.get view selected-records) error?)
        (check-equal? reads 1)
        (check-exception ((.get view admit-current)) error?))
      (let (view (yuanxu-load-modules
                 (context (.o custom/guestbook:
                           (publication 'wrong (.o) (lambda (_deps) (.o))))
                          '(custom/guestbook) '() void (lambda (_generation) #t))))
        (check-exception (.get view selected-records) error?)))
    (yuanxu-test-case "cycles fail without retaining a usable partial session"
      (let* ((declarations
              (.o core/schema:
                  (publication 'core/schema
                   (.o App: (.o module-id: 'custom/guestbook contract: ObjectScope))
                   (lambda (_deps) (.o)))
                  custom/guestbook:
                  (publication 'custom/guestbook
                   (.o Schema: (.o module-id: 'core/schema contract: ObjectScope))
                   (lambda (_deps) (.o)))))
             (view (yuanxu-load-modules
                    (context declarations '(custom/guestbook) '() void
                             (lambda (_generation) #t)))))
        (check-exception (.get view selected-records) error?)
        (check-exception (.get view modules custom guestbook) error?)))))
