;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :yuanxu/object-syntax/path-slots
        (rename-in (only-in :yuanxu/object-syntax/path-slots .def) (.def define-path))
        (prefix-in (only-in :clan/poo/object .o .def) native-)
        (only-in :clan/poo/object .get .+ .slot?)
        (only-in :std/test test-suite test-case check-equal? check-exception)
        (only-in :gerbil/expander core-expand datum->syntax)
        (only-in :gerbil/runtime/gambit with-exception-catcher
                 call-with-output-string display-exception))
(export path-slots-test)

(def (path-error datum)
  (with-exception-catcher
    (lambda (error)
      (call-with-output-string
        (lambda (port)
          (parameterize ((current-output-port port))
            (display-exception error port)))))
    (lambda () (core-expand (datum->syntax (quote-syntax .o) datum)) #f)))

(def (values-of checks) (map (lambda (check) (.get check value)) checks))
(def (profile root) (.get root funflow profiles gerbil-scheme))
(def (pipeline root) (.get root funflow profiles gerbil-scheme pipeline))
(def (checks root) (.get root funflow profiles gerbil-scheme pipeline checks))

(def path-slots-test
  (test-suite "Native path-slot lowering"
    (test-case "direct leaves merge prefixes and preserve inherited intermediates lazily"
      (def demands 0)
      (.def Parent
        execution: (.o profile: (.o emit?: #f timeout: 60 retained: 'profile)
                       environment: (.o PATH: "/bin"))
        .acquire: (lambda () 'acquired)
        .release: (lambda (value) value)
        unrelated: (error "unrelated slot must stay lazy"))
      (def parent-profile (.get Parent execution profile))
      (.def (Child @ Parent)
        execution.profile.emit?: (begin (set! demands (+ demands 1)) #t)
        execution.environment.TMPDIR: "/tmp/tests"
        execution.profile.timeout: 30)
      (check-equal? demands 0)
      (check-equal? (.get Child execution profile timeout) 30)
      (check-equal? demands 0)
      (check-equal? (.get Child execution profile emit?) #t)
      (check-equal? (.get Child execution profile emit?) #t)
      (check-equal? demands 1)
      (check-equal? (.get Child execution profile retained) 'profile)
      (check-equal? (.get Child execution environment PATH) "/bin")
      (check-equal? (.get Child execution environment TMPDIR) "/tmp/tests")
      (check-equal? ((.get Child .acquire)) 'acquired)
      (check-equal? ((.get Child .release) 'released) 'released)
      (check-equal? (.get parent-profile emit?) #f)
      (check-equal? (.get parent-profile timeout) 60)
      (native-.def (Expanded @ Parent)
        execution: =>.+
        (native-.o profile: =>.+ (native-.o emit?: #t timeout: 30)
                   environment: =>.+ (native-.o TMPDIR: "/tmp/tests")))
      (check-equal? (.get Child execution profile timeout) (.get Expanded execution profile timeout))
      ;; Object-valued assignment replaces the leaf; refinement retains it.
      (.def (Replaced @ Parent) execution.profile: (.o emit?: #t))
      (check-equal? (.slot? (.get Replaced execution profile) 'retained) #f)
      (.def (Mixed @ Parent)
        execution.profile.emit?: #t
        execution.environment: =>.+ {TMPDIR: "/tmp/mixed"})
      (check-equal? (.get Mixed execution profile retained) 'profile)
      (check-equal? (.get Mixed execution environment PATH) "/bin")
      (.def Missing)
      (.def (Invalid @ Missing) execution.profile.emit?: #t)
      (check-exception (.get Invalid execution profile emit?) true))
    (test-case "four shared-prefix refinements retain final lexical slots after parent cache"
      (def pipeline-demands 0)
      (def checks-demands 0)
      (def unused-demands 0)
      (.def Profile
        build: (.o value: 'parent-build retained: 'build)
        test: (.o value: 'parent-test dependency: 'build)
        package: (.o value: 'parent-package dependency: 'test)
        pipeline:
        (begin
          (set! pipeline-demands (+ pipeline-demands 1))
          (.o pipeline-name: 'default
              checks:
              (begin
                (set! checks-demands (+ checks-demands 1))
                (list build test package)))))
      (.def Parent
        funflow:
        (.o profiles: (.o gerbil-scheme: Profile rust: 'untouched)
            unused: (begin (set! unused-demands (+ unused-demands 1)) 'unused)))
      (def parent-pipeline (pipeline Parent))
      (def parent-checks (checks Parent))
      (check-equal? (values-of parent-checks) '(parent-build parent-test parent-package))
      (.def (Child @ Parent)
        funflow.profiles.gerbil-scheme.build: =>.+ {value: 'child-build}
        funflow.profiles.gerbil-scheme.test: =>.+ {value: 'child-test}
        funflow.profiles.gerbil-scheme.package: =>.+ {value: 'child-package}
        funflow.profiles.gerbil-scheme.pipeline: =>.+ {pipeline-name: 'release})
      (check-equal? (list pipeline-demands checks-demands unused-demands) '(1 1 0))
      (def child-pipeline (pipeline Child))
      (check-equal? (list pipeline-demands checks-demands unused-demands) '(2 1 0))
      (def child-checks (checks Child))
      (check-equal? (.get child-pipeline pipeline-name) 'release)
      (check-equal? (values-of child-checks) '(child-build child-test child-package))
      (check-equal? (map eq? child-checks
                       (list (.get Child funflow profiles gerbil-scheme build)
                             (.get Child funflow profiles gerbil-scheme test)
                             (.get Child funflow profiles gerbil-scheme package)))
                    '(#t #t #t))
      (check-equal? (.get Child funflow profiles gerbil-scheme build retained) 'build)
      (check-equal? (.get Child funflow profiles rust) 'untouched)
      (check-equal? (.slot? Child 'funflow.profiles.gerbil-scheme.build) #f)
      (check-equal? (eq? child-pipeline (pipeline Child)) #t)
      (check-equal? (eq? child-checks (checks Child)) #t)
      (check-equal? (eq? parent-pipeline (pipeline Parent)) #t)
      (check-equal? (eq? parent-checks (checks Parent)) #t)
      (check-equal? (values-of (checks Parent)) '(parent-build parent-test parent-package))
      (.def (Sibling @ Parent)
        funflow.profiles.gerbil-scheme.build: =>.+ {value: 'sibling})
      (check-equal? (values-of (checks Sibling)) '(sibling parent-test parent-package))
      (check-equal? (values-of (checks Child)) '(child-build child-test child-package))
      ;; Negative control: a previously extracted list really does stay stale.
      (.def (Frozen @ Parent)
        funflow.profiles.gerbil-scheme.build: =>.+ {value: 'new}
        funflow.profiles.gerbil-scheme.pipeline: =>.+ {checks: parent-checks})
      (check-equal? (.get Frozen funflow profiles gerbil-scheme build value) 'new)
      (check-equal? (values-of (checks Frozen)) '(parent-build parent-test parent-package))
      (check-equal? unused-demands 0))

    (test-case "path and handwritten native expansion agree"
      (.def Parent a: (.o b: (.o left: (.o x: 0) right: (.o x: 0))))
      (.def (Short @ Parent) a.b.left: =>.+ {x: 1} a.b.right: =>.+ {x: 2})
      (native-.def (Long @ Parent)
        a: =>.+ (native-.o b: =>.+
                  (native-.o left: =>.+ (native-.o x: 1)
                             right: =>.+ (native-.o x: 2))))
      (check-equal? (list (.get Short a b left x) (.get Short a b right x))
                    (list (.get Long a b left x) (.get Long a b right x))))

    (test-case "relative brace paths, aliases and payload lexical hygiene"
      (let ((payload 42) (native-.o 'shadowed) (.+ 'shadowed))
        (.def Parent a: (.o b: (.o x: 0) c: (.o x: 0)))
        (.def (Child @ Parent)
          a: =>.+ {b: =>.+ {x: payload} c: =>.+ {x: (+ payload 1)}})
        (check-equal? (.get Child a b x) 42)
        (check-equal? (.get Child a c x) 43))
      (let ((payload 7))
        (.def Parent a: (.o b: (.o x: 0)))
        (.def (Child @ Parent) a: =>.+ {b: =>.+ {x: payload}})
        (define-path (Renamed @ Child) a.b: =>.+ {x: 10})
        (check-equal? (.get Renamed a b x) 10)
        (def object (.o (:: @ Child) a.b: =>.+ {x: (+ payload 1)}))
        (check-equal? (.get object a b x) 8)))

    (test-case "relative dotted paths inside a refinement brace"
      (.def Parent module: (.o profiles: (.o a: (.o build: (.o x: 0)
                                                          test: (.o x: 0)))))
      (.def (Child @ Parent)
        module: =>.+
        {profiles.a.build: =>.+ {x: 11}
         profiles.a.test: =>.+ {x: 12}})
      (check-equal? (.get Child module profiles a build x) 11)
      (check-equal? (.get Child module profiles a test x) 12))

    (test-case "interleaved root prefixes merge independently"
      (.def Parent a: (.o x: (.o n: 0) y: (.o n: 0))
                   b: (.o x: (.o n: 0)))
      (.def (Child @ Parent)
        a.x: =>.+ {n: 1} b.x: =>.+ {n: 2} a.y: =>.+ {n: 3})
      (check-equal? (list (.get Child a x n) (.get Child b x n) (.get Child a y n))
                    '(1 2 3)))

    (test-case "native default, tuple, shared slot and explicit header remain valid"
      (let ((shared 9))
        (.def Parent (x ? 1) x: 2 shared (tuple 3))
        (check-equal? (.get Parent x) 2)
        (check-equal? (.get Parent shared) 9)
        (check-equal? (.get Parent tuple) 3)
        (check-equal? (.get (.o () x: 5) x) 5)
        (check-equal? (.get (.o (:: @ Parent x) y: (+ x 1)) y) 3)))

    (test-case "only demanded target payloads evaluate"
      (def left-demands 0)
      (def right-demands 0)
      (.def Parent a: (.o left: (.o x: 0) right: (.o x: 0)))
      (.def (Child @ Parent)
        a.left: =>.+
        (begin (set! left-demands (+ left-demands 1)) (.o x: 1))
        a.right: =>.+
        (begin (set! right-demands (+ right-demands 1)) (.o x: 2)))
      (check-equal? (list left-demands right-demands) '(0 0))
      (check-equal? (.get Child a left x) 1)
      (check-equal? (list left-demands right-demands) '(1 0))
      (check-equal? (.get Child a left x) 1)
      (check-equal? (list left-demands right-demands) '(1 0))
      (check-equal? (.get Child a right x) 2)
      (check-equal? (list left-demands right-demands) '(1 1)))

    (test-case "object and brace match patterns delegate to native POO"
      (def value (.o x: 5))
      (check-equal? (match value ((.o x: n) n) (_ #f)) 5)
      (check-equal? (match value ({x: n} n) (_ #f)) 5))

    (test-case "literal dotted slots remain available through native binding"
      (native-.def Literal a.b: 10)
      (check-equal? (.get Literal a.b) 10)
      (check-equal? (.slot? Literal 'a) #f))

    (test-case "missing or non-object intermediates fail on demand"
      (.def Missing)
      (.def (Child @ Missing) a.b: =>.+ {x: 1})
      (check-exception (.get Child a b) true)
      (.def Scalar a: 1)
      (.def (Bad @ Scalar) a.b: =>.+ {x: 1})
      (check-exception (.get Bad a b) true))

    (test-case "duplicate paths, overlaps and invalid operators are rejected"
      ;; Expand using the authoring binding from this module.
      (for-each
        (lambda (entry)
          (let ((message
                 (path-error (car entry))))
            (check-equal? (and message (if (string-contains message (cdr entry)) #t #f)) #t)))
        '(((.o a.b: =>.+ {x: 1} a.b: =>.+ {x: 2}) . "duplicate path-slot")
          ((.o a: =>.+ {} a.b: =>.+ {}) . "overlapping ancestor")
          ((.o a.b: =>.+ {} a: =>.+ {}) . "overlapping ancestor")
          ((.o a.b: =>.+ {} a.b.c: =>.+ {}) . "overlapping ancestor")
          ((.o a.b.c: =>.+ {} a.b: =>.+ {}) . "overlapping ancestor")
          ((.o a.b: 1 a.b: 2) . "duplicate path-slot")
          ((.o a.b: 1 a.b.c: 2) . "overlapping ancestor")
          ((.o a.b: => identity) . "require native =>.+")
          ((.o a..b: =>.+ {}) . "empty path-slot segment")
          ((.o a.b: =>.+) . "missing value after path-slot operator"))))))
