;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :yuanxu/composition/roles
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
         :std/test
        :clan/poo/object
        :yuanxu/object-family/role-syntax
        :yuanxu/feature-system/domain-case/interface
        :yuanxu/feature-system/domain-case/syntax)


(import "./domain-case-test-support")

(def domain-case-test
  (test-suite "POO CaseComponent and DomainCase closure"
    (yuanxu-test-case "object, type, and contract close into one cached DomainCase"
      (let* ((cache (yuanxu-domain-case-cache))
             (cold (close-base cache))
             (warm (close-base cache))
             (left-receipt
              (yuanxu-domain-case-instantiate
               (.ref cold 'domain-case) (agent-role 'agent-1 "revision-1")))
             (right-receipt
              (yuanxu-domain-case-instantiate
               (.ref cold 'domain-case) (agent-role 'agent-2 "revision-2")))
             (left (.ref left-receipt 'instance))
             (right (.ref right-receipt 'instance)))
        (check (.ref cold 'accepted?) => #t)
        (check (.ref cold 'cache-hit?) => #f)
        (check (.ref warm 'accepted?) => #t)
        (check (.ref warm 'cache-hit?) => #t)
        (check (eq? (.ref cold 'domain-case) (.ref warm 'domain-case)) => #t)
        (check (eq? (.ref (.ref cold 'domain-case) 'shared-prototype)
                    (.ref (.ref warm 'domain-case) 'shared-prototype)) => #t)
        (check (yuanxu-domain-case-cache-closure-count cache) => 1)
        (check (yuanxu-domain-case-cache-hit-count cache) => 1)
        (check (yuanxu-domain-case-instance-mix-count
                (.ref cold 'domain-case))
               => 0)
        (check (yuanxu-domain-case-instance-overlay-count
                (.ref cold 'domain-case))
               => 2)
        (check (.ref left-receipt 'accepted?) => #t)
        (check (.ref right-receipt 'accepted?) => #t)
        (check (.ref left 'agent-id) => 'agent-1)
        (check (.ref right 'agent-id) => 'agent-2)
        (check (.ref left 'source-revision) => "revision-1")
        (check (.ref right 'source-revision) => "revision-2")
        (check (eq? (.ref left 'domain-case/ref) (.ref cold 'domain-case))
               => #t)
        (check (.ref left 'domain-case/instance-overlay-kind)
               => 'yuanxu.role-instance-overlay.v1)
        (check (.ref left 'domain-case/instance-composition-kind)
               => 'yuanxu.role-instance-overlay.v1)
        (check (.ref left 'domain-case/instance-overlay-resolver-depth) => 1)
        (check (.ref left 'qualification/versioned?) => #t)
        (check (.ref left 'qualification/revision-bound?) => #t)))

    (yuanxu-test-case "instance overlay preserves marker, local, and shared precedence"
      (let* ((case-value
              (.ref (close-base (yuanxu-domain-case-cache)) 'domain-case))
             (local-role
              (poo-core-role-object
               (slots ((agent-id 'overlay-agent)
                       (schema-id 'agent.case.v1)
                       (schema-version 1)
                       (source-revision "overlay-revision")
                       (qualification/versioned? 'local-override)
                       (domain-case/ref #f)
                       (domain-case/key 'spoofed-key)))
               (supers)))
             (receipt
              (yuanxu-domain-case-instantiate case-value local-role))
             (instance (.ref receipt 'instance)))
        (check (.ref receipt 'accepted?) => #t)
        (check (.ref instance 'qualification/versioned?) => 'local-override)
        (check (.ref instance 'qualification/revision-bound?) => #t)
        (check (eq? (.ref instance 'domain-case/ref) case-value) => #t)
        (check (.ref instance 'domain-case/key) => (.ref case-value 'key))
        (check (yuanxu-domain-case-instance-mix-count case-value) => 0)
        (check (yuanxu-domain-case-instance-overlay-count case-value) => 1)))

    (yuanxu-test-case "computed POO slots retain native mix semantics"
      (let* ((case-value
              (.ref (close-base (yuanxu-domain-case-cache)) 'domain-case))
             (computed-local-role
              (.o (agent-id 'computed-agent)
                  (schema-id 'agent.case.v1)
                  (schema-version 1)
                  (source-revision "computed-revision")))
             (receipt
              (yuanxu-domain-case-instantiate
               case-value computed-local-role))
             (instance (.ref receipt 'instance)))
        (check (.ref receipt 'accepted?) => #t)
        (check (.ref instance 'agent-id) => 'computed-agent)
        (check (.ref instance 'qualification/versioned?) => #t)
        (check (.ref instance 'domain-case/instance-overlay-kind) => #f)
        (check (.ref instance 'domain-case/instance-composition-kind)
               => 'yuanxu.role-compose-mix.v1)
        (check (.ref instance 'domain-case/instance-overlay-resolver-depth)
               => #f)
        (check (yuanxu-domain-case-instance-mix-count case-value) => 1)
        (check (yuanxu-domain-case-instance-overlay-count case-value) => 0)))

    (yuanxu-test-case "canonical key is deterministic and excludes procedures"
      (let* ((left
              (yuanxu-domain-case-canonical-descriptor
               'agent.case.v1 1
               (list versioned-component revision-component) '() '(runtime)))
             (right
              (yuanxu-domain-case-canonical-descriptor
               'agent.case.v1 1
               (list versioned-component revision-component) '() '(runtime)))
             (reversed
              (yuanxu-domain-case-canonical-descriptor
               'agent.case.v1 1
               (list revision-component versioned-component) '() '(runtime)))
             (left-key (yuanxu-domain-case-canonical-key left))
             (right-key (yuanxu-domain-case-canonical-key right))
             (reversed-key (yuanxu-domain-case-canonical-key reversed)))
        (check left => right)
        (check left-key => right-key)
        (check (equal? left-key reversed-key) => #f)
        (check
         (yuanxu-domain-case-canonical-descriptor
          'agent.case.v1 1 (list versioned-component revision-component)
          '() '(runtime audit))
         =>
         (yuanxu-domain-case-canonical-descriptor
          'agent.case.v1 1 (list versioned-component revision-component)
          '() '(audit runtime)))
        (check (string-contains
                (call-with-output-string (lambda (port) (write left port)))
                "procedure")
               => #f)))

    (yuanxu-test-case "same canonical identity cannot alias different component objects"
      (let* ((cache (yuanxu-domain-case-cache))
             (cold (close-base cache))
             (versioned-clone
              (yuanxu-case-component
               'versioned 1 versioned-role versioned-type
               (list schema-id-slot schema-version-slot)
               (list versioned-contract)
               (list runtime-projection)))
             (alias
              (yuanxu-domain-case-close
               cache 'agent.case.v1 1
               (list versioned-clone revision-component) '() '(runtime))))
        (check (.ref cold 'accepted?) => #t)
        (check (.ref alias 'accepted?) => #f)
        (check (diagnostic-codes alias) => '(module-owner-identity-alias))
        (check (yuanxu-domain-case-cache-closure-count cache) => 1)))

    (yuanxu-test-case "duplicate, parent, and projection declarations fail closure"
      (let* ((cache (yuanxu-domain-case-cache))
             (missing-parent
              (yuanxu-case-component
               'child 1 policy-role policy-type '() '() '()
               '(not-declared)))
             (duplicate
              (yuanxu-domain-case-close
               cache 'duplicate.case.v1 1
               (list versioned-component versioned-component)))
             (parent
              (yuanxu-domain-case-close
               cache 'parent.case.v1 1 (list missing-parent)))
             (projection
              (yuanxu-domain-case-close
               cache 'projection-selection.case.v1 1
               (list versioned-component) '() '(runtime runtime))))
        (check (diagnostic-codes duplicate)
               => '(duplicate-component-id projection-name-conflict))
        (check (diagnostic-codes parent)
               => '(missing-or-forward-parent-component))
        (check (diagnostic-codes projection)
               => '(duplicate-projection-selection))
        (check (yuanxu-domain-case-cache-closure-count cache) => 0)))

    (yuanxu-test-case "type identity and parent membership close before composition"
      (let* ((cache (yuanxu-domain-case-cache))
             (parent-role
              (poo-core-role-object (slots ((mode 'parent))) (supers)))
             (child-role
              (poo-core-role-object (slots ((mode 'child))) (supers)))
             (parent-type
              (yuanxu-case-type-contract 'ParentMode '() (lambda (_) #t)))
             (child-type
              (yuanxu-case-type-contract
               'ChildMode '(ParentMode) (lambda (_) #t)))
             (parent-component
              (yuanxu-case-component
               'parent-mode 1 parent-role parent-type '() '() '()))
             (child-component
              (yuanxu-case-component
               'child-mode 1 child-role child-type '() '() '()
               '(parent-mode)))
             (closed
              (yuanxu-domain-case-close
               cache 'precedence.case.v1 1
               (list parent-component child-component)))
             (local-role
              (poo-core-role-object (slots ((instance/local? #t))) (supers)))
             (instance
              (.ref (yuanxu-domain-case-instantiate
                     (.ref closed 'domain-case) local-role)
                    'instance))
             (missing-type-component
              (yuanxu-case-component
               'missing-type 1 policy-role
               (yuanxu-case-type-contract
                'MissingTypeChild '(NotDeclared) (lambda (_) #t))
               '() '() '()))
             (missing-type
              (yuanxu-domain-case-close
               cache 'missing-type.case.v1 1
               (list missing-type-component)))
             (conflicting-type-component
              (yuanxu-case-component
               'conflicting-type 1 policy-role
               (yuanxu-case-type-contract
                'ParentMode '() (lambda (_) #t))
               '() '() '()))
             (conflicting-type
              (yuanxu-domain-case-close
               cache 'conflicting-type.case.v1 1
               (list parent-component conflicting-type-component))))
        (check (.ref closed 'accepted?) => #t)
        (check (.ref instance 'mode) => 'child)
        (check (diagnostic-codes missing-type)
               => '(missing-or-forward-parent-type))
        (check (diagnostic-codes conflicting-type)
               => '(type-identity-conflict))))

    (yuanxu-test-case "slot conflict rejects and explicit witnessed override closes"
      (let* ((cache (yuanxu-domain-case-cache))
             (foreign-role
              (poo-core-role-object
               (slots ((foreign/status #t)))
               (supers)))
             (foreign-type
              (yuanxu-case-type-contract 'Foreign '() (lambda (_) #t)))
             (foreign-slot
              (yuanxu-case-slot-contract
               'schema-version 'foreign 'boolean 'false 'replace '() #f
               boolean?))
             (foreign-component
              (yuanxu-case-component
               'foreign 1 foreign-role foreign-type
               (list foreign-slot) '() '()))
             (rejected
              (yuanxu-domain-case-close
               cache 'conflict.case.v1 1
               (list versioned-component foreign-component)))
             (override
              (yuanxu-case-slot-contract
               'schema-version 'conflict.case.v1 'positive-integer
               'required 'replace '(versioned foreign)
               'schema-version-compatibility-v1
               (lambda (value) (and (exact-integer? value) (> value 0)))))
             (accepted
              (yuanxu-domain-case-close
               cache 'override.case.v1 1
               (list versioned-component foreign-component)
               (list override))))
        (check (.ref rejected 'accepted?) => #f)
        (check (diagnostic-codes rejected) => '(slot-contract-conflict))
        (check (.ref accepted 'accepted?) => #t)))

    (yuanxu-test-case "method contract refinement requires an explicit witness"
      (let* ((cache (yuanxu-domain-case-cache))
             (base-contract
              (yuanxu-case-method-contract
               'run-base 'base 'run 'method 'Run
               'any-agent 'receipt (lambda (_) #t)))
             (strict-contract
              (yuanxu-case-method-contract
               'run-strict 'strict 'run 'method 'Run
               'admin-agent 'receipt+evidence (lambda (_) #t)))
             (witnessed-contract
              (yuanxu-case-method-contract
               'run-witnessed 'strict 'run 'method 'Run
               'any-agent 'receipt+evidence
               (lambda (context) (slot/default context 'allowed? #f))
               '(run-base) 'run-contract-refinement-v1
               (lambda (candidate inherited)
                 (and (equal? (.ref candidate 'domain-id)
                              (.ref inherited 'domain-id))
                      (equal? (.ref candidate 'precondition-id)
                              (.ref inherited 'precondition-id))))))
             (false-witness-contract
              (yuanxu-case-method-contract
               'run-false-witness 'strict 'run 'method 'Run
               'any-agent 'receipt+evidence (lambda (_) #t)
               '(run-base) 'run-false-refinement-v1
               (lambda (_candidate _inherited) #f)))
             (base
              (yuanxu-case-component
               'base 1 policy-role policy-type '()
               (list base-contract) '()))
             (strict
              (yuanxu-case-component
               'strict 1 policy-role policy-type '()
               (list strict-contract) '()))
             (witnessed
              (yuanxu-case-component
               'witnessed 1 policy-role policy-type '()
               (list witnessed-contract) '()))
             (false-witness
              (yuanxu-case-component
               'false-witness 1 policy-role policy-type '()
               (list false-witness-contract) '()))
             (rejected
              (yuanxu-domain-case-close
               cache 'contract.case.v1 1 (list base strict)))
             (accepted
              (yuanxu-domain-case-close
               cache 'contract.witnessed.case.v1 1 (list base witnessed)))
             (false-witness-rejected
              (yuanxu-domain-case-close
               cache 'contract.false-witness.case.v1 1
               (list base false-witness)))
             (allowed-context
              (poo-core-role-object (slots ((allowed? #t))) (supers)))
             (denied-context
              (poo-core-role-object (slots ((allowed? #f))) (supers)))
             (method-accepted
              (yuanxu-domain-case-check-method
               (.ref accepted 'domain-case) 'run allowed-context))
             (method-rejected
              (yuanxu-domain-case-check-method
               (.ref accepted 'domain-case) 'run denied-context))
             (method-unknown
              (yuanxu-domain-case-check-method
               (.ref accepted 'domain-case) 'unknown allowed-context)))
        (check (.ref rejected 'accepted?) => #f)
        (check (diagnostic-codes rejected)
               => '(contract-refinement-conflict))
        (check (.ref accepted 'accepted?) => #t)
        (check (diagnostic-codes false-witness-rejected)
               => '(contract-refinement-conflict))
        (check (.ref method-accepted 'accepted?) => #t)
        (check (.ref method-accepted 'contract-id) => 'run-witnessed)
        (check (.ref method-rejected 'accepted?) => #f)
        (check (diagnostic-codes method-rejected)
               => '(method-contract-rejected))
        (check (diagnostic-codes method-unknown)
               => '(unknown-method-contract))))

    (yuanxu-test-case "projection and policy algebra conflicts fail before caching"
      (let* ((cache (yuanxu-domain-case-cache))
             (other-projection
              (yuanxu-case-projection
               'runtime 'other 'other.runtime.v1 (lambda (_) '(other))))
             (other-component
              (yuanxu-case-component
               'other 1 policy-role policy-type '() '()
               (list other-projection) '() 'permit-overrides))
             (policy-component
              (yuanxu-case-component
               'policy 1 policy-role policy-type '() '() '()
               '() 'deny-overrides))
             (same-projection-component
              (yuanxu-case-component
               'same-projection 1 policy-role policy-type '() '()
               (list runtime-projection)))
             (same-projection
              (yuanxu-domain-case-close
               cache 'same-projection.case.v1 1
               (list versioned-component same-projection-component)
               '() '(runtime)))
             (receipt
              (yuanxu-domain-case-close
               cache 'projection.case.v1 1
               (list versioned-component other-component policy-component)
               '() '(runtime))))
        (check (.ref receipt 'accepted?) => #f)
        (check (diagnostic-codes receipt)
               => '(projection-name-conflict policy-algebra-conflict))
        (check (diagnostic-codes same-projection)
               => '(projection-name-conflict))
        (check (yuanxu-domain-case-cache-closure-count cache) => 0)))

    (yuanxu-test-case "slot, type, and state contracts fail at instance boundary"
      (let* ((cache (yuanxu-domain-case-cache))
             (case-value (.ref (close-base cache) 'domain-case))
             (invalid-type
              (yuanxu-domain-case-instantiate
               case-value (agent-role 'agent-invalid "revision-1" 0)))
             (invalid-state
              (yuanxu-domain-case-instantiate
               case-value (agent-role 'agent-blocked "blocked")))
             (missing-slot-role
              (poo-core-role-object
               (slots ((agent-id 'agent-missing)
                       (schema-id 'agent.case.v1)
                       (schema-version 1)))
               (supers)))
             (missing-slot
              (yuanxu-domain-case-instantiate
               case-value missing-slot-role)))
        (check (.ref invalid-type 'accepted?) => #f)
        (check (diagnostic-codes invalid-type)
               => '(slot-contract-rejected type-contract-rejected))
        (check (.ref invalid-state 'accepted?) => #f)
        (check (diagnostic-codes invalid-state)
               => '(state-contract-rejected))
        (check (.ref missing-slot 'accepted?) => #f)
        (check (diagnostic-codes missing-slot)
               => '(required-slot-missing type-contract-rejected))))

    (yuanxu-test-case "only selected projections cross the DomainCase boundary"
      (let* ((cache (yuanxu-domain-case-cache))
             (case-value (.ref (close-base cache) 'domain-case))
             (instance
              (.ref (yuanxu-domain-case-instantiate
                     case-value (agent-role 'agent-1 "revision-1"))
                    'instance))
             (selected
              (yuanxu-domain-case-project case-value 'runtime instance))
             (private
              (yuanxu-domain-case-project case-value 'private instance)))
        (check (.ref selected 'accepted?) => #t)
        (check (.ref selected 'schema-id) => 'agent.runtime-projection.v1)
        (check (.ref selected 'payload)
               => '((agent-id . agent-1)
                    (source-revision . "revision-1")))
        (check (.ref private 'accepted?) => #f)
        (check (diagnostic-codes private) => '(projection-not-selected))))

    (yuanxu-test-case "1000 Agents share one closed case and remain isolated"
      (let* ((cache (yuanxu-domain-case-cache))
             (closure (close-base cache))
             (case-value (.ref closure 'domain-case))
             (shared (.ref case-value 'shared-prototype)))
        (let loop ((index 0)
                   (all-accepted? #t)
                   (all-isolated? #t)
                   (all-case-bound? #t)
                   (shared-stable? #t))
          (if (= index 1000)
              (begin
                (check all-accepted? => #t)
                (check all-isolated? => #t)
                (check all-case-bound? => #t)
                (check shared-stable? => #t))
              (let* ((id
                      (string->symbol
                       (string-append "agent-" (number->string index))))
                     (receipt
                      (yuanxu-domain-case-instantiate
                       case-value (agent-role id "revision-fleet")))
                     (instance (.ref receipt 'instance)))
                (loop (+ index 1)
                      (and all-accepted? (.ref receipt 'accepted?))
                      (and all-isolated? (eq? (.ref instance 'agent-id) id))
                      (and all-case-bound?
                           (eq? (.ref instance 'domain-case/ref) case-value))
                      (and shared-stable?
                           (eq? (.ref case-value 'shared-prototype)
                                shared))))))
        (check (yuanxu-domain-case-cache-closure-count cache) => 1)
        (check (yuanxu-domain-case-instance-mix-count case-value) => 0)
        (check (yuanxu-domain-case-instance-overlay-count case-value) => 1000)
        (check (.ref closure 'cache-hit?) => #f)))

    (yuanxu-test-case "1000 Agents use sparse U=8/32/64 role-policy-strategy cases"
      (for-each
       (lambda (unique-count)
         (let (receipt (exercise-sparse-fleet unique-count))
           (check (.ref receipt 'agent-count) => 1000)
           (check (.ref receipt 'unique-case-count) => unique-count)
           (check (.ref receipt 'all-closures-accepted?) => #t)
           (check (.ref receipt 'all-warm-hits?) => #t)
           (check (.ref receipt 'all-instances-accepted?) => #t)
           (check (.ref receipt 'all-case-bindings-correct?) => #t)
           (check (.ref receipt 'closure-count) => unique-count)
           (check (.ref receipt 'cache-hit-count) => unique-count)
           (check (.ref receipt 'instance-mix-count) => 0)
           (check (.ref receipt 'instance-overlay-count) => 1000)))
       '(8 32 64)))))

(export domain-case-test)
