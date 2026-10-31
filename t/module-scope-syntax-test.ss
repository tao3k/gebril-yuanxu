;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil/runtime/gambit with-exception-catcher
                 call-with-output-string display-exception)
        :yuanxu/profile-composition/selection-syntax
        :yuanxu/object-syntax/path-slots
        (rename-in (only-in :yuanxu/profile-composition/selection-syntax use-module)
                   (use-module with-module))
        (only-in :yuanxu/profile-composition/bindings yuanxu-module-scope)
        (only-in :yuanxu/profile-composition/profile-bundle
                 yuanxu-profile-export yuanxu-module-profiles)
        (only-in :yuanxu/module-system/objects
                 make-semantic-module ModuleAuthoringProfile. ModuleSourceRole.)
        (only-in :yuanxu/module-system/schema/relations yuanxu-semantic-identity)
        (only-in :yuanxu/module-system/source/objects make-yuanxu-module-package-source)
        (only-in :clan/poo/object .get .ref .+)
        (only-in :std/test test-suite test-case check-equal? check-exception)
        (only-in :gerbil/expander core-expand datum->syntax))
(export module-scope-syntax-test)

(def (expand-scope datum)
  (core-expand (datum->syntax (quote-syntax use-module) datum)))

(def module-scope-syntax-test
  (test-suite "Bounded native module scope"
    (test-case "the alias is the original scope and source identity is retained"
      (def source-handle (make-yuanxu-module-package-source "example/funflow@revision"))
      (.def funflow source: source-handle prototypes: (.o) profiles: (.o))
      (check-equal? (use-module funflow as ff (eq? ff funflow)) #t)
      (check-equal? (use-module funflow as ff (eq? (.get ff source) source-handle)) #t)
      (def derived (use-module funflow as ff (.+ ff (.o label: 'custom))))
      (check-equal? (eq? (.get derived source) source-handle) #t)
      (check-equal? (.get derived label) 'custom))

    (test-case "outer aliases survive and nested aliases shadow normally"
      (.def Scope label: 'outer-scope)
      (.def Other label: 'inner-scope)
      (let ((ff 'outside))
        (check-equal?
          (use-module Scope as ff
            (list (.get ff label)
                  (use-module Other as ff (.get ff label))
                  (.get ff label)))
          '(outer-scope inner-scope outer-scope))
        (check-equal? ff 'outside))
      (check-equal?
        (if (expand-scope '(let ((Scope (.o)))
                             (use-module Scope as local-alias (list local-alias)))) #t #f)
        #t)
      ;; No binding becomes available to a sibling expression.
      (check-exception
        (expand-scope '(let ((Scope (.o)))
                         (use-module Scope as unbound-alias (list unbound-alias))
                         unbound-alias))
        true))

    (test-case "closures retain the bounded scope and local names cannot capture helpers"
      (.def Scope label: 'retained)
      (let ((yuanxu-module-scope 'shadowed) (ff 'outside))
        (def thunk (with-module Scope as ff (lambda () (.get ff label))))
        (check-equal? (thunk) 'retained)
        (check-equal? ff 'outside)))

    (test-case "binding and result each evaluate once, without traversing the scope"
      (def scope-demands 0)
      (def body-demands 0)
      (def publication-demands 0)
      (.def Root
        source: (begin (set! publication-demands (+ publication-demands 1)) 'source)
        profiles: (error "unselected Profiles must remain lazy"))
      (let-syntax ((Scope (syntax-rules ()
                           ((_ . args) (error "unexpected application"))
                           (_ (begin (set! scope-demands (+ scope-demands 1)) Root)))))
        (check-equal? (use-module Scope as ff
                        (begin (set! body-demands (+ body-demands 1)) (eq? ff Root)))
                      #t))
      (check-equal? (list scope-demands body-demands publication-demands) '(1 1 0)))

    (test-case "upstream and downstream share prototypes and lazy Profile getters"
      (def source-handle (make-yuanxu-module-package-source "example/funflow@revision"))
      (def prototype-demands 0)
      (def profile-demands 0)
      (def unrelated-demands 0)
      (.def Check. value: 'default)
      (.def Pipeline. checks: '())
      ;; Fixture publications use native lazy slots. No Loader is involved.
      (.def Funflow
        source: source-handle
        prototypes:
        (.o check: (begin (set! prototype-demands (+ prototype-demands 1)) Check.)
            pipeline: Pipeline.)
        profiles:
        (.o gerbil-scheme:
            (begin
              (set! profile-demands (+ profile-demands 1))
              (use-module Funflow as ff
                (.o
                  build: (.o (:: @ (.get ff prototypes check)) value: 'build)
                  test: (.o (:: @ (.get ff prototypes check)) value: 'test)
                  package: (.o (:: @ (.get ff prototypes check)) value: 'package)
                  pipeline:
                  (.o (:: @ (.get ff prototypes pipeline))
                    pipeline-name: 'default
                    checks: (list build test package)))))
            rust: (begin (set! unrelated-demands (+ unrelated-demands 1)) 'rust)))
      (.def Project
        funflow: (use-module Funflow as ff (.o (:: @ ff))))
      (check-equal? (list prototype-demands profile-demands unrelated-demands) '(0 0 0))
      (check-equal? (eq? (.get Project funflow source) source-handle) #t)
      (check-equal? (list prototype-demands profile-demands unrelated-demands) '(0 0 0))
      (def parent-checks (.get Project funflow profiles gerbil-scheme pipeline checks))
      (check-equal? (map (lambda (c) (.get c value)) parent-checks) '(build test package))
      (check-equal? (list prototype-demands profile-demands unrelated-demands) '(1 1 0))
      (.def (Release @ Project)
        funflow.profiles.gerbil-scheme.build: =>.+ {value: 'release-build}
        funflow.profiles.gerbil-scheme.test: =>.+ {value: 'release-test}
        funflow.profiles.gerbil-scheme.package: =>.+ {value: 'release-package}
        funflow.profiles.gerbil-scheme.pipeline: =>.+ {pipeline-name: 'release})
      (def final-checks (.get Release funflow profiles gerbil-scheme pipeline checks))
      (check-equal? (map (lambda (c) (.get c value)) final-checks)
                    '(release-build release-test release-package))
      (check-equal? (.get Release funflow profiles gerbil-scheme pipeline pipeline-name)
                    'release)
      (check-equal? (eq? (.get Release funflow source) source-handle) #t)
      (check-equal? (eq? final-checks
                        (.get Release funflow profiles gerbil-scheme pipeline checks)) #t)
      (check-equal? (map (lambda (c) (.get c value)) parent-checks) '(build test package))
      (check-equal?
        (use-module Funflow as ff (eq? (.get ff prototypes check) Check.)) #t)
      (check-equal? unrelated-demands 0))

    (test-case "unbound and malformed declarations fail without guessing a source"
      (for-each
        (lambda (datum) (check-exception (expand-scope datum) true))
        '((use-module MissingModule as ff (list ff))
          (let ((Scope (.o))) (use-module Scope as ff))
          (let ((Scope (.o))) (use-module Scope as ff 42))
          (use-module Scope as ff (.o) (.o))
          (use-module Scope as 42 (.o))
          (use-module Scope as ff (.o . malformed)))))

    (test-case "non-object source fails before executing the body"
      (def ran? #f)
      (let ((NotScope 42))
        (check-exception (use-module NotScope as ff (set! ran? #t)) true))
      (check-equal? ran? #f))

    (test-case "direct slot/source collisions are actionable declaration errors"
      (for-each
        (lambda (form)
          (def message
            (with-exception-catcher
              (lambda (error)
                (call-with-output-string
                  (lambda (port) (display-exception error port))))
              (lambda () (expand-scope form) "unexpected success")))
          (check-equal? (if (string-contains message "conflicts with lexical slot") #t #f) #t))
        '((.o funflow: (use-module funflow as ff (.o (:: @ ff))))
          (.o funflow: (with-module funflow as ff (.o (:: @ ff))))
          (.o providers.funflow: (use-module funflow as ff (.o (:: @ ff))))
          (.o providers.funflow: (with-module funflow as ff (.o (:: @ ff)))))))

    (test-case "identifier-only selections preserve the existing Bundle grammar"
      (.def (Role @ ModuleSourceRole.)
        identity: 'test recommended-forms: '() forbidden-slot-verbs: '()
        forbidden-root-forms: '() recursive-root-forms?: #f forbidden-imports: '()
        forbidden-forms: '() forbid-raw-behavior-hooks?: #f
        forbid-raw-query-initializers?: #f repair-operators: '() freedom: 'open)
      (.def (Authoring @ ModuleAuthoringProfile.)
        executor: (.o) types: Role objects: Role funs: Role config: Role interface: Role)
      (def Module
        (make-semantic-module
          (yuanxu-semantic-identity 'test 'funflow) Authoring
          profiles: (yuanxu-module-profiles
                      (yuanxu-profile-export 'build (.o identity: 'build)))))
      (check-equal? (.get (use-module Module as named build) profile-identities) '(build))
      (check-equal? (.get (use-module Module build) profile-identities) '(build)))))
