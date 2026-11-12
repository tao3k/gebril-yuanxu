(import :std/test :clan/poo/object
        (only-in :clan/poo/mop Type. validate)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :tao3k/yuanxu/module-system/building/source-closure package-library-spec))
(export requires-scope-probe-test)

;; The role wrapper and edge resolution are an isolated design fixture.
(def (require-edge declarations alias)
  (unless (.slot? declarations alias)
    (error "undeclared dependency" alias))
  (.ref declarations alias))

(def (resolve-owner owner declarations active)
  (when (memq owner active)
    (error "dependency cycle" (reverse (cons owner active))))
  (for-each (lambda (dependency)
              (resolve-owner dependency declarations (cons owner active)))
            (require-edge declarations owner)))

(def requires-scope-probe-test
  (test-suite "Scoped requires prototype"
    (test-case "the published edge and the local binding use the same final receiver"
      (def checks '())
      (def Scope
        (.cc Type. identity: 'json-schema/scope
          .element?: (lambda (value)
                       (set! checks (cons 'publisher checks))
                       (string? (.get value defaults schema)))))
      (def Provider
        (.cc Type. identity: 'opentofu/schema-requirement
          .element?: (lambda (value)
                       (set! checks (cons 'consumer checks))
                       (string-prefix? "provider-" (.get value defaults schema)))))
      (def base-compiles 0)
      (def baseline
        (.o (:: @)
          defaults: (.o schema: "baseline")
          compile: (begin
                     (set! base-compiles (+ base-compiles 1))
                     (let (effective @)
                       (lambda () (.get effective defaults schema))))))
      (def (derive upstream schema)
        (validate Provider
          (validate Scope
            (.o (:: @ upstream)
              defaults: => (lambda (inherited) (.cc inherited schema: schema))))))
      (def selected (.o json-schema: baseline))
      (def (bind-requirements declarations)
        (def declared (require-edge declarations 'JsonSchema))
        (.o JsonSchema:
            (derive (.ref selected (.get declared module-id)) (.get declared schema))))
      (def declaration (.o JsonSchema: (.o module-id: 'json-schema schema: "provider-v1")))
      (def edges (bind-requirements declaration))
      (def OpenTofuInterface (.o requires: edges))
      (def Review (.o (:: @)
                    interface: OpenTofuInterface
                    schema: (.get @ interface requires JsonSchema)))
      (def parent-compile (.get baseline compile))
      (check-equal? (parent-compile) "baseline")
      (def first (require-edge edges 'JsonSchema))
      (check-equal? (eq? first (.get Review schema)) #t)
      (check-equal? ((.get first compile)) "provider-v1")
      (check-equal? (reverse checks) '(publisher consumer))
      (set! checks '())
      (check-exception (derive baseline #f) error?)
      (check-equal? (reverse checks) '(publisher))
      (set! checks '())
      (check-exception (derive baseline "wrong") error?)
      (check-equal? (reverse checks) '(publisher consumer))
      (set! checks '())
      (def next-declaration (.cc declaration JsonSchema:
                                 (.cc (.get declaration JsonSchema) schema: "provider-v2")))
      (def next-edges (bind-requirements next-declaration))
      (def next-interface (.cc OpenTofuInterface requires: next-edges))
      (def next-review (.cc Review interface: next-interface))
      (def second (.get next-review schema))
      (check-equal? (eq? second first) #f)
      (check-equal? (eq? second (require-edge next-edges 'JsonSchema)) #t)
      (check-equal? (eq? first (.get Review schema)) #t)
      (check-equal? ((.get second compile)) "provider-v2")
      (check-equal? (reverse checks) '(publisher consumer))
      (check-equal? (eq? parent-compile (.get baseline compile)) #t)
      (check-equal? (parent-compile) "baseline")
      (check-equal? base-compiles 3)
      (check-exception (require-edge edges 'Unlisted) error?)
      (resolve-owner 'review (.o review: '(opentofu) opentofu: '(schema) schema: '()) '())
      (check-exception
        (resolve-owner 'review (.o review: '(opentofu) opentofu: '(review)) '()) error?))
    (test-case "standard import collection sees one compiler target for shared JsonSchema"
      (call-with-temporary-directory "requires-scope-targets"
        (lambda (root)
          (def (write-source name text)
            (call-with-output-file (path-expand name root) (lambda (out) (display text out))))
          (write-source "gerbil.pkg" "(package: requires-scope-fixture)\n")
          (write-source "json-schema.ss" "(export schema) (def schema #t)\n")
          (write-source "opentofu.ss" "(import \"json-schema.ss\") (export tofu) (def tofu schema)\n")
          (write-source "review.ss" "(import \"opentofu.ss\" \"json-schema.ss\") (export review) (def review tofu)\n")
          (check-equal?
            (package-library-spec root 'requires-scope-fixture
              '("json-schema.ss" "opentofu.ss" "review.ss"))
            '("json-schema" "opentofu" "review")))))))
