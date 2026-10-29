;;; A product language is owned by its package, not by Core's namespace list.
(import :std/test
        (only-in :std/misc/ports read-all-as-string)
        (only-in :clan/poo/object .get)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/building/build-projection yuanxu-project-source-spec)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :gerbil/expander current-expander-context make-top-context
                 core-import-module expander-context-id)
        (only-in :yuanxu/module-system/building/source-package register-module-build-source! package-prelude-identity)
        (only-in :yuanxu/module-system/building/source-closure package-library-spec)
        (only-in :yuanxu/module-system/source/preparation build-target-name))
(export package-owned-prelude-test)
(def (write-datum file datum)
  (call-with-output-file file (lambda (port) (write datum port) (newline port))))
(def (with-product name proc)
  (call-with-temporary-directory "product-language-"
    (lambda (root)
      (def package (string->symbol (string-append "product-" name)))
      (def identity (string->symbol (string-append "example/" name "/prelude")))
      (write-datum (path-expand "gerbil.pkg" root)
        (list 'package: package 'prelude:
              (string->symbol (string-append ":" (symbol->string identity)))))
      (call-with-output-file (path-expand "prelude.ss" root)
        (lambda (port)
          (display "prelude: :gerbil/core\npackage: " port)
          (display (string-append "example/" name) port)
          (display "\n(import :gerbil/core)\n(export (import: :gerbil/core))\n" port)))
      (parameterize ((current-expander-context (make-top-context)))
        (proc root package identity)))))
(def package-owned-prelude-test
  (test-suite "Package-owned language registration"
    (test-case "product prelude retains native source and target identity"
      (with-product "owned"
        (lambda (root package identity)
          (register-module-build-source! root package prelude: identity)
          (check-equal? (package-prelude-identity root) identity)
          (check-equal? (build-target-name identity (symbol->string package) identity) "prelude")
          (write-datum (path-expand "consumer.ss" root) '(def value 42))
          (check-equal? (expander-context-id (core-import-module (path-expand "consumer.ss" root)))
                        'product-owned/consumer)
          (check-equal? (and (member "prelude" (package-library-spec root package '("consumer.ss"))) #t)
                        #t))))
    (test-case "native Module public-library projection publishes the owned language"
      (with-product "projection"
        (lambda (root package identity)
          (register-module-build-source! root package)
          (call-with-output-file (path-expand "init.ss" root)
            (lambda (port)
              (display "(import :yuanxu/module-system/selection/init-syntax)\n(yuanxu! source: \"./modules\" mode: explicit (example))\n" port)))
          (write-datum (path-expand "consumer.ss" root) '(def value 42))
          (def module-root (path-expand "modules/example" root))
          (create-directory* module-root)
          (for-each
            (lambda (row)
              (call-with-output-file (path-expand (car row) module-root)
                (lambda (port) (display (cdr row) port))))
            '(("objects.ss" . "(export)\n")
              ("config.ss" . "(export)\n")
              ("types.ss" . "(import :clan/poo/object (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract))\n(def Scope (yuanxu-predicate-contract 'test/scope object? (lambda (_v _c) '())))\n(export Scope)\n")
              ("build.ss" . "(import :clan/poo/object)\n(def Build (.o kind: 'module/build roots: '() library-roots: '(\"consumer\")))\n(export Build)\n")
              ("interface.ss" . "(.def Example identity: 'example features: (.o) core: (.o requires: (.o) scope-contract: Scope exports: (.o) projections: (list Build)))\n")))
          (def projection
            (yuanxu-project-source-spec (yuanxu-load-modules (path-expand "modules" root))
                                       '() root (path-expand "init.ss" root)))
          (check-equal? (and (memq identity (.get projection compiler-identities)) #t) #t)
          ;; Holding resolved naming metadata never approves changed sources.
          ;; The actual projected language remains part of compiler-current.
          (def path (path-expand "prelude.ss" root))
          (def text (call-with-input-file path read-all-as-string))
          (def (write-language value)
            (call-with-output-file (list path: path truncate: #t)
              (lambda (port) (display value port))))
          (dynamic-wind
            (lambda () (write-language (string-append text "\n")))
            (lambda () (check-exception ((.get projection admit-current)) error?))
            (lambda () (write-language text))))))
    (test-case "wrong expected prelude cannot alter package lookup"
      (with-product "mismatch"
        (lambda (root package identity)
          (def before (load-path))
          (check-exception
            (register-module-build-source! root package prelude: 'foreign/prelude) error?)
          (check-equal? (load-path) before))))
    (test-case "an unrelated namespace remains outside the package build"
      (with-product "foreign"
        (lambda (root package identity)
          (register-module-build-source! root package prelude: identity)
          (check-exception
            (build-target-name 'foreign/implementation (symbol->string package) identity) error?))))))
