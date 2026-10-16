;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :std/make make)
        (only-in :gerbil/expander eval-syntax current-expander-context make-top-context syntax->list)
        (only-in :clan/poo/object .o .+ .ref .get object?)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :core/types poo-flow-predicate-contract)
        (only-in :core/feature-system/model feature-descriptor)
        (only-in :core/feature-system/capability-model feature-projection-request)
        (only-in :core/module-system/source/objects poo-flow-module-source-ref-metadata)
        (only-in :core/module-system/source/admission module-source-type module-source-read)
        (only-in :core/module-system/interface poo-flow-load-modules)
        (only-in :core/modules/building/build-projection poo-flow-core-write-build-entry poo-flow-core-admit-build-inputs))
(export module-build-graph-test)
(def Scope (poo-flow-predicate-contract 'test/build-scope object? (lambda (_v _c) '())))
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
                   "(poo-flow! :app (web +late +early -off) :unused (bomb disable: #t))")
       (for-each
        (lambda (id)
          (let (directory (path-expand (string-append "modules/" id) root))
            (write-file (path-expand "types.ss" directory)
             "(import (only-in :clan/poo/object object?) (only-in :core/types poo-flow-predicate-contract)) (def Scope (poo-flow-predicate-contract 'fixture object? (lambda (_v _c) '()))) (export Scope)")
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
  (poo-flow-load-modules (path-expand "init.ss" root)
   read-publication:
   (lambda (source)
     (let (id (cdr (assq 'module-id (poo-flow-module-source-ref-metadata source))))
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
(def (script-main file)
  ;; Test-only native expansion of the generated build script; no Module Loader.
  (parameterize ((current-expander-context (make-top-context)))
    (for-each eval-syntax (syntax->list (read-syntax-from-file file)))
    (eval-syntax 'main)))
(def (native-binding file name)
  (parameterize ((current-expander-context (make-top-context)))
    (eval-syntax `(import ,file))
    (eval-syntax name)))
(def module-build-graph-test
  (test-suite "Selected Core and Feature compiler input Graph"
    (poo-flow-test-case "roles derive once, Core dependency precedes consumer, optional order follows Graph"
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
    (poo-flow-test-case "a different selected generation cannot reuse the parent's preparations"
      (with-source
       (lambda (root _prefix)
         (let* ((v (fixture-view root)) (parent (.get v build-graph))
                (other (.+ v (.o selected-graph: (.+ (.get v selected-graph) (.o generation: "other"))))))
           (check-equal? (length (.get parent entries)) 10)
           (check-exception (.get other build-graph) error?)))))
    (poo-flow-test-case "optional func role becomes a root without a second inventory"
      (with-source
       (lambda (root prefix)
         (write-file (path-expand "modules/app/web/func.ss" root) "(def (identity-value x) x) (export identity-value)")
         (let (names (entry-names (.get (fixture-view root) build-graph)))
           (check-equal? (length names) 11)
           (check-equal? (and (memq (string->symbol (string-append prefix "/modules/app/web/func")) names) #t) #t)))))
    (poo-flow-test-case "additional Core and Feature contributions use one ordered projection"
      (with-source
       (lambda (root _prefix)
         (let (graph (.get (fixture-view root #f (list (build-contribution "extra/core"))) build-graph))
           (check-equal? (length (.get graph entries)) 12)))))
    (poo-flow-test-case "identical contributions deduplicate and differing options conflict"
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
    (poo-flow-test-case "foreign requests are retained; unknown and unresolved build projections reject"
      (with-source
       (lambda (root _prefix)
         (let (graph (.get (fixture-view root #f (list (feature-projection-request 'r 'runtime 'v1))) build-graph))
           (check-equal? (length (.get graph other-projections)) 2))
         (for-each
          (lambda (projection)
            (check-exception (.get (fixture-view root #f (list projection)) build-graph) error?))
          (list 'bad (.o kind: 'module/build roots: '(42)) (feature-projection-request 'r 'build 'v1))))))
    (poo-flow-test-case "owner-relative paths cannot escape or traverse symlinks"
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
    (poo-flow-test-case "native build script and make compile only the selected artifact tree"
      (with-source
       (lambda (root prefix)
         (let* ((v (fixture-view root))
                (out (path-expand "artifact" root))
                (artifact (poo-flow-core-write-build-entry v out))
                (spec (.get artifact spec))
                (lib (path-expand "lib" root)))
           (check-equal? (length spec) 10)
           (check-equal? (.get (poo-flow-core-write-build-entry v out) spec) spec)
           (check-equal? (module-source-type (path-expand "build.ss" out)) 'regular)
           (check-equal? (module-source-type (path-expand (string-append prefix "/modules/unused/bomb/interface.ss") out)) #f)
           (check-equal? (module-source-type (path-expand (string-append prefix "/modules/app/web/extra/off.ss") out)) #f)
           (let* ((main (script-main (.get artifact build-entry)))
                  (output (call-with-output-string
                           (lambda (port) (parameterize ((current-output-port port)) (main "spec"))))))
             (check-equal? (call-with-input-string output read) spec))
           (check-equal?
            (native-binding (path-expand (string-append prefix "/modules/app/web/config.ss") out) 'Origin)
            (path-normalize (path-expand "modules/app/web/config.ss" root)))
           ;; Native executor only; no new scheduler, Module runtime Loader or full build.
           (make spec srcdir: out libdir: lib bindir: (path-expand "bin" root)
                 parallelize: 1 optimize: #f debug: #t)
           (for-each
            (lambda (entry)
              (check-equal? (module-source-type
                            (path-expand (string-append (cadr entry) ".ssi") lib)) 'regular)) spec)
           (let (output
                 (call-with-output-string
                  (lambda (port)
                    (parameterize ((current-output-port port))
                      (make spec srcdir: out libdir: lib bindir: (path-expand "bin" root)
                            parallelize: 1 optimize: #f debug: #t)))))
             (when (string-contains output "... compile") (display output))
             (check-equal? (and (string-contains output "... compile") #t) #f))
           (write-file (path-expand "init.ss" root) ";; selection changed")
           (check-exception ((script-main (.get artifact build-entry)) "spec") error?)))))
    (poo-flow-test-case "destination tampering and unowned directories refuse before overwriting"
      (with-source
       (lambda (root _prefix)
         (let* ((v (fixture-view root)) (out (path-expand "artifact" root))
                (artifact (poo-flow-core-write-build-entry v out))
                (script (module-source-read (.get artifact build-entry)))
                (target (path-expand (string-append (cadar (.get artifact spec)) ".ss") out)))
           (write-file target ";; foreign content")
           (check-exception (poo-flow-core-write-build-entry v out) error?)
           (check-exception ((.get artifact admit-current)) error?)
           (check-exception ((script-main (.get artifact build-entry)) "spec") error?)
           (check-equal? (module-source-read target) ";; foreign content")
           (check-equal? (module-source-read (.get artifact build-entry)) script))
         (let (out (path-expand "unowned" root))
           (write-file (path-expand "foreign.ss" out) ";; foreign input")
           (check-exception (poo-flow-core-write-build-entry (fixture-view root) out) error?)
           (check-equal? (module-source-type (path-expand "build.ss" out)) #f)))))
    (poo-flow-test-case "stale init, role and contribution inputs refuse materialization"
      (for-each
       (lambda (file)
         (with-source
          (lambda (root _prefix)
            (let* ((v (fixture-view root)) (graph (.get v build-graph)) (out (path-expand "stale" root)))
              (write-file (path-expand file root) ";; changed")
              (check-exception ((.get graph admit-current)) error?)
              (check-exception (poo-flow-core-admit-build-inputs (.get graph source-inputs)) error?)
              (check-exception (poo-flow-core-write-build-entry v out) error?)
              (check-equal? (module-source-type (path-expand "build.ss" out)) #f)))))
       '("init.ss" "modules/app/web/config.ss" "modules/app/web/extra/late.ss" "modules/app/web/func.ss" "modules/app/web/extra/gerbil.pkg")))))
