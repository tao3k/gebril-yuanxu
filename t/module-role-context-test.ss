;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Public role identity and source admission through the runtime test entry.
(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :std/error Error? Error-message)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :clan/poo/object .o .get .call)
        (only-in :gerbil/expander make-module-context current-expander-context
                 current-expander-phi current-expander-compile current-expander-eval)
        (only-in :gerbil/runtime/loader load-path set-load-path! add-load-path!)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/reader module-publication-reader)
        (only-in :yuanxu/module-system/source/reader-evaluation reader-evaluation-observers)
        (only-in "qualification/module-publication/fixtures.ss"
                 with-publication-source PublicLibraryFixture write-file))
(export module-role-context-test)
(def (refusal thunk)
  (with-catch (lambda (failure) (and (Error? failure) (Error-message failure)))
    (lambda () (thunk) #f)))
(def (with-external-publication check)
  (def library (.call PublicLibraryFixture .acquire))
  (try
    (with-publication-source
      (lambda (root _module-root source view)
        (def reader (module-publication-reader))
        (.call reader read source)
        (.call reader admit-current)
        (check library root view reader))
      roles:
      (.o interface:
        `((import (only-in ,(.get library path) ExternalValue))
          (.def Fixture identity: 'custom/example
            core: (.o requires: (.o) scope-contract: FixtureContract
                      exports: (.o external: ExternalValue))
            features: (.o)))))
    (finally (.call PublicLibraryFixture .release library))))
(def module-role-context-test
  (test-suite "Runtime role contexts retain values and refuse changed source authority"
    (yuanxu-test-case "foreign reader contexts can outlive their wrapper directory"
      (def path (call-with-temporary-directory "foreign-role-"
                  (cut path-expand "interface.ss" <>)))
      (def context (make-module-context 'foreign/interface #f #f path))
      (def form '(foreign-body))
      (slot-set! context 'code form)
      (def completed (make-hash-table-eq))
      (parameterize ((current-expander-context context) (current-expander-phi 0)
                     (current-expander-compile identity) (current-expander-eval identity))
        (defvalues (compile evaluate) (reader-evaluation-observers (make-hash-table) completed))
        (check-equal? (eq? form (evaluate (compile form))) #t)
        (check-equal? (hash-length completed) 0)))
    (yuanxu-test-case "private and public imports retain one role value"
      (def package (gensym 'role-context-))
      (def library (string->symbol
        (string-append ":" (symbol->string package) "/modules/custom/example/objects")))
      (with-publication-source
        (lambda (root _module-root _source view)
          (def previous (load-path))
          (dynamic-wind
            (lambda () (add-load-path! root))
            (lambda ()
              (def scope (.get view modules custom example))
              (check-equal? (eq? (.get scope left) (.get scope right)) #t)
              (check-equal? (.get scope left retained) 'upstream))
            (lambda () (set-load-path! previous))))
        package: package
        roles:
        (.o config: `((import (only-in ,library FixtureScope))
                       (def Config #f) (def Greeting FixtureScope) (export Config Greeting))
            interface:
            '((.def Fixture identity: 'custom/example
                core: (.o requires: (.o) scope-contract: FixtureContract
                          exports: (.o left: FixtureScope right: Greeting))
                features: (.o))))))
    (yuanxu-test-case "new source epochs do not reuse stale role values"
      (with-publication-source
        (lambda (root module-root _source view)
          (def scope (.get view modules custom example))
          (check-equal? (.get scope greeting) "hello")
          (write-file (path-expand "config.ss" module-root)
            "(def Greeting \"changed\") (export Greeting)")
          (check-exception ((.get view admit-current)) error?)
          (def next (yuanxu-load-modules (path-expand "modules" root)))
          (check-equal? (.get next modules custom example greeting) "changed")
          (check-equal? (eq? scope (.get next modules custom example)) #f))))
    (yuanxu-test-case "refresh reuses unchanged standard role values and checks changed inputs"
      (with-publication-source
        (lambda (_root module-root _source first)
          (def parent (.get first modules custom example))
          (check-equal? (.get parent greeting) "hello")
          (def retained (.get parent role-value))
          (def second (.call first .refresh))
          (def unchanged (.get second modules custom example))
          (check-equal? (eq? retained (.get unchanged role-value)) #t)
          (write-file (path-expand "config.ss" module-root)
            "(def Greeting \"changed\") (export Greeting)")
          (check-exception ((.get second admit-current)) error?)
          (def third (.call second .refresh))
          (def changed (.get third modules custom example))
          (check-equal? (eq? retained (.get changed role-value)) #t)
          (check-equal? (.get changed greeting) "changed")
          (check-equal? (.get parent greeting) "hello")
          ((.get third admit-current)))
        roles:
        (.o interface:
          '((.def Fixture identity: 'custom/example
              core: (.o requires: (.o) scope-contract: FixtureContract
                        exports: (.o role-value: FixtureScope greeting: Greeting))
              features: (.o))))))
    (yuanxu-test-case "changed public name refuses before use and exact restoration admits"
      (with-external-publication
        (lambda (library _root view reader)
          (check-equal? (.get view modules custom example external) "original")
          (def previous (load-path))
          (def entered? #f)
          (try
            (set-load-path! (cons (.get library shadow) previous))
            (check-equal?
              (refusal (lambda () (.call reader admit-current) (set! entered? #t)))
              "public dependency source or runtime identity changed")
            (check-equal? entered? #f)
            (finally (set-load-path! previous)))
          (.call reader admit-current)
          (check-equal? (.get view modules custom example external) "original"))))
    (yuanxu-test-case "changed public source refuses even when its name is unchanged"
      (with-external-publication
        (lambda (library _root view reader)
          (check-equal? (.get view modules custom example external) "original")
          (def path (.get library path))
          (def original (call-with-input-file path read-line))
          (def entered? #f)
          (try
            (write-file path "(def ExternalValue \"changed\") (export ExternalValue)")
            (check-equal?
              (refusal (lambda () (.call reader admit-current) (set! entered? #t)))
              "public dependency source or runtime identity changed")
            (check-equal? entered? #f)
            (finally (write-file path original)))
          (.call reader admit-current))))))
