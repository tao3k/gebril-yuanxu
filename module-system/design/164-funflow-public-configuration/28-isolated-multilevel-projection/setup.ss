;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(def assertions 0)
(def (check label condition)
  (unless condition (error "multilevel-control-failed" label))
  (set! assertions (+ assertions 1)))
(def (report label value)
  (write (list label value)) (newline) (force-output (current-output-port)))
(def cold-profile 0)
(def cold-module 0)
(def cold-pipeline 0)
(def cold-check 0)
(def pipeline-forces 0)
(def checks-forces 0)
(.def Scenario.)
(.def Profile.)
(.def Module.)
(.def Pipeline.)
(.def Check.)
(.def Bindings.)
(def Root
  (.o (:: @ [Scenario.])
    selected-profiles: '(ci)
    ci:
    (.o (:: @ [Profile.])
      selected-modules: '(funflow)
      funflow:
      (.o (:: effective-module [Module.])
        build: (.o (:: @ [Check.]) commands: '("gerbil" "build"))
        test: (.o (:: @ [Check.]) commands: '("gerbil" "test"))
        package: (.o (:: @ [Check.]) commands: '("gerbil" "package"))
        unused-check:
        (begin (set! cold-check (+ cold-check 1))
               (.o (:: @ [Check.]) commands: '("optional-check")))
        pipeline:
        (begin (set! pipeline-forces (+ pipeline-forces 1))
          (.o (:: @ [Pipeline.])
            selected-checks: '(build test package)
            checks:
            (begin (set! checks-forces (+ checks-forces 1))
              (map (lambda (name) (.ref effective-module name)) selected-checks))))
        unused-pipeline:
        (begin (set! cold-pipeline (+ cold-pipeline 1))
               (.get Root ci funflow pipeline)))
      unused-module:
      (begin (set! cold-module (+ cold-module 1)) (.get Root ci funflow)))
    unused-profile:
    (begin (set! cold-profile (+ cold-profile 1)) (.get Root ci))))
(def parent-pipeline (.get Root ci funflow pipeline))
(def parent-checks (.get parent-pipeline checks))
(check 'parent-cache-warm (and (= pipeline-forces 1) (= checks-forces 1)))

;; Business intent: retain upstream commands and append ONLY the new flag.
(.def (Release @ Root)
  ci: =>.+
  (.o funflow: =>.+
      (.o build: =>.+ (.o commands: => append '("--release"))
          smoke: (.o (:: @ [Check.]) commands: '("printf" "smoke"))
          pipeline: =>.+ (.o selected-checks: => append '(smoke)))))
;; Different intent: replace the command value, preserving the surrounding Check.
(.def (Replacement @ Root)
  ci: =>.+
  (.o funflow: =>.+ (.o build: =>.+ (.o commands: '("custom-builder")))))
(check 'user-declarations-still-lazy
  (and (= pipeline-forces 1) (= checks-forces 1)
       (= cold-profile 0) (= cold-module 0) (= cold-pipeline 0) (= cold-check 0)))

(def (empty-obligations candidate context) '())
(def (symbols? candidate)
  (and (list? candidate) (every symbol? candidate)
       (= (length candidate)
          (length (delete-duplicates/hash candidate table: (make-hash-table-eq))))))
(def (commands? candidate)
  (and (list? candidate) (pair? candidate) (every string? candidate)))
(def SymbolsContract (yuanxu-predicate-contract 'multi/symbols symbols? empty-obligations))
(def CommandsContract (yuanxu-predicate-contract 'multi/commands commands? empty-obligations))
(def (same-target candidate context)
  (if (eq? candidate (.get context target)) '() (list (.o kind: 'wrong-target))))
(def (pipeline-obligations candidate context)
  (let* ((owner (.get context parent target))
         (actual (.get candidate checks))
         (expected (map (lambda (name) (.ref owner name)) (.get candidate selected-checks))))
    (if (and (eq? candidate (.get context target))
             (= (length actual) (length expected)) (every eq? actual expected))
      '() (list (.o kind: 'stale-final-checks)))))
(def (check-obligations candidate context)
  (if (and (eq? candidate (.get context target))
           (not (member "forbidden" (.get candidate commands))))
    '() (list (.o kind: 'check-policy-refused))))
(def (native-contract contract-id family fields obligations-proc)
  (.cc YuanxuObjectContract.
    'identity contract-id 'proto family 'responsibilities fields '.obligations obligations-proc))
(def ScenarioShape
  (native-contract 'multi/scenario-shape Scenario.
    (.o selected-profiles: SymbolsContract) same-target))
(def ProfileShape
  (native-contract 'multi/profile-shape Profile.
    (.o selected-modules: SymbolsContract) same-target))
(def ModuleShape (native-contract 'multi/module-shape Module. (.o) same-target))
(def PipelineShape
  (native-contract 'multi/pipeline-shape Pipeline.
    (.o selected-checks: SymbolsContract) same-target))
(def CheckShape
  (native-contract 'multi/check-shape Check. (.o commands: CommandsContract) same-target))
(def BindingsContract (native-contract 'multi/bindings Bindings. (.o) empty-obligations))

;; The small functional builder is fixture-upstream code, not a public DSL.
(def (make-policy policy-id family shape-contract selector-slot fixed-policies default-policy scope-function obligations-proc)
  (let ((fixed-contracts
         (object<-alist
           (map (lambda (name) (cons name (.get (.ref fixed-policies name) template)))
                (.all-slots fixed-policies)))))
    (.o shape: shape-contract
        template: (native-contract policy-id family fixed-contracts obligations-proc)
        fixed: fixed-policies
        default: default-policy
        selector: selector-slot
        scope: scope-function)))
(def (own-scope candidate context) candidate)
(def (pipeline-scope candidate context) (.get context parent target))
(def CheckPolicy
  (make-policy 'multi/check Check. CheckShape #f (.o) #f own-scope check-obligations))
(def PipelinePolicy
  (make-policy 'multi/pipeline Pipeline. PipelineShape 'selected-checks
    (.o) CheckPolicy pipeline-scope pipeline-obligations))
(def ModulePolicy
  (make-policy 'multi/module Module. ModuleShape #f
    (.o pipeline: PipelinePolicy) #f own-scope same-target))
(def ProfilePolicy
  (make-policy 'multi/profile Profile. ProfileShape 'selected-modules
    (.o) ModulePolicy own-scope same-target))
(def ScenarioPolicy
  (make-policy 'multi/scenario Scenario. ScenarioShape 'selected-profiles
    (.o) ProfilePolicy own-scope same-target))
