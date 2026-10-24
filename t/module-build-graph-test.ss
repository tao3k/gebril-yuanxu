;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :std/make make)
        (only-in :std/list/list find)
        (only-in :gerbil/expander eval-syntax current-expander-context make-top-context syntax->list core-read-module/sexp)
        (only-in :clan/poo/object .o .+ .cc .ref .get .call object? NoApplicableMethod?)
        (only-in :clan/poo/object-contract ObjectContract.)
        (only-in :clan/poo/type String)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)
        (only-in :yuanxu/feature-system/model feature-descriptor)
        (only-in :yuanxu/feature-system/capability-model feature-projection-request)
        (only-in :yuanxu/module-system/source/objects yuanxu-module-source-ref-metadata)
        (only-in :yuanxu/module-system/source/admission module-source-type module-source-read current-module-source-observer
                 call-with-module-source-read-cache module-source-admit-current!)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/preparation yuanxu-prepare-module-retained-source)
        (only-in :yuanxu/module-system/building/interface yuanxu-init-build call-with-init-build-spec)
        (only-in "../core-spec.ss" core-spec)
        (only-in :yuanxu/module-system/building/build-projection yuanxu-project-source-spec))
(export module-build-graph-test)
(def Scope (yuanxu-predicate-contract 'test/build-scope object? (lambda (_v _c) '())))
(def (write-file path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (lambda (port) (display text port))))
(def (remove-tree path)
  (if (eq? (module-source-type path) 'directory)
    (begin (for-each (lambda (name) (remove-tree (path-expand name path))) (directory-files path))
           (delete-directory path)) (delete-file path)))
(def (with-source test)
  (let* ((root (make-temporary-file-name "selected-build-"))
         (prefix (symbol->string (gensym 'build-fixture-))))
    (dynamic-wind
     (lambda ()
       (write-file (path-expand "gerbil.pkg" root) (string-append "(package: " prefix ")"))
       (write-file (path-expand "init.ss" root)
                   "(yuanxu! mode: explicit :core (schema) :app (web +late +early -off) :unused (bomb disable: #t))")
       (for-each
        (lambda (id)
          (let (directory (path-expand (string-append "modules/" id) root))
            (write-file (path-expand "types.ss" directory)
             "(import (only-in :clan/poo/object object?) (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)) (def Scope (yuanxu-predicate-contract 'fixture object? (lambda (_v _c) '()))) (export Scope)")
            (write-file (path-expand "objects.ss" directory)
             "(import (only-in :clan/poo/object .o) \"types.ss\") (def Defaults (.o retained: #t)) (export Defaults)")
            (write-file (path-expand "config.ss" directory) "(import (only-in :std/source this-source-file)) (def Greeting \"ready\") (def Origin (this-source-file)) (export Greeting Origin)")
            (write-file (path-expand "extra/core.ss" directory) "(def CoreExtra #t) (export CoreExtra)")
            (write-file (path-expand "interface.ss" directory)
             (string-append "(.def Published identity: '" id
               (if (string=? id "app/web")
                   " core: (.o requires: (.o Schema: (.o module-id: 'core/schema contract: Scope)) scope-contract: Scope exports: (.o greeting: Greeting)) features: (.o))"
                   " core: (.o requires: (.o) scope-contract: Scope exports: (.o greeting: Greeting)) features: (.o))")))))
        '("app/web" "core/schema"))
       (write-file (path-expand "modules/app/web/extra/early.ss" root)
                   "(def Early 'early) (export Early)")
       (write-file (path-expand "modules/app/web/extra/late.ss" root)
                   "(import \"early.ss\") (def Late Early) (export Late)")
       (write-file (path-expand "modules/unused/bomb/interface.ss" root) "(((unselected must never compile")
       (write-file (path-expand "modules/app/web/extra/off.ss" root) "(((disabled feature must never compile"))
     (lambda () (test root prefix))
     (lambda () (remove-tree root)))))
(def (build-contribution . root-values) (.o kind: 'module/build roots: root-values))
(def (optional name paths (dependencies '()))
  (feature-descriptor
   (.o feature-id: (string->symbol (string-append "app/web/" (symbol->string name)))
       owner-module-id: 'app/web requires: dependencies
       projections: (list (apply build-contribution paths)))))
(def (fixture-view root (feature-values #f) (core-projections '()))
  (yuanxu-load-modules (path-expand "init.ss" root)
   read-publication:
   (lambda (source)
     (let (id (cdr (assq 'module-id (yuanxu-module-source-ref-metadata source))))
       (.o identity: id
           features: (if (eq? id 'app/web)
                       (or feature-values (.o early: (optional 'early '("extra/early"))
                                        late: (optional 'late '("extra/late") '(app/web/early))
                                        off: (error "negative Feature forced"))) (.o))
           core: (.o requires: (if (eq? id 'app/web)
                                (.o Schema: (.o module-id: 'core/schema contract: Scope)) (.o))
                     projections: core-projections scope-contract: Scope
                     link: (lambda (_deps) (error "build must not link domain scopes"))))))))
(def (entry-names graph)
  (map (lambda (entry) (.get entry compiler-identity)) (.get graph entries)))
(def module-build-graph-test
  (test-suite "Selected Core and Feature compiler input Graph"
    (yuanxu-test-case "library inventory does not compile the init selection owner"
      (check-equal? (member "init" core-spec) #f)
      (check-equal? (member "build" core-spec) #f)
      ;; These are ordinary library APIs, not linked Module interfaces.
      (check-equal? (and (member "module-system/selection/init-syntax" core-spec) #t) #t)
      (check-equal? (and (member "ops/interface" core-spec) #t) #t)
      (check-equal? (member "modules/json-schema/interface" core-spec) #f)
      (check-equal? (member "modules/funflow/interface" core-spec) #f)
      (check-equal? (ormap (cut string-prefix? "scenarios/" <>) core-spec) #f))
    (yuanxu-test-case "retained inclusion preserves native leading-header semantics"
      (with-source
       (lambda (root prefix)
         (for-each
          (lambda (case)
            (def path (path-expand (string-append (car case) ".ss") root))
            (write-file path (cadr case))
            (def prepared (yuanxu-prepare-module-retained-source path void))
            (check-equal? (.get prepared compiler-identity)
                          (string->symbol (string-append prefix "/" (car case))))
            (def direct? (and (member `(include ,path) (.get prepared compiler-forms)) #t))
            (check-equal? direct? (caddr case))
            (write-file path ";; changed after native preparation")
            (check-exception ((.get prepared admit-current)) error?))
          '(("plain" ";; comment\n(def value '(namespace: package:)) (export value)" #t)
            ("empty" ";; comment only\n" #t)
            ("namespace" ";; comment\nnamespace: explicit\n(def value 7) (export value)" #f)
            ("prelude" "prelude: :gerbil/core\n(def value 7) (export value)" #f)
            ("package" "package: #f\n(def value 7) (export value)" #f)))
         ;; This SDK rejects an explicit false namespace under gerbil.pkg.
         ;; Preparation must preserve that native refusal rather than normalize it.
         (def path (path-expand "namespace-false.ss" root))
         (write-file path "namespace: #f\n(def value 7) (export value)")
         (check-exception (core-read-module/sexp path) syntax-error?)
         (check-exception (yuanxu-prepare-module-retained-source path void) syntax-error?))))
    (yuanxu-test-case "SDK dispatch receives the admitted spec and rejects stale input first"
      (with-source
       (lambda (root _prefix)
         (def declaration '(yuanxu! :load-modules "./modules" mode: explicit :core (schema)))
         (write-file (path-expand "init.ss" root)
           (call-with-output-string (cut write declaration <>)))
         (write-file (path-expand "build.ss" root) "(export #t)")
         (defvalues (exports _modules)
           (yuanxu-init-build (path-expand "init.ss" root) declaration))
         (def spec (.get exports std-make-spec))
         (check-exception (.get exports std-make-run) NoApplicableMethod?)
         (def expected (spec '()))
         (def calls 0)
         ;; Observe the ordinary SDK callback without compiling fixture files.
         (def (receive admitted arguments)
           (set! calls (1+ calls))
           (check-equal? (eq? admitted expected) #t)
           (check-equal? arguments '("spec"))
           'forwarded)
         ;; The declarative SDK adapter obtains the same owner from the spec
         ;; expression, with no user-maintained dispatcher or public registry.
         (check-equal?
           (call-with-init-build-spec (cut spec '()) receive '("spec") (path-expand "lib" root))
           'forwarded)
         (check-equal? calls 1)
         (check-exception
           (call-with-init-build-spec
             (lambda () (map identity (spec '()))) receive '("spec") (path-expand "lib" root))
           error?)
         (check-equal? calls 1)
         ;; A native package callback returns no publication authority. The
         ;; explicit projection .compile must reject missing compiler outputs.
         (def compile-calls 0)
         (def (uncompiled admitted arguments)
           (set! compile-calls (1+ compile-calls))
           (check-equal? (eq? admitted expected) #t)
           (check-equal? arguments '("compile"))
           'package-only)
         (def projection
           (yuanxu-project-source-spec
             (yuanxu-load-modules (path-expand "init.ss" root)) '() root
             (path-expand "build.ss" root)))
         (check-exception
           (.call projection .compile (path-expand "lib" root)
             (cut uncompiled expected '("compile"))) error?)
         (check-equal? compile-calls 1)
         ;; The SDK entry must enforce the same complete-product boundary;
         ;; a callback return value cannot authorize an absent runtime.
         (check-exception
           (call-with-init-build-spec (cut spec '()) uncompiled '("compile")
             (path-expand "lib" root))
           error?)
         (check-equal? compile-calls 2)
         (def config (path-expand "modules/core/schema/config.ss" root))
         (write-file config (string-append (module-source-read config) "\n;; stale request\n"))
         (check-exception
           (call-with-init-build-spec (cut spec '()) receive '("spec")
             (path-expand "lib" root)) error?)
         (check-equal? calls 1))))
    (yuanxu-test-case "configuration admission precedes publication binding"
      (with-source
       (lambda (root _prefix)
         (write-file (path-expand "init.ss" root)
           "(yuanxu! :load-modules \"./modules\" mode: explicit :app (web))")
         (def settings-type (.cc ObjectContract. 'responsibilities (.o message: String)))
         (def bindings 0)
         ;; The hook is an effect probe: a rejected configuration must never
         ;; reach it, even when the scope's outer shape Contract accepts.
         (def export-value
           (.o .bind-publication:
             (lambda (_selection owner-id admission-name guard)
               (set! bindings (1+ bindings))
               (.o owner: owner-id admission: admission-name package-current: guard))))
         ;; Each request has its own ordinary selection and refused epoch.
         (def (select candidate-value)
           (yuanxu-load-modules (path-expand "init.ss" root)
             read-publication:
             (lambda (_source)
               (.o identity: 'app/web features: (.o)
                 core:
                 (.o requires: (.o) scope-contract: Scope
                   admissions:
                   (.o Config: (.o export-path: '(config) contract-path: '(types Config))
                       Value: (.o export-path: '(value) contract-path: '(types Value)))
                   link:
                   (lambda (_dependencies)
                     (.o config: candidate-value value: export-value
                         types: (.o Config: settings-type Value: Scope))))))))
         (check-exception (.get (select (.o message: 123)) modules modules app web) error?)
         (check-equal? bindings 0)
         (check-exception (.get (select (.o message: "ok" typo: #t)) modules modules app web) error?)
         (check-equal? bindings 0)
         (def accepted (.get (select (.o message: "ok")) modules modules app web))
         (check-equal? (.get accepted config message) "ok")
         (check-equal? (.get accepted value owner) 'app/web)
         (check-equal? (.get accepted value admission) 'Value)
         (check-equal? (.get accepted value package-current) #f)
         (check-equal? bindings 1))))
    (yuanxu-test-case "direct package scope is confined to its selected publication"
      (with-source
       (lambda (root _prefix)
         (write-file (path-expand "init.ss" root)
           "(yuanxu! :load-modules \"./modules\" mode: explicit :app (web) :core (schema))")
         ;; Probe the handoff, not Nix realization. The product service gate
         ;; separately verifies actual Provider/Schema/engine outputs.
         (def (projection name)
           (.o kind: 'module/external-package identity: name
             .prepare:
             (lambda (_root current! _publication)
               (.o identity: name source-inputs: '() input-files: '()
                 admit-current: current!
                 .realize: (lambda (_directory _guard) (error "unexpected realization"))))))
         (def (select projection-values)
           (yuanxu-load-modules (path-expand "init.ss" root)
             read-publication:
             (lambda (source)
               (let (id (cdr (assq 'module-id (yuanxu-module-source-ref-metadata source))))
                 (.o identity: id features: (.o)
                   core: (.o requires: (.o) scope-contract: Scope
                           projections: (if (eq? id 'app/web) projection-values '())
                           link: (lambda (_dependencies) (.o greeting: 'source retained: #t))))))))
         (def view (select (list (projection 'web-package))))
         (def graph (.get view build-graph))
         (check-equal? (.get (car (.get graph external-packages)) scope-owner) 'app/web)
         (def current? #t)
         (def (current!) (unless current? (error "stale package probe")))
         (def package-parent (.o greeting: 'package-parent retained: #f))
         (def packages
           (.o build-graph: graph
             packages:
             (.o web-package:
               (.o scope: (.o (:: @ package-parent) greeting: 'realized)))
             sources-current: current! admit-current: current!))
         (def ready (.call view .with-packages packages))
         (check-equal? (.get ready modules modules app web greeting) 'realized)
         (check-equal? (.get ready modules modules app web retained) #t)
         (check-equal? (.get ready modules modules core schema greeting) 'source)
         (check-exception (.call (select '()) .with-packages packages) error?)
         (set! current? #f)
         (check-exception ((.get ready admit-current)) error?)
         (def ambiguous (select (list (projection 'first) (projection 'second))))
         (def conflicting
           (.o build-graph: (.get ambiguous build-graph)
             packages: (.o first: (.o scope: (.o)) second: (.o scope: (.o)))
             sources-current: void admit-current: void))
         (check-exception (.get (.call ambiguous .with-packages conflicting) modules modules app web) error?))))
    (yuanxu-test-case "package handoff retains the selected source Graph without linking scopes"
      (with-source
       (lambda (root _prefix)
         (def view (fixture-view root))
         (def graph (.get view build-graph))
         (def selected (.get view selected-graph))
         ;; Package effects are probes here; real Nix remains in the AWS gate.
         (def packages
           (.o build-graph: graph packages: (.o)
             sources-current: (lambda () #t) admit-current: (lambda () #t)))
         (def realized (.call view .with-packages packages))
         (check-equal? (eq? (.get realized build-graph) graph) #t)
         (check-equal? (eq? (.get realized selected-graph) selected) #t)
         (write-file (path-expand "modules/app/web/config.ss" root) "(def Config 'changed)")
         (check-exception ((.get realized admit-current)) error?))))
    (yuanxu-test-case "one pure window shares a Graph traversal but independent calls recheck"
      (with-source
       (lambda (root _prefix)
         (def view (fixture-view root))
         (def graph (.get view build-graph))
         (def checks 0)
         (parameterize ((current-module-source-observer
                         (lambda (key amount)
                           (when (eq? key 'checks) (set! checks (+ checks amount))))))
           (call-with-module-source-read-cache
             (lambda ()
               ((.get graph compiler-current))
               (def first checks)
               ((.get graph compiler-current))
               ;; Only the public request remains; its retained entry guards
               ;; are not traversed again in this same stable byte window.
               (check-equal? (- checks first) 1)))
           (def previous checks)
           ((.get graph compiler-current))
           (check-equal? (> (- checks previous) 1) #t))
         (write-file (path-expand "modules/app/web/config.ss" root) "(def Config 'changed)")
         (check-exception ((.get graph admit-current)) error?))))
    (yuanxu-test-case "init to publication to build uses the default reader and never links scopes"
      (with-source
       (lambda (root prefix)
         (let (path (path-expand "modules/app/web/interface.ss" root))
           (write-file path
            (string-append
             "(import (only-in :yuanxu/feature-system/model feature-descriptor)) "
             "(.def Published identity: 'app/web core: (.o requires: (.o Schema: (.o module-id: 'core/schema contract: Scope)) scope-contract: Scope exports: (error \"must not link while building\")) features: "
             "(.o early: (feature-descriptor (.o feature-id: 'app/web/early owner-module-id: 'app/web projections: (list (.o kind: 'module/build roots: '(\"extra/early\"))))) "
             "late: (feature-descriptor (.o feature-id: 'app/web/late owner-module-id: 'app/web requires: '(app/web/early) projections: (list (.o kind: 'module/build roots: '(\"extra/late\"))))) "
             "off: (error \"negative feature must not evaluate\")))")))
         (let* ((view (yuanxu-load-modules (path-expand "init.ss" root)))
                (graph (.get view build-graph)))
           (check-equal? (.get view selected-graph module-order) '(core/schema app/web))
           (check-equal? (.get view selected-graph feature-order) '(app/web/early app/web/late))
           ;; The compiler projection consumes the reader's exact role input,
           ;; including its guard; it must not create a duplicate source object.
           (let* ((prepared (.call view prepare-publication 'app/web))
                  (path (path-normalize (path-expand "modules/app/web/config.ss" root)))
                  (observed (find (lambda (input) (equal? (.get input path) path))
                                  (.get prepared source-dependencies)))
                  (entry (find (lambda (entry) (equal? (.get entry path) path))
                               (.get graph entries))))
             (check-equal? (object? observed) #t)
             (check-equal? (eq? (.get entry input) observed) #t))
           (let (names (map symbol->string (entry-names graph)))
             ;; Contribution targets belong to the contribution package. SDK
             ;; tools stay guarded, but must not become its compiler targets.
             (check-equal? (length (filter (lambda (name)
                                            (string-prefix? (string-append prefix "/") name)) names)) 10)
             (check-equal? (ormap (cut string-prefix? "yuanxu/" <>) names) #f)
             (def reads '())
             (parameterize ((current-module-source-observer
                             (lambda (key _amount)
                               (when (and (pair? key) (eq? (car key) 'file-read))
                                 (set! reads (cons (caddr key) reads))))))
               ((.get graph compiler-current)))
             (for-each
               (lambda (suffix)
                 (check-equal? (ormap (cut string-suffix? suffix <>) reads) #t))
               '("/module-system/source/declaration.ss" "/types.ss")))
           (check-exception (.get view modules app web) error?)))))
    (yuanxu-test-case "roles derive once, Core dependency precedes consumer, optional order follows Graph"
      (with-source
       (lambda (root prefix)
         (let* ((v (fixture-view root)) (graph (.get v build-graph))
                (names (map symbol->string (entry-names graph))))
           (check-equal? (length names) 10)
           (check-equal? names
            (map (lambda (name) (string-append prefix "/modules/" name))
             '("core/schema/types" "core/schema/objects" "core/schema/config" "core/schema/interface"
               "app/web/types" "app/web/objects" "app/web/config" "app/web/interface"
               "app/web/extra/early" "app/web/extra/late")))
           (check-equal? (.get v selected-graph feature-order) '(app/web/early app/web/late))
           (check-equal? (length (.get graph other-projections)) 0)))))
    (yuanxu-test-case "a different selected generation cannot reuse the parent's preparations"
      (with-source
       (lambda (root _prefix)
         (let* ((v (fixture-view root)) (parent (.get v build-graph))
                (other (.+ v (.o selected-graph: (.+ (.get v selected-graph) (.o generation: "other"))))))
           (check-equal? (length (.get parent entries)) 10)
           (check-exception (.get other build-graph) error?)))))
    (yuanxu-test-case "optional func role becomes a root without a second inventory"
      (with-source
       (lambda (root prefix)
         (write-file (path-expand "modules/app/web/func.ss" root) "(def (identity-value x) x) (export identity-value)")
         (let (names (entry-names (.get (fixture-view root) build-graph)))
           (check-equal? (length names) 11)
           (check-equal? (and (memq (string->symbol (string-append prefix "/modules/app/web/func")) names) #t) #t)))))
    (yuanxu-test-case "additional Core and Feature contributions use one ordered projection"
      (with-source
       (lambda (root _prefix)
         (let (graph (.get (fixture-view root #f (list (build-contribution "extra/core"))) build-graph))
           (check-equal? (length (.get graph entries)) 12)))))
    (yuanxu-test-case "identical contributions deduplicate and differing options conflict"
      (with-source
       (lambda (root _prefix)
         (let* ((v (fixture-view root
                     (.o early: (optional 'early '("extra/early"))
                         late: (optional 'late '("extra/early") '(app/web/early))
                         off: (error "negative Feature forced"))))
                (graph (.get v build-graph)))
           (check-equal? (length (.get graph entries)) 9))
         (check-exception
          (.get (fixture-view root
                  (.o early: (optional 'early '("extra/early"))
                      late: (optional 'late '((gxc: "extra/early" "-debug")) '(app/web/early))
                      off: (error "negative Feature forced"))) build-graph) error?))))
    (yuanxu-test-case "foreign requests are retained; unknown and unresolved build projections reject"
      (with-source
       (lambda (root _prefix)
         (let (graph (.get (fixture-view root #f (list (feature-projection-request 'r 'runtime 'v1))) build-graph))
           (check-equal? (length (.get graph other-projections)) 2))
         (for-each
          (lambda (projection)
            (check-exception (.get (fixture-view root #f (list projection)) build-graph) error?))
          (list 'bad (.o kind: 'module/build roots: '(42)) (feature-projection-request 'r 'build 'v1))))))
    (yuanxu-test-case "owner-relative paths cannot escape or traverse symlinks"
      (with-source
       (lambda (root _prefix)
         (for-each
          (lambda (path)
            (check-exception
             (.get (fixture-view root #f (list (build-contribution path))) build-graph) error?))
          '("../escape" "/absolute/file" "extra/missing"))
         (create-symbolic-link (path-expand "modules/app/web/extra/early.ss" root)
                               (path-expand "modules/app/web/extra/link.ss" root))
         (check-exception
          (.get (fixture-view root
                  (.o early: (optional 'early '("extra/link"))
                      late: (optional 'late '("extra/late") '(app/web/early)) off: #f)) build-graph) error?))))
    (yuanxu-test-case "direct projection preserves targets and never writes a prepared tree"
      (with-source
       (lambda (root prefix)
         (write-file (path-expand "build.ss" root) "(export #t)")
         (let* ((v (fixture-view root))
                (artifact (yuanxu-project-source-spec v '() root (path-expand "build.ss" root)))
                (names (map cadr (.get artifact spec))))
           (check-equal? (eq? (.get artifact build-graph) (.get v build-graph)) #t)
           (check-equal? (length names) 10)
           (check-equal? (andmap (cut string-prefix? "modules/" <>) names) #t)
           (check-equal? (file-exists? (path-expand ".gerbil" root)) #f)
           (write-file (path-expand "modules/app/web/config.ss" root) ";; changed")
           (check-exception ((.get artifact admit-current)) error?)))))
    (yuanxu-test-case "retained headers share pure Graph checks without retaining freshness"
      (with-source
       (lambda (root _prefix)
         (write-file (path-expand "build.ss" root) "(export #t)")
         (def view (fixture-view root))
         (.get view build-graph)
         (def retained '("retained/a" "retained/b" "retained/c" "retained/d"))
         (for-each
           (lambda (name)
             (write-file (path-expand (string-append name ".ss") root) "(export #t)"))
           retained)
         ;; Count actual filesystem observation windows, not guard requests.
         ;; Every retained source must still be checked on independent reuse.
         (def (project names)
           (def windows 0)
           (def artifact
             (parameterize ((current-module-source-observer
                             (lambda (key amount)
                               (when (eq? key 'read-windows)
                                 (set! windows (+ windows amount))))))
               (yuanxu-project-source-spec view names root (path-expand "build.ss" root))))
           (values artifact windows))
         (defvalues (_single single-windows) (project (list (car retained))))
         (defvalues (many many-windows) (project retained))
         (check-equal? many-windows single-windows)
         (check-equal? (length (.get many spec)) 14)
         (write-file (path-expand "retained/d.ss" root) ";; changed after preparation")
         (check-exception ((.get many admit-current)) error?))))
    (yuanxu-test-case "unconsumed generated contributions cannot silently disappear from spec"
      (with-source
       (lambda (root _prefix)
         (write-file (path-expand "build.ss" root) "(export #t)")
         (let (v (fixture-view root #f (list (feature-projection-request 'r 'runtime 'v1))))
           (check-exception
            (yuanxu-project-source-spec v '() root (path-expand "build.ss" root)) error?)))))
    (yuanxu-test-case "stale init, role and contribution inputs refuse reuse"
      (for-each
       (lambda (file)
         (with-source
          (lambda (root _prefix)
            (let* ((v (fixture-view root)) (graph (.get v build-graph)) (out (path-expand "stale" root)))
              (write-file (path-expand file root) ";; changed")
              (check-exception ((.get graph admit-current)) error?)
              (check-exception (module-source-admit-current! (.get graph source-inputs)) error?)
              (check-exception (yuanxu-project-source-spec v '() root (path-expand "init.ss" root)) error?)
              (check-equal? (module-source-type (path-expand "build.ss" out)) #f)))))
       '("init.ss" "modules/app/web/config.ss" "modules/app/web/extra/late.ss" "modules/app/web/func.ss" "modules/app/web/extra/gerbil.pkg")))))
