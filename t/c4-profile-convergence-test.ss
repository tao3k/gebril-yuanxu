;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Comprehensive positive and negative-control tests for Yuanxu Design 165 &
;;; Slice 53 (INV-1..INV-6): Two-Tier Interface, POO Slot-Observation, Dotted
;;; Paths, `.o` Dispatch Tables, Plural Global/Module Profiles, and Runtime Overlays.

(import :std/test
        (only-in :clan/poo/object .o .ref .get .slot?)
        (only-in :std/list/list find)
        (only-in :tao3k/yuanxu/module-system/source/init module-init-intent)
        (only-in :tao3k/yuanxu/module-system/source/selection select-module-graph)
        (only-in :tao3k/yuanxu/module-system/convergence/func
                 make-slot-spec make-governance-envelope governance-envelope-meet
                 by-tag make-feature-decl make-module-decl make-global-profile
                 converge-assembly converge-runtime-overlay))
(export c4-profile-convergence-test)

;;; ---------------------------------------------------------------------------
;;; Target Catalog: `env`, `durable`, `ai-agentic-context`, `ui-workbench`
;;; ---------------------------------------------------------------------------

(def AirgappedContextProfile.
  (.o bind-these: #f
      profile-id: 'airgapped-context
      no-live-llm: #t
      governance-envelope: (make-governance-envelope 1 #f #t)))

(def DetourBlockerProfile.
  (.o bind-these: #f
      profile-id: 'detour-blocker
      auto-archive: #f
      hooks: '(detour-guard)))

(def StagingContextProfile.
  (.o bind-these: #f
      profile-id: 'staging-context
      hooks: '(staging-trace)))

(def (make-test-catalog (extra-env-branches #f) (bad-slot-key? #f))
  (let* ((env-mod
          (make-module-decl
           'env
           tags: '(environment)
           slot-specs: (list (make-slot-spec 'mode
                                             stage: 'assembly
                                             combiner: 'exclusive
                                             default: 'local-dev
                                             allowed: '(local-dev ci-hermetic airgapped staging)))))
         (durable-mod
          (make-module-decl
           'durable
           tags: '(engine policy durable)
           slot-specs: (list (make-slot-spec 'detour-state
                                             stage: 'runtime
                                             combiner: 'exclusive
                                             default: 'mainline
                                             allowed: '(mainline blocker-active side-quest-active)))
           features: '())) ;; 100% pure Durable — ZERO Org features!
         (ui-mod
          (make-module-decl
           'ui-workbench
           tags: '(ui)
           slot-specs: (list (make-slot-spec 'tab-providers
                                             stage: 'assembly
                                             combiner: 'union
                                             default: '(index-tab)))))
         (context-durable-feat
          (make-feature-decl
           'ai-agentic-context 'durable
           ;; Native POO `enabled?: durable.enabled?` tracked by `slot-observation`!
           enabled-fn: (lambda (sys) (.get sys durable enabled?))
           contributions: (.o bind-these: #f
                              ui-workbench: (.o bind-these: #f tab-providers: '(durable-task-tabs)))))
         (env-branches
          (if extra-env-branches
            extra-env-branches
            (.o bind-these: #f
                ci-hermetic: AirgappedContextProfile.
                airgapped: AirgappedContextProfile.)))
         (profiles-tbl
          (if bad-slot-key?
            (.o bind-these: #f env.mdoe: (.o bind-these: #f ci-hermetic: AirgappedContextProfile.))
            (.o bind-these: #f
                env.mode: env-branches
                durable.detour-state: (.o bind-these: #f blocker-active: DetourBlockerProfile.))))
         (context-mod
          (make-module-decl
           'ai-agentic-context
           tags: '(context org-backed llm-client)
           slot-specs: (list (make-slot-spec 'no-live-llm stage: 'assembly combiner: 'exclusive default: #f)
                             (make-slot-spec 'auto-archive stage: 'assembly combiner: 'exclusive default: #t)
                             (make-slot-spec 'focused-tab-archive stage: 'assembly combiner: 'exclusive
                                             default: 'on-blur allowed: '(immediate on-blur manual))
                             (make-slot-spec 'hooks stage: 'assembly combiner: 'union default: '(core-org))
                             (make-slot-spec 'governance-envelope stage: 'assembly combiner: 'meet
                                             default: (make-governance-envelope 2 #t #t)
                                             meet: governance-envelope-meet))
           features: (list context-durable-feat)
           profiles: profiles-tbl
           governance-floor: (.o bind-these: #f
                                 governance-envelope: (make-governance-envelope 2 #t #t)))))
    (list env-mod durable-mod ui-mod context-mod)))

(def c4-profile-convergence-test
  (test-suite "Yuanxu Design 165 & Slice 53 C4 Plural Profile Convergence"

    (test-case "Context + Durable auto-bridge (zero durable/+org), -durable veto, and INV-1/INV-6"
      (let ((cat (make-test-catalog)))
        ;; 1. Context alone -> durable.enabled? is #f, bridge stays unloaded (INV-1 & INV-6)
        (let ((r-alone (converge-assembly cat '(env ai-agentic-context))))
          (check (.ref r-alone 'status) => 'ready)
          (check (.ref r-alone 'active-features) => '())
          (check (and (memq 'ai-agentic-context/durable (.ref r-alone 'compiled-closure)) #t) => #f)
          (check (and (memq 'durable (.ref r-alone 'admitted-modules)) #t) => #f))

        ;; 2. Context + Durable + UI -> bridge auto-activates in Band 1 and contributes to open union slot!
        (let ((r-both (converge-assembly cat '(env durable ai-agentic-context ui-workbench))))
          (check (.ref r-both 'status) => 'ready)
          (check (.ref r-both 'active-features) => '(ai-agentic-context/durable))
          (check (and (memq 'ai-agentic-context/durable (.ref r-both 'compiled-closure)) #t) => #t)
          (check (.get (.ref r-both 'effective-configs) ui-workbench tab-providers)
                 => '(index-tab durable-task-tabs))
          (let ((implied-rec (find (lambda (rc) (eq? (.ref rc 'identity) 'ai-agentic-context/durable))
                                   (.ref r-both 'receipts))))
            (check (.ref implied-rec 'band) => 'implied-bridge)
            (check (.ref implied-rec 'activation) => 'implied)))

        ;; 3. Explicit `-durable` Band 4b veto dominates Band 1 implied bridge (INV-3)
        (let ((r-veto (converge-assembly cat '(env durable ai-agentic-context ui-workbench)
                                         explicit-flags: '((ai-agentic-context/durable . #f)))))
          (check (.ref r-veto 'status) => 'ready)
          (check (.ref r-veto 'active-features) => '())
          (check (.get (.ref r-veto 'effective-configs) ui-workbench tab-providers) => '(index-tab)))))

    (test-case "Plural Global Profiles, by-tag targeting, POO .o table derivation, and zero-recompile runtime overlay"
      (let* ((cat (make-test-catalog))
             (ci-profile (make-global-profile 'ci-env '(env) (.o bind-these: #f mode: 'ci-hermetic)))
             (tag-profile (make-global-profile 'llm-hooks (list (by-tag 'llm-client))
                                               (.o bind-these: #f hooks: '(audit-tag-hook))))
             (r-asm (converge-assembly cat '(env durable ai-agentic-context)
                                       global-profiles: (list ci-profile tag-profile))))
        (check (.ref r-asm 'status) => 'ready)
        ;; `env.mode = 'ci-hermetic` fired `AirgappedContextProfile.` from POO `.o` table!
        (check (.get (.ref r-asm 'effective-configs) ai-agentic-context no-live-llm) => #t)
        (check (.get (.ref r-asm 'effective-configs) ai-agentic-context hooks)
               => '(core-org audit-tag-hook))
        (check (.ref (.get (.ref r-asm 'effective-configs) ai-agentic-context governance-envelope)
                     'allow-network)
               => #f)
        ;; Runtime-stage `durable.detour-state = 'blocker-active` activates `DetourBlockerProfile.`
        ;; with ZERO expansion of `compiled-closure` (INV-6)!
        (let ((r-rt (converge-runtime-overlay
                     cat r-asm
                     (list (cons 'durable (.o bind-these: #f detour-state: 'blocker-active))))))
          (check (.ref r-rt 'status) => 'ready)
          (check (.ref r-rt 'compiled-closure) => (.ref r-asm 'compiled-closure))
          (check (.get (.ref r-rt 'effective-configs) ai-agentic-context auto-archive) => #f)
          (check (.get (.ref r-rt 'effective-configs) ai-agentic-context hooks)
                 => '(core-org audit-tag-hook detour-guard)))))

    (test-case "INV-4 same-band exclusive peer conflict fails closed; INV-5 GovernanceFloor prevents escalation; INV-2 catches typos"
      (let* ((cat (make-test-catalog))
             (gp1 (make-global-profile 'p1 '(ai-agentic-context)
                                       (.o bind-these: #f focused-tab-archive: 'on-blur)))
             (gp2 (make-global-profile 'p2 '(ai-agentic-context)
                                       (.o bind-these: #f focused-tab-archive: 'immediate)))
             (r-conf (converge-assembly cat '(env ai-agentic-context)
                                        global-profiles: (list gp1 gp2))))
        ;; INV-4: disagreeing same-band exclusive scalar fails closed!
        (check (.ref r-conf 'status) => 'rejected)
        (check (.ref (car (.ref r-conf 'diagnostics)) 'code) => 'peer-exclusive-conflict))

      ;; INV-5: Band 4b Module Profile cannot escalate Band 5 GovernanceFloor (trust-ceiling stays <= 2)
      (let* ((cat (make-test-catalog))
             (escalate-prof (.o bind-these: #f
                                profile-id: 'escalate-attempt
                                governance-envelope: (make-governance-envelope 99 #t #t)))
             (r-floor (converge-assembly cat '(env ai-agentic-context)
                                         module-profiles: (list (cons 'ai-agentic-context (list escalate-prof))))))
        (check (.ref r-floor 'status) => 'ready)
        (check (.ref (.get (.ref r-floor 'effective-configs) ai-agentic-context governance-envelope)
                     'trust-ceiling)
               => 2))

      ;; INV-2: misspelled slot key `env.mdoe` in `.o` dispatch table fails closed!
      (let* ((bad-cat (make-test-catalog #f #t))
             (r-typo (converge-assembly bad-cat '(env ai-agentic-context))))
        (check (.ref r-typo 'status) => 'rejected)
        (check (.ref (car (.ref r-typo 'diagnostics)) 'code) => 'unknown-interface-slot)))

    (test-case "yuanxu! frontend parses plural :profiles / profiles: and select-module-graph auto-bridges implied-modules"
      (let* ((forms
              '((yuanxu!
                  :load-modules "./modules"
                  mode: explicit
                  mount: Lab
                  :profiles (LocalDevProfile. StrictSoDProfile.)
                  (durable)
                  (ai-agentic-context +memory
                                      profiles: (WorkspaceContextProfile. OrgProgressiveProfile.)))))
             (intent (module-init-intent forms "/tmp/init.ss"))
             (ctx-row (find (lambda (r) (eq? (.ref r 'identity) 'ai-agentic-context))
                            (.ref intent 'decisions))))
        (check (.ref intent 'global-profiles) => '(LocalDevProfile. StrictSoDProfile.))
        (check (.ref ctx-row 'profiles) => '(WorkspaceContextProfile. OrgProgressiveProfile.)))
      ;; Fail-closed negative controls on malformed :profiles / duplicate profiles:
      (check-exception
       (module-init-intent
        '((yuanxu! :load-modules "./modules" mode: explicit :profiles () (durable)))
        "/tmp/bad1.ss")
       true)
      (check-exception
       (module-init-intent
        '((yuanxu! :load-modules "./modules" mode: explicit
                   (durable profiles: (P1.) profiles: (P2.))))
        "/tmp/bad2.ss")
       true)
      ;; Live `select-module-graph` auto-activates `ai-agentic-context/durable` when both modules
      ;; are admitted, stays inert when `durable` is absent, and obeys `-durable` explicit veto!
      (let* ((pubs
              (lambda (id)
                (case id
                  ((durable) (.o identity: 'durable features: (.o)))
                  ((ai-agentic-context)
                   (.o identity: 'ai-agentic-context
                       features: (.o durable: (.o implied-modules: '(durable)))))
                  (else (error "unknown test pub" id)))))
             (run-sel
              (lambda (init-form roots)
                (let* ((intent-val (module-init-intent (list init-form) "/tmp/sel-init.ss"))
                       (ctx (.o bind-these: #f
                                intent: intent-val
                                init-source: "/tmp/sel-init.ss"
                                generation: 1
                                selected: roots
                                denied-modules: '())))
                  (select-module-graph ctx roots pubs void (lambda (_id) '()))))))
        ;; 1. Context alone -> bridge stays inert
        (let ((g-alone (run-sel '(yuanxu! :load-modules "./m" mode: explicit (ai-agentic-context))
                                '(ai-agentic-context))))
          (check (.ref g-alone 'feature-order) => '())
          (check (.ref g-alone 'implied-features) => '()))
        ;; 2. Durable + Context -> `ai-agentic-context/durable` auto-activates as implied!
        (let ((g-both (run-sel '(yuanxu! :load-modules "./m" mode: explicit (durable) (ai-agentic-context))
                               '(durable ai-agentic-context))))
          (check (.ref g-both 'feature-order) => '(ai-agentic-context/durable))
          (check (.ref g-both 'implied-features) => '(ai-agentic-context/durable)))
        ;; 3. Durable + Context -durable -> explicit veto dominates!
        (let ((g-veto (run-sel '(yuanxu! :load-modules "./m" mode: explicit (durable) (ai-agentic-context -durable))
                               '(durable ai-agentic-context))))
          (check (.ref g-veto 'feature-order) => '())
          (check (.ref g-veto 'implied-features) => '()))))))
