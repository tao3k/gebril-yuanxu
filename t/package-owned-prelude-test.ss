;;; A product language is owned by its package, not by Core's namespace list.
(import :std/test
        (only-in :std/misc/ports read-all-as-string)
        (only-in :clan/poo/object .get)
        (only-in :tao3k/yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :tao3k/yuanxu/module-system/building/build-projection yuanxu-project-source-spec)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :gerbil/expander current-expander-context make-top-context
                 core-import-module expander-context-id)
        (only-in :tao3k/yuanxu/module-system/building/source-package register-module-build-source! package-prelude-identity)
        (only-in :tao3k/yuanxu/module-system/building/source-closure package-library-spec)
        (only-in :tao3k/yuanxu/module-system/source/preparation build-target-name))
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
        (def previous (load-path))
        (dynamic-wind
          void
          (lambda () (proc root package identity))
          (lambda () (set-load-path! previous)))))))
(def package-owned-prelude-test
  (test-suite "Package-owned language registration"
    (test-case "product prelude retains standard source and target identity"
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
    (test-case "standard Module public-library projection publishes the owned language"
      (with-product "projection"
        (lambda (root package identity)
          (register-module-build-source! root package)
          (call-with-output-file (path-expand "init.ss" root)
            (lambda (port)
              (display "(import :tao3k/yuanxu/module-system/selection/init-syntax)\n(yuanxu! :test-dir \"./t\" source: \"./modules\" mode: explicit (example))\n" port)))
          (write-datum (path-expand "consumer.ss" root) '(def value 42))
          (def module-root (path-expand "modules/example" root))
          (create-directory* module-root)
          (for-each
            (lambda (row)
              (call-with-output-file (path-expand (car row) module-root)
                (lambda (port) (display (cdr row) port))))
            '(("objects.ss" . "(export)\n")
              ("config.ss" . "(export)\n")
              ("types.ss" . "(import :clan/poo/object (only-in :clan/poo/type Record))\n(def Scope (.cc (Record) identity: 'test/scope))\n(export Scope)\n")
              ("build.ss" . "(import :clan/poo/object)\n(.def Build defbuild-script: (.o spec: '(\"facade\")))\n(export Build)\n")
              ("facade.ss" . "(import \"../../consumer.ss\") (export)\n")
              ("interface.ss" . "(.def Example identity: 'example features: (.o) core: (.o scope-contract: Scope exports: (.o)))\n")))
          (def projection
            (yuanxu-project-source-spec (yuanxu-load-modules (path-expand "modules" root))
                                       '() root (path-expand "init.ss" root)))
          (check-equal? (and (memq identity (.get projection compiler-identities)) #t) #t)
          (def targets (map (lambda (target) (if (string? target) target (cadr target)))
                               (.get projection spec)))
          (check-equal? (and (member "prelude" targets) #t) #t)
          (for-each (lambda (target)
                      (check-equal? (file-exists? (path-expand (string-append target ".ss") root)) #t))
                    targets)
          ;; An executable has its own source; STD Make rejects a second
          ;; target for the same source even when it would name another product.
          (call-with-output-file (path-expand "run.ss" root)
            (lambda (port) (display "(def (main . args) (void)) (export main)\n" port)))
          (def program-view (yuanxu-load-modules (path-expand "modules" root)))
          (def build-target '(exe: "run" bin: "consumer-program"))
          (def program-projection
            (yuanxu-project-source-spec program-view (list build-target)
              root (path-expand "init.ss" root)))
          (def build-name (string-append (symbol->string package) "/run"))
          (check-equal?
            (filter (lambda (target) (and (pair? target) (eq? (car target) exe:)))
              (.get program-projection spec))
            '((exe: "run" bin: "consumer-program")))
          (check-equal?
            (length (filter (cut eq? <> (string->symbol build-name))
                            (.get program-projection compiler-identities))) 1)
          ((.get program-projection admit-current))
          (def default-bin
            (yuanxu-project-source-spec program-view '((exe: "run"))
              root (path-expand "init.ss" root)))
          (check-equal?
            (filter (lambda (target) (and (pair? target) (eq? (car target) exe:)))
              (.get default-bin spec))
            '((exe: "run")))
          (check-exception
            (yuanxu-project-source-spec program-view
              '((exe: "run" bin: "../escape")) root (path-expand "init.ss" root)) error?)
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
