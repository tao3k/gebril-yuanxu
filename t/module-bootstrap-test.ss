;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source-only Graph admission is independent of compiler execution.
(import (only-in :std/test test-suite check-equal?)
        (only-in :gerbil/expander core-import-module expander-context-id module-context-import
                 module-context-export module-export-name core-resolve-module-export
                 resolve-identifier datum->syntax import-set? import-set-source
                 import-set-phi import-set-imports make-module-context
                 make-module-import make-module-export make-import-set
                 current-expander-context current-expander-module-import expander-context-table make-top-context eval-syntax module-export-phi
                 module-export-weak? module-export-key module-export-context core-module->prelude-context
                 make-prelude-context prelude-context-import)
        (only-in :std/list/list find)
        (only-in :tao3k/yuanxu/module-system/building/source-closure for-each-build-module)
        (only-in :tao3k/yuanxu/module-system/source/deferred-declaration module-binding-action)
        (only-in :tao3k/yuanxu/module-system/source/admission call-with-module-source-operation-measurement)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case yuanxu-test-observe)
        (only-in :tao3k/yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in "./qualification/testing/directory.ss" DirectoryFixture write-source)
        (only-in :std/source this-source-file)
        (only-in :clan/poo/object .get .call .o .cc)
        (only-in :tao3k/yuanxu/object-types/contracts yuanxu-contract-admit yuanxu-validation-evidence-accepted?)
        (only-in :tao3k/yuanxu/module-system/interface yuanxu-load-modules))
(export module-bootstrap-test)
(def root (path-expand ".." (path-directory (this-source-file))))
(def module-bootstrap-test
  (test-suite "Source tool consumes uncompiled JsonSchema publication"
    (yuanxu-test-fixture "role preludes retain old bindings and complete only weak runtime language exports"
      (directory DirectoryFixture)
      ;; Actual former source forms, expanded by Gerbil in the same process as
      ;; the production preludes. Only filenames/explicit package headers differ.
      (for-each
        (lambda (row)
          (def name (car row))
          (def file (path-expand (string-append name ".ss") (.get directory root)))
          (write-source file (cadr row))
          (def reference (core-import-module file))
          (def actual (core-import-module (path-expand
                         (string-append "module-system/source/" name ".ss") root)))
          (def expected (module-context-export reference))
          (def exported (module-context-export actual))
          (def core (core-import-module ':gerbil/core))
          ;; Count a multiset by public name/phase/weakness and canonical runtime
          ;; binding identity. Never compare renamed exports to private spelling.
          (def remaining (make-hash-table))
          (def added-phases (make-hash-table-eq))
          (def (resolved entry)
            ;; Raw export resolution can return an intermediate import/alias
            ;; binding (e.g. @make-object). Use runtime terminal resolution in
            ;; the exporting context, at the export's actual phase.
            (def key (module-export-key entry))
            (check-equal? (symbol? key) #t)
            (resolve-identifier (datum->syntax #f key)
              (module-export-phi entry) (module-export-context entry)))
          (def (key entry)
            (list (module-export-name entry) (module-export-phi entry) (module-export-weak? entry)))
          (def runtime (make-hash-table))
          (for-each
            (lambda (entry)
              (hash-put! runtime (list (module-export-name entry) (module-export-phi entry))
                (resolved entry))) (module-context-export core))
          (for-each
            (lambda (entry)
              (def metadata (key entry))
              (def bindings (or (hash-get remaining metadata) (make-hash-table-eq)))
              (hash-update! bindings (resolved entry) (cut + <> 1) 0)
              (hash-put! remaining metadata bindings)) expected)
          (for-each
            (lambda (entry)
              (def bindings (hash-get remaining (key entry)))
              (def binding (resolved entry))
              (def count (and bindings (hash-get bindings binding)))
              (if (and count (> count 0))
                (hash-put! bindings binding (- count 1))
                (begin
                  (hash-update! added-phases (module-export-phi entry) (cut + <> 1) 0)
                  ;; Former flattened import: omitted positive-phase exports.
                  ;; Any completion must be an actual public runtime binding,
                  ;; weak so explicit user bindings retain precedence.
                  (check-equal? (module-export-weak? entry) #t)
                  (let ((name (module-export-name entry)) (phase (module-export-phi entry)))
                    ;; A POO binding may shadow the weak Core name. Reexport
                    ;; the SAME effective runtime lookup, never the hidden
                    ;; defining-module binding underneath that shadow.
                    (check-equal?
                      (list name phase
                        (and (hash-key? runtime (list name phase))
                             (eq? binding (resolve-identifier (datum->syntax #f name) phase reference))))
                      (list name phase #t)))))) exported)
          (hash-for-each
            (lambda (_metadata bindings)
              (hash-for-each (lambda (_binding count) (check-equal? count 0)) bindings)) remaining)
          (check-equal? (hash-ref added-phases 0 0) 0)
          (def poo (core-import-module ':clan/poo/object))
          (for-each
            (lambda (name)
              (check-equal? (eq? (resolve-identifier (datum->syntax #f name) 0 actual)
                                (resolve-identifier (datum->syntax #f name) 0 poo)) #t))
            '(object? make-object))
          (when (string=? name "module-prelude")
            (let* ((declaration (core-import-module ':tao3k/yuanxu/module-system/source/declaration))
                   (declared (find (lambda (entry)
                                     (and (eq? (module-export-name entry) '.def)
                                          (= (module-export-phi entry) 0)))
                                   (module-context-export declaration))))
              ;; Export renaming does not rename the prelude module's private
              ;; lexical .def (the complete POO import). Test the real consumer
              ;; language, retaining exact identity with the published role API.
              (check-equal? (not (not declared)) #t)
              (def consumer (make-top-context (core-module->prelude-context actual)))
              (check-equal? (eq? (resolve-identifier (datum->syntax #f '.def) 0 consumer)
                                (resolved declared)) #t)))
          (parameterize ((current-expander-context
                          (make-top-context (core-module->prelude-context actual))))
            (check-equal? (eval-syntax '(let ((make-object 'local-constructor)
                                           (object? 'local-predicate))
                                        (list make-object object?)))
                          '(local-constructor local-predicate)))
          (def (dependency-order context)
            (def result '())
            (for-each-build-module context
              (lambda (child) (unless (eq? child context) (set! result (cons child result)))))
            (reverse result))
          (def before (dependency-order reference))
          (def after (dependency-order actual))
          (check-equal? (length before) (length after))
          (for-each (lambda (left right)
                      (check-equal? (list (expander-context-id left) (eq? left right))
                                    (list (expander-context-id left) #t))) before after)
          (def grouped (filter (lambda (entry)
                                (and (import-set? entry) (eq? (import-set-source entry) core)
                                     (= (import-set-phi entry) 0))) (module-context-import actual)))
          (check-equal? (length grouped) 1)
          (check-equal? (length (import-set-imports (car grouped))) (length (module-context-export core)))
          (displayln "ROLE-PRELUDE " name
            " imports=" (length (module-context-import reference)) "->" (length (module-context-import actual))
            " exports=" (length expected) "->" (length exported)
            " added-phases=" (hash->list added-phases)
            " dependency-contexts=" (length after)))
        '(("config-prelude"
           "prelude: :tao3k/yuanxu/prelude\npackage: prelude-audit\n(import (except-in :gerbil/core object? make-object) :clan/poo/object)\n(export (import: :gerbil/core :clan/poo/object))\n")
          ("module-prelude"
           "prelude: :gerbil/core\npackage: prelude-audit\n(import (except-in :gerbil/core object? make-object) (except-in :clan/poo/object .def) (only-in :tao3k/yuanxu/module-system/source/declaration .def) (phi: +1 :gerbil/core) (phi: +2 :gerbil/core))\n(export (import: :gerbil/core :clan/poo/object) (phi: +1 (import: :gerbil/core)) (phi: +2 (import: :gerbil/core)) (phi: 1 load-module) .def)\n"))))
    (yuanxu-test-case "binding factories share the runtime language frame without copying aliases"
      (def before (current-expander-context))
      ;; A real higher-order library function observes the active factory
      ;; context. No synthetic module or extra Fixture API is required.
      (def action (module-binding-action "std/func" 'repeat))
      (def context (car (action (list current-expander-context 1))))
      (def again (car (action (list current-expander-context 1))))
      (check-equal? (eq? before (current-expander-context)) #t)
      (check-equal? (eq? context again) #f)
      (check-equal? (hash-key? (expander-context-table context) 'repeat) #t)
      (check-equal? (hash-key? (expander-context-table context) 'make-object) #f)
      (def core (core-import-module ':gerbil/core))
      ;; Compare actual public import resolution, including renamed exports,
      ;; rather than the defining module's possibly shadowed private spelling.
      (def reference (make-top-context))
      (parameterize ((current-expander-context reference))
        (eval-syntax '(import :gerbil/core)))
      (yuanxu-test-observe 'factory-language-strong-bindings
        (list (hash-length (expander-context-table reference))
              (hash-length (expander-context-table context))))
      (def mismatches
        (filter-map
          (lambda (entry)
            (let ((name (module-export-name entry)) (phase (module-export-phi entry)))
              (let ((expected (resolve-identifier (datum->syntax #f name) phase reference))
                    (actual (resolve-identifier (datum->syntax #f name) phase context)))
                (and (or (not expected) (not (eq? actual expected)))
                     (list name phase)))))
          (module-context-export core)))
      (check-equal? mismatches '())
      ;; A runtime language name keeps strong import/collision semantics.
      (check-equal? ((module-binding-action "gerbil/core" 'list) '(one two)) '(one two))
      (def failure #f)
      (with-catch (lambda (error) (set! failure error))
        (lambda () ((module-binding-action "std/list/list" 'missing-factory-binding) '())))
      (check-equal? (not (not failure)) #t)
      (check-equal? (eq? before (current-expander-context)) #t))
    (yuanxu-test-case "binding factories preserve the invoking import owner"
      (def import-owner (current-expander-module-import))
      (def imports '())
      (parameterize ((current-expander-module-import
                       (lambda arguments
                         (let (context (apply import-owner arguments))
                           (set! imports (cons (expander-context-id context) imports))
                           context))))
        (check-equal?
          ((module-binding-action "std/func" 'repeat) (list (lambda () 42) 2))
          '(42 42)))
      (check-equal? (and (memq 'std/func imports) #t) #t))
    (yuanxu-test-case "direct Gerbil preludes retain their complete module association"
      (def language (core-import-module ':gerbil/core))
      ;; The Gerbil constructor is valid independently of its registry-caching
      ;; helper. Do not register it just to make traversal succeed.
      (def prelude (make-prelude-context language))
      (def context (make-module-context 'direct-prelude/root #f #f #f))
      (slot-set! context 'super prelude)
      (def visited '())
      (for-each-build-module context
        (lambda (owner) (set! visited (cons owner visited))))
      (check-equal? (and (memq language visited) #t) #t)
      (check-equal? (car visited) context)
      ;; Dropping a real export cannot claim the same full association.
      (def incomplete (make-prelude-context language))
      (slot-set! incomplete 'import (cdr (prelude-context-import incomplete)))
      (def invalid (make-module-context 'direct-prelude/incomplete #f #f #f))
      (slot-set! invalid 'super incomplete)
      (def rejected #f)
      (with-catch (lambda (_) (set! rejected #t))
        (lambda () (for-each-build-module invalid void)))
      (check-equal? rejected #t))
    (yuanxu-test-case "runtime cursor preserves alias order, cycles, pruning and failure"
      ;; Isolated runtime metadata, not issued Module publications or a Loader.
      (def root (make-module-context 'cursor/root #f #f #f))
      (def left (make-module-context 'cursor/left #f #f #f))
      (def right (make-module-context 'cursor/right #f #f #f))
      (def shared (make-module-context 'cursor/shared #f #f #f))
      (def alias (make-module-import (make-module-export shared 'value 0 'value #f) 'value 0 #f))
      (slot-set! root 'import (list left (make-import-set right 0 '()) left))
      (slot-set! left 'import (list alias alias))
      (slot-set! right 'import (list shared))
      (slot-set! shared 'import (list root))
      (def (walk (descend? (lambda (_context) #t)) (stop #f))
        (def visited '())
        (def caught #f)
        (with-catch
          (lambda (error) (set! caught error))
          (lambda ()
            (for-each-build-module root
              (lambda (context)
                (set! visited (cons (expander-context-id context) visited))
                (when (and stop (eq? context left)) (raise stop)))
              (make-hash-table-eq) descend?)))
        (values (reverse visited) caught))
      (defvalues (complete failure) (walk))
      (check-equal? complete '(cursor/shared cursor/left cursor/right cursor/root))
      (check-equal? failure #f)
      (defvalues (pruned _failure) (walk (lambda (context) (not (eq? context left)))))
      (check-equal? pruned '(cursor/left cursor/shared cursor/right cursor/root))
      (def original-error (list 'cursor-stop))
      (defvalues (stopped caught) (walk (lambda (_context) #t) original-error))
      (check-equal? stopped '(cursor/shared cursor/left))
      (check-equal? (eq? caught original-error) #t)
      (defvalues (again _again-failure) (walk))
      (check-equal? again complete))
    (yuanxu-test-case "prelude retains complete runtime import sets and POO constructors"
      (def prelude (core-import-module (path-expand "prelude.ss" root)))
      (def core (core-import-module ':gerbil/core))
      (def grouped
        (filter (lambda (entry)
                  (and (import-set? entry) (eq? (import-set-source entry) core)
                       (= (import-set-phi entry) 0)))
                (module-context-import prelude)))
      (check-equal? (length grouped) 1)
      ;; A compact dependency retains ALL runtime aliases, not an empty
      ;; dependency marker which silently removes the language's exports.
      (check-equal? (length (import-set-imports (car grouped)))
                    (length (module-context-export core)))
      (def poo (core-import-module ':clan/poo/object))
      (for-each
        (lambda (name)
          (check-equal?
            (eq? (resolve-identifier (datum->syntax #f name) 0 prelude)
                 (resolve-identifier (datum->syntax #f name) 0 poo)) #t))
        '(object? make-object .o .get .ref)))
    (yuanxu-test-case "Core prelude bindings retain explicit runtime dependencies"
      (def object-context (core-import-module ':clan/poo/object))
      (def exports (module-context-export object-context))
      (for-each
        (lambda (file)
          (def context (core-import-module (path-expand file root)))
          ;; runtime: keeps an actual runtime context edge, not an empty only-in
          ;; or a private dependency inventory outside Gerbil's import graph.
          (check-equal? (and (memq object-context (module-context-import context)) #t) #t)
          (for-each
            (lambda (name)
              (def exported (find (lambda (entry) (eq? name (module-export-name entry))) exports))
              (check-equal?
                (eq? (resolve-identifier (datum->syntax #f name) 0 context)
                     (core-resolve-module-export exported)) #t))
            '(.o .get .ref)))
        '("module-system/building/interface.ss" "module-system/building/build-projection.ss"
          "module-system/source/build.ss" "admission/source.ss"
          "object-types/contracts.ss")))
    (yuanxu-test-case "runtime imports preserve deliberate constructor and predicate shadows"
      (for-each
        (lambda (row)
          (def context (core-import-module (path-expand (car row) root)))
          (def origin (core-import-module (cadr row)))
          (for-each
            (lambda (name)
              ;; gerbil/core reexports import-binding nodes. Compare resolved
              ;; runtime bindings on both sides, not a wrapper with its referent.
              (check-equal?
                (eq? (resolve-identifier (datum->syntax #f name) 0 context)
                     (resolve-identifier (datum->syntax #f name) 0 origin)) #t))
            '(object? make-object)))
        '(("module-system/schema/support/object.ss" :clan/poo/object)
          ("graph/operation.ss" :gerbil/core))))
    (yuanxu-test-case "shared-root DFS preserves identity without retaining a cross-call cache"
      ;; Deferring runtime Build activation must not be confused with deleting
      ;; its compiler metadata from the existing explicit build owner.
      (def build-covered? #f)
      (for-each-build-module
        (core-import-module ':tao3k/yuanxu/module-system/building/build-projection)
        (lambda (context)
          (when (eq? (expander-context-id context) 'tao3k/yuanxu/module-system/source/build)
            (set! build-covered? #t))))
      (check-equal? build-covered? #t)
      (def roots
        (map core-import-module
          '(:tao3k/yuanxu/module-system/building/build-projection
            :tao3k/yuanxu/module-system/building/configuration-source)))
      (def expected (make-hash-table))
      (def repeated 0)
      (for-each (lambda (root)
                  (for-each-build-module root
                    (lambda (context)
                      (set! repeated (+ repeated 1))
                      (hash-put! expected (expander-context-id context) context)))) roots)
      (def (walk)
        (def seen (make-hash-table-eq))
        (def visits 0)
        (for-each (lambda (root)
                    (for-each-build-module root
                      (lambda (context)
                        (set! visits (+ visits 1))
                        (check-equal?
                          (eq? context (hash-ref expected (expander-context-id context))) #t))
                      seen)) roots)
        (check-equal? visits (hash-length expected))
        (check-equal? (< visits repeated) #t)
        visits)
      (def visits (walk))
      (check-equal? visits (walk))
      (yuanxu-test-observe 'bootstrap-root-visits repeated)
      (yuanxu-test-observe 'bootstrap-union-visits visits))
    (yuanxu-test-case "init selects a source Graph and exposes the declared Contract"
      (let ((view (yuanxu-load-modules (path-expand "init.ss" root))))
        (defvalues (graph costs)
          (call-with-module-source-operation-measurement (lambda () (.get view build-graph))))
        (def scope (.get view modules Modules json-schema))
        (def contract (.call scope contract 'bootstrap/value
                         '((type . "object") (required . ("value"))
                           (properties . ((value . ((type . "string"))))))))
        ;; Exercise the real Core declarations and constructor-owned standard
        ;; source bindings. No fixture supplies a bound path or a pure flag.
        (check-equal? (> (hash-ref costs '(calls reader-bound-source-reuse) 0) 0) #t)
        (yuanxu-test-observe 'bound-source-reuses (hash-ref costs '(calls reader-bound-source-reuse) 0))
        (yuanxu-test-observe 'build-source-resolutions (hash-ref costs '(calls reader-source-resolution) 0))
        (check-equal? (.get view selected-graph module-order)
                      '(tao3k/yuanxu/modules/json-schema/interface
                        tao3k/yuanxu/modules/funflow/interface
                        tao3k/yuanxu/scenarios/gitea-postgresql/postgresql/interface
                        tao3k/yuanxu/scenarios/gitea-postgresql/gitea/interface
                        tao3k/yuanxu/scenarios/gitea-postgresql/interface))
        (check-equal? (> (length (.get graph entries)) 15) #t)
        (check-equal? (yuanxu-validation-evidence-accepted?
                       (yuanxu-contract-admit contract (.o value: "pass") #f)) #t)
        (check-equal? (yuanxu-validation-evidence-accepted?
                       (yuanxu-contract-admit contract (.o value: 7) #f)) #f)
        (def parent-type (.get contract value-contract))
        (def restricted-type
          (.cc (.get contract value-type)
            '.element? (lambda (_value) #f)
            '.diagnose (lambda (_value location)
                         (list (.o kind: 'test-policy path: location)))))
        (def child (.cc contract 'value-type restricted-type))
        (check-equal? (eq? (.get child value-contract) restricted-type) #t)
        (check-equal? (eq? (.get contract value-contract) parent-type) #t)
        (check-equal? (yuanxu-validation-evidence-accepted?
                       (yuanxu-contract-admit child (.o value: "pass") #f)) #f)
        (check-equal? (yuanxu-validation-evidence-accepted?
                       (yuanxu-contract-admit contract (.o value: "pass") #f)) #t)))))
