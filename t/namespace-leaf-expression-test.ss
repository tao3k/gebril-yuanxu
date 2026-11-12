;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Standard POO leaf expressions: receiver, slot continuation and lexical scope.
(import :std/test :clan/poo/object
        (only-in "./qualification/namespace/leaf-values.ss" Build Debug Explicit Inherited NamedSuper)
        (only-in :clan/poo/mop NoApplicableMethod?))
(export namespace-leaf-expression-test)
(def (command executable flags) (cons executable flags))
(def namespace-leaf-expression-test
  (test-suite "Leaf expression scope is standard POO scope"
    (test-case "documented user expressions use ordinary standard POO values"
      (check-equal? (.get Build argv) '("gerbil" "build"))
      (check-equal? (.get Debug argv) '("gerbil" "build" "--debug"))
      (check-equal? (.get Explicit argv) '("gxi" "build"))
      (check-equal? (eq? Explicit (.get Explicit receiver)) #t)
      (check-equal? (.get Inherited argv) (.get Debug argv))
      (check-equal? (.get NamedSuper argv) (.get Debug argv))
      (check-equal? (.get Build argv) '("gerbil" "build")))
    (test-case "inherited formulas see the final receiver after parent cache warming"
      (def computations 0)
      (def parent
        (.o self: profile executable: "gerbil" flags: '("build")
            argv: (begin (set! computations (1+ computations))
                         (command (.get profile executable) flags))
            unrelated: (error "unrelated leaf forced")))
      (def original (.get parent argv))
      (.def (Debug @ parent) (flags => append '("--debug")))
      (.def (Release @ parent) flags: => (cut append <> '("--release")))
      (check-equal? computations 1)
      (check-equal? (.slot? Debug 'quote) #f)
      (check-equal? (.get Debug argv) '("gerbil" "build" "--debug"))
      (check-equal? (.get Release argv) '("gerbil" "build" "--release"))
      (check-equal? computations 3)
      (check-equal? (eq? original (.get parent argv)) #t)
      (check-equal? (eq? (.get Debug argv) (.get Debug argv)) #t)
      (check-equal? computations 3)
      ;; A saved parent value is a deliberate replacement, not inheritance.
      (.def (Captured @ Debug) argv: original)
      (check-equal? (.get Captured flags) '("build" "--debug"))
      (check-equal? (.get Captured argv) '("gerbil" "build")))
    (test-case "sup is a named current-slot continuation, not a containing branch"
      (def parent (.o amount: 2 total: (* amount 3) other: 9))
      (check-equal? (.get parent total) 6)
      (def child
        (.o self: receiver super: inherited inherit: (list parent)
            amount: 5
            (total (sup) (+ (sup) (inherited)))
            other: (1+ (inherited))))
      (check-equal? (.get child total) 30)
      (check-equal? (.get child other) 10)
      (check-equal? (.get parent total) 6)
      (let (sup 'ordinary-lexical-value)
        (check-equal? (.get (.o value: sup) value) 'ordinary-lexical-value)))
    (test-case "replacement and conditional inheritance preserve lazy refusal"
      (def poison (.o flags: (error "discarded ancestor forced")))
      (def replacement (.o inherit: (list poison) flags: '("build")))
      (check-equal? (.get replacement flags) '("build"))
      (def fallback
        (.o self: receiver inherited?: #f
            (value (sup) (if (.get receiver inherited?) (sup) 7))))
      (check-equal? (.get fallback value) 7)
      (check-exception (.get (.cc fallback 'inherited? #t) value) NoApplicableMethod?))
    (test-case "nested lexical slots and function arguments keep their own scopes"
      (def parent
        (.o executable: "gxi" flags: '("outer")
            task: (.o self: task flags: '("--version")
                      argv: (command executable (.get task flags)))
            local: (.o executable: "local-tool" argv: (command executable '()))))
      (check-equal? (.get parent task argv) '("gxi" "--version"))
      (def child (.cc parent 'executable "gerbil" 'flags '("changed-outer")))
      (check-equal? (.get child task argv) '("gerbil" "--version"))
      (check-equal? (.get child local argv) '("local-tool"))
      (check-equal? (.get parent task argv) '("gxi" "--version")))
    (test-case "a containing namespace is an explicit value distinct from leaf self"
      (def directory (.o label: 'directory sibling: 'helper))
      (def (leaf parent)
        (.o self: receiver label: 'leaf
            own: (.get receiver label) containing: (.get parent label)))
      (def value (leaf directory))
      (def namespace (.o entry: value))
      (check-equal? (.get namespace entry own) 'leaf)
      (check-equal? (.get namespace entry containing) 'directory)
      (check-equal? (eq? value (.get namespace entry)) #t))))
