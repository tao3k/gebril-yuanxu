;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; End-to-end Yuanxu Loader integration test for Design 165:
;;; - Directory-hosted Feature `implied-modules:` auto-bridging (Band 1)
;;; - Cold zero-cost when prerequisite module is absent (INV-1 + INV-6)
;;; - Band 4b explicit `-feature` veto dominance (INV-3 + INV-6)
;;; - Plural `:profiles` & per-module `profiles:` convergence via `yuanxu-load-modules`
;;; - Auditable `activation-receipts` & zero-recompilation `.apply-runtime-overlay`

(import :std/test
        (only-in :std/list/list any find)
        (only-in :clan/poo/object .o .ref .slot?)
        (only-in :tao3k/yuanxu/module-system/source/link yuanxu-load-modules)
        (only-in :tao3k/yuanxu/module-system/convergence/types
                 by-tag make-global-profile make-governance-envelope))
(export c4-loader-integration-test)

(def (write-text! path content)
  (create-directory* (path-directory path))
  (call-with-output-file path (lambda (p) (display content p))))

(def (remove-tree! dir)
  (when (file-exists? dir)
    (let ((info (file-info dir #f)))
      (if (eq? (file-info-type info) 'directory)
        (begin
          (for-each (lambda (entry) (remove-tree! (path-expand entry dir)))
                    (directory-files dir))
          (delete-directory dir))
        (delete-file dir)))))

(def (make-fixture-workspace! root init-source-text (trap-durable-objects? #f))
  (write-text! (path-expand "gerbil.pkg" root)
               "(package: c4-fixture\n prelude: :tao3k/yuanxu/prelude)\n")
  (write-text! (path-expand "init.ss" root) init-source-text)

  ;; Module 1: env (assembly-stage mode slot)
  (write-text! (path-expand "modules/env/types.ss" root)
               "(import (only-in :clan/poo/type define-type Type.) (only-in :clan/poo/object object?))\n(export EnvContract)\n(define-type (EnvContract @ Type.) identity: 'env/scope .element?: object?)\n")
  (write-text! (path-expand "modules/env/objects.ss" root)
               "(import (only-in :clan/poo/object .o))\n(export EnvScope)\n(def EnvScope (.o name: 'env))\n")
  (write-text! (path-expand "modules/env/interface.ss" root)
               "(import (only-in :clan/poo/object .def .o)\n        (only-in :tao3k/yuanxu/module-system/convergence/types make-slot-spec)\n        \"./types.ss\" \"./objects.ss\")\n(export Env)\n(.def Env\n  identity: 'env\n  tags: '(runtime-env)\n  slot-specs: (list (make-slot-spec 'mode stage: 'assembly combiner: 'exclusive default: 'local-dev allowed: '(local-dev ci-hermetic airgapped)))\n  defaults: (.o mode: 'local-dev)\n  core: (.o scope-contract: EnvContract exports: EnvScope))\n")

  ;; Module 2: durable (pure engine, zero Org, runtime-stage detour-state slot)
  (write-text! (path-expand "modules/durable/types.ss" root)
               "(import (only-in :clan/poo/type define-type Type.) (only-in :clan/poo/object object?))\n(export DurableContract)\n(define-type (DurableContract @ Type.) identity: 'durable/scope .element?: object?)\n")
  (write-text! (path-expand "modules/durable/objects.ss" root)
               "(import (only-in :clan/poo/object .o))\n(export DurableScope)\n(def DurableScope (.o engine: 'pure-durable-work))\n")
  (write-text! (path-expand "modules/durable/interface.ss" root)
               "(import (only-in :clan/poo/object .def .o)\n        (only-in :tao3k/yuanxu/module-system/convergence/types make-slot-spec)\n        \"./types.ss\" \"./objects.ss\")\n(export Durable)\n(.def Durable\n  identity: 'durable\n  tags: '(engine durable)\n  slot-specs: (list (make-slot-spec 'detour-state stage: 'runtime combiner: 'exclusive default: 'none allowed: '(none blocker-active)))\n  defaults: (.o detour-state: 'none)\n  core: (.o scope-contract: DurableContract exports: DurableScope)\n  features: '())\n")

  ;; Module 3: ai-agentic-context with directory-hosted `features/durable/interface.ss`
  (write-text! (path-expand "modules/ai-agentic-context/types.ss" root)
               "(import (only-in :clan/poo/type define-type Type.) (only-in :clan/poo/object object?))\n(export ContextContract)\n(define-type (ContextContract @ Type.) identity: 'context/scope .element?: object?)\n")
  (write-text! (path-expand "modules/ai-agentic-context/objects.ss" root)
               "(import (only-in :clan/poo/object .o))\n(export ContextScope)\n(def ContextScope (.o context-kind: 'org-shared))\n")
  (write-text! (path-expand "modules/ai-agentic-context/interface.ss" root)
               (string-append
                "(import (only-in :clan/poo/object .def .o)\n"
                "        (only-in :tao3k/yuanxu/module-system/convergence/types make-slot-spec make-governance-envelope governance-envelope-meet)\n"
                "        \"./types.ss\" \"./objects.ss\")\n"
                "(export Context)\n"
                "(.def Context\n"
                "  identity: 'ai-agentic-context\n"
                "  tags: '(context org-backed)\n"
                "  slot-specs:\n"
                "  (list (make-slot-spec 'network-policy stage: 'assembly combiner: 'exclusive default: 'standard allowed: '(standard offline))\n"
                "        (make-slot-spec 'disclosure stage: 'assembly combiner: 'exclusive default: 'L1 allowed: '(L0 L1 L2 L3))\n"
                "        (make-slot-spec 'audit-hooks stage: 'assembly combiner: 'union default: '(base))\n"
                "        (make-slot-spec 'active-overlay stage: 'runtime combiner: 'exclusive default: 'normal allowed: '(normal detour-blocker))\n"
                "        (make-slot-spec 'envelope stage: 'assembly combiner: 'meet default: (make-governance-envelope 3 #t #t) meet: governance-envelope-meet))\n"
                "  defaults: (.o network-policy: 'standard disclosure: 'L1 audit-hooks: '(base) active-overlay: 'normal envelope: (make-governance-envelope 3 #t #t))\n"
                "  profiles: (.o env.mode: (.o ci-hermetic: (.o profile-id: 'AirgappedContextProfile. network-policy: 'offline))\n"
                "                durable.detour-state: (.o blocker-active: (.o profile-id: 'DetourBlockerProfile. active-overlay: 'detour-blocker)))\n"
                "  governance-floor: (.o envelope: (make-governance-envelope 2 #f #t))\n"
                "  core: (.o scope-contract: ContextContract exports: ContextScope)\n"
                "  features: '(durable))\n"))
  (write-text! (path-expand "modules/ai-agentic-context/features/durable/objects.ss" root)
               (if trap-durable-objects?
                 "(error \"INV-6 VIOLATION: inactive directory Feature objects.ss must NEVER be evaluated!\")\n"
                 "(import (only-in :clan/poo/object .o .slot? object?)\n        (only-in :clan/poo/type define-type Type.))\n(export EnableContextDurable ContextDurableContract)\n(define-type (ContextDurableContract @ Type.)\n  identity: 'context/durable-bridge\n  .element?: (lambda (s) (and (object? s) (.slot? s 'durable-bridge))))\n(def (EnableContextDurable inherited)\n  (.o (:: self inherited) durable-bridge: 'active-org-durable-bridge))\n"))
  (write-text! (path-expand "modules/ai-agentic-context/features/durable/interface.ss" root)
               "(import (only-in :clan/poo/object .def)\n        (only-in \"./objects.ss\" EnableContextDurable ContextDurableContract))\n(export Feature)\n(.def Feature\n  requires: '()\n  implied-modules: '(durable)\n  refine: EnableContextDurable\n  contract: ContextDurableContract)\n"))

(def c4-loader-integration-test
  (test-suite "Yuanxu Design 165 End-to-End Loader & Convergence Integration"

    (test-case "Directory Feature implied-modules auto-bridges in Band 1 with ActivationReceipt"
      (let ((root (path-expand (symbol->string (gensym 'c4-bridge-)) "/tmp")))
        (dynamic-wind
          void
          (lambda ()
            (make-fixture-workspace!
             root
             "(import (only-in :tao3k/yuanxu/prelude yuanxu!))\n(yuanxu!\n  :load-modules \"./modules\" mode: explicit mount: Fixture\n  (env)\n  (durable)\n  (ai-agentic-context))\n")
            (let* ((view (yuanxu-load-modules (path-expand "init.ss" root)))
                   (graph (.ref view 'selected-graph))
                   (implied (.ref graph 'implied-features))
                   (receipts (.ref view 'activation-receipts))
                   (ctx-scope (.ref (.ref (.ref view 'modules) 'Fixture) 'ai-agentic-context))
                   (bridge-receipt
                    (find (lambda (r)
                            (and (eq? (.ref r 'band) 'implied-bridge)
                                 (eq? (.ref r 'activation) 'implied)))
                          receipts)))
              (check (pair? implied) => #t)
              (check (and (memq 'c4-fixture/modules/ai-agentic-context/interface/durable implied) #t) => #t)
              (check (object? bridge-receipt) => #t)
              (check (.ref bridge-receipt 'observed-reads) => '((c4-fixture/modules/durable/interface enabled? #t)))
              (check (.ref ctx-scope 'durable-bridge) => 'active-org-durable-bridge)))
          (lambda () (remove-tree! root)))))

    (test-case "mode: auto + build-selection reuses cached loader-roots graph for implied-modules"
      (let ((root (path-expand (symbol->string (gensym 'c4-auto-bridge-)) "/tmp")))
        (dynamic-wind
          void
          (lambda ()
            (make-fixture-workspace!
             root
             "(import (only-in :tao3k/yuanxu/prelude yuanxu!))\n(yuanxu!\n  :load-modules \"./modules\" mode: auto)\n")
            (let* ((view (yuanxu-load-modules (path-expand "init.ss" root)
                           build-selection: (.o modules: '(modules/durable modules/ai-agentic-context)
                                                mounts: '())))
                   (graph (.ref view 'selected-graph))
                   (implied (.ref graph 'implied-features))
                   (ctx-scope (.ref (.ref (.ref view 'modules) 'modules) 'ai-agentic-context)))
              (check (and (memq 'c4-fixture/modules/ai-agentic-context/interface/durable implied) #t) => #t)
              (check (.slot? ctx-scope 'durable-bridge) => #t)
              (check (.ref ctx-scope 'durable-bridge) => 'active-org-durable-bridge)))
          (lambda () (remove-tree! root)))))

    (test-case "INV-1 & INV-6: Absent durable keeps directory Feature 100% cold (objects.ss never loaded)"
      (let ((root (path-expand (symbol->string (gensym 'c4-cold-)) "/tmp")))
        (dynamic-wind
          void
          (lambda ()
            (make-fixture-workspace!
             root
             "(import (only-in :tao3k/yuanxu/prelude yuanxu!))\n(yuanxu!\n  :load-modules \"./modules\" mode: explicit mount: Fixture\n  (env)\n  (ai-agentic-context))\n"
             #t)
            (let* ((view (yuanxu-load-modules (path-expand "init.ss" root)))
                   (graph (.ref view 'selected-graph))
                   (ctx-scope (.ref (.ref (.ref view 'modules) 'Fixture) 'ai-agentic-context)))
              (check (.ref graph 'implied-features) => '())
              (check (.ref graph 'feature-order) => '())
              (check (.slot? ctx-scope 'durable-bridge) => #f)))
          (lambda () (remove-tree! root)))))

    (test-case "INV-3 & INV-6: Band 4b explicit -durable veto dominates Band 1 and keeps objects.ss cold"
      (let ((root (path-expand (symbol->string (gensym 'c4-veto-)) "/tmp")))
        (dynamic-wind
          void
          (lambda ()
            (make-fixture-workspace!
             root
             "(import (only-in :tao3k/yuanxu/prelude yuanxu!))\n(yuanxu!\n  :load-modules \"./modules\" mode: explicit mount: Fixture\n  (env)\n  (durable)\n  (ai-agentic-context -durable))\n"
             #t)
            (let* ((view (yuanxu-load-modules (path-expand "init.ss" root)))
                   (graph (.ref view 'selected-graph))
                   (receipts (.ref view 'activation-receipts))
                   (ctx-scope (.ref (.ref (.ref view 'modules) 'Fixture) 'ai-agentic-context))
                   (veto-receipt
                    (find (lambda (r) (eq? (.ref r 'activation) 'vetoed)) receipts)))
              (check (.ref graph 'implied-features) => '())
              (check (.ref graph 'feature-order) => '())
              (check (object? veto-receipt) => #t)
              (check (.ref veto-receipt 'band) => 'module-profiles)
              (check (.slot? ctx-scope 'durable-bridge) => #f)))
          (lambda () (remove-tree! root)))))

    (test-case "Plural :profiles, profiles:, by-tag, .o table, GovernanceFloor, and Runtime Overlay"
      (let ((root (path-expand (symbol->string (gensym 'c4-profiles-)) "/tmp")))
        (dynamic-wind
          void
          (lambda ()
            (make-fixture-workspace!
             root
             (string-append
              "(import (only-in :tao3k/yuanxu/prelude yuanxu!))\n"
              "(yuanxu!\n"
              "  :load-modules \"./modules\" mode: explicit mount: Fixture\n"
              "  :profiles (CiHermeticGlobal. StrictAuditGlobal.)\n"
              "  (env)\n"
              "  (durable)\n"
              "  (ai-agentic-context profiles: (WorkspaceContextProfile.)))\n"))
            (let* ((view (yuanxu-load-modules (path-expand "init.ss" root)))
                   (gp-reg
                    (.o CiHermeticGlobal.:
                        (make-global-profile 'CiHermeticGlobal.
                                             '(env)
                                             (.o mode: 'ci-hermetic))
                        StrictAuditGlobal.:
                        (make-global-profile 'StrictAuditGlobal.
                                             (list (by-tag 'org-backed))
                                             (.o audit-hooks: '(sod-audit)
                                                 envelope: (make-governance-envelope 5 #t #t)))))
                   (mp-reg
                    (.o WorkspaceContextProfile.:
                        (.o profile-id: 'WorkspaceContextProfile.
                            disclosure: 'L2
                            audit-hooks: '(workspace-trace))))
                   (res ((.ref view '.converge-profiles)
                         global-profiles: gp-reg
                         module-profiles: mp-reg))
                   (eff (.ref res 'effective-configs))
                   (ctx-cfg (.ref eff 'c4-fixture/modules/ai-agentic-context/interface))
                   (env-cfg (.ref eff 'c4-fixture/modules/env/interface))
                   (env-floor (.ref ctx-cfg 'envelope)))
              (check (.ref res 'status) => 'ready)
              ;; Band 4a Global Profile set env.mode = ci-hermetic (resolved from leaf 'env!)
              (check (.ref env-cfg 'mode) => 'ci-hermetic)
              ;; Band 3 .o dispatch table triggered AirgappedContextProfile. -> offline
              (check (.ref ctx-cfg 'network-policy) => 'offline)
              ;; Band 4b per-module Profile set disclosure = L2
              (check (.ref ctx-cfg 'disclosure) => 'L2)
              ;; Union combiner merged base + by-tag(org-backed) + local profile
              (check (and (memq 'base (.ref ctx-cfg 'audit-hooks))
                          (memq 'sod-audit (.ref ctx-cfg 'audit-hooks))
                          (memq 'workspace-trace (.ref ctx-cfg 'audit-hooks)) #t) => #t)
              ;; Band 5 GovernanceFloor prevented trust escalation (clamped 5 -> 2, network #t -> #f)
              (check (.ref env-floor 'trust-ceiling) => 2)
              (check (.ref env-floor 'allow-network) => #f)
              ;; INV-6: Runtime-stage overlay activates DetourBlockerProfile. with ZERO closure expansion
              (let* ((rt ((.ref view '.apply-runtime-overlay)
                          res
                          (list (cons 'durable (.o detour-state: 'blocker-active)))))
                     (rt-ctx (.ref (.ref rt 'effective-configs) 'c4-fixture/modules/ai-agentic-context/interface)))
                (check (.ref rt 'status) => 'ready)
                (check (.ref rt 'compiled-closure) => (.ref res 'compiled-closure))
                (check (.ref rt-ctx 'active-overlay) => 'detour-blocker))))
          (lambda () (remove-tree! root)))))))
