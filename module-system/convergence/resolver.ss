;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Two-Phase POO Slot-Observation & 7-Band C4 Plural Profile Convergence Resolver.
;;;
;;; Implements Yuanxu Design 165 & Slice 53 invariants (INV-1..INV-6):
;;; - Closed `sys` proxy over explicitly admitted modules (`durable.enabled?` = #f when absent).
;;; - `%call-with-recorded-slot-reads` automatic read-set capture & `scc` cycle check.
;;; - Concise POO `.o` dispatch tables (`env.mode: (.o ci-hermetic: P.)`) with
;;;   static contract validation and automatic assembly vs runtime stage split.
;;; - Plural Global Profiles (`:profiles`, by ID or `by-tag`), plural Module Profiles,
;;;   Band 4b explicit `-feature` veto, Band 5 monotonic `GovernanceFloor`, and
;;;   zero-recompilation `converge-runtime-overlay`.

(import (only-in :clan/poo/object .o .ref .slot? .all-slots object? object<-alist)
        (only-in :clan/poo/object/slot-observation %call-with-recorded-slot-reads)
        (only-in :std/list/list filter find filter-map)
        (only-in :std/string/misc string-split)
        (only-in ./types
                 tag-selector? make-slot-spec
                 make-activation-receipt make-convergence-diagnostic
                 make-convergence-result)
        (only-in ./combiners
                 list-dedup-union apply-band-value merge-band-contributions))
(export parse-dotted-slot-path
        converge-assembly
        converge-runtime-overlay)

;;; ---------------------------------------------------------------------------
;;; Dotted Slot Path & Contract Helpers
;;; ---------------------------------------------------------------------------

(def (parse-dotted-slot-path sym)
  (let* ((parts (string-split (symbol->string sym) #\.))
         (syms (map string->symbol parts)))
    (if (= (length syms) 2)
      (values (car syms) (cadr syms))
      (values #f #f))))

(def (find-slot-spec mod-decl slot-name)
  (if (eq? slot-name 'enabled?)
    (make-slot-spec 'enabled? stage: 'assembly combiner: 'exclusive default: #t)
    (find (lambda (sp) (eq? (.ref sp 'name) slot-name))
          (.ref mod-decl 'slot-specs))))

(def (slot-value-valid? slot-spec val)
  (let ((allowed (.ref slot-spec 'allowed-values)))
    (or (not allowed) (and (member val allowed) #t))))

(def (normalize-profile-list v)
  (cond
   ((null? v) '())
   ((list? v) v)
   ((object? v) (list v))
   (else '())))

(def (module-has-tag? mod-decl tag)
  (and (memq tag (.ref mod-decl 'tags)) #t))

;; Build a closed `sys` POO proxy over `admitted-ids` (INV-1).
;; Unadmitted catalog modules expose ONLY `enabled?: #f` (never pulled into closure).
(def (build-sys-proxy catalog-by-id admitted-ids slot-table)
  (let ((all-ids (hash-keys catalog-by-id)))
    (object<-alist
     (map (lambda (mid)
            (if (memq mid admitted-ids)
              (let* ((mod-decl (hash-ref catalog-by-id mid))
                     (cur-vals (or (hash-get slot-table mid) (make-hash-table-eq)))
                     (entries
                      (cons
                       (cons 'enabled? #t)
                       (map (lambda (sp)
                              (let ((sn (.ref sp 'name)))
                                (cons sn (if (hash-key? cur-vals sn)
                                           (hash-ref cur-vals sn)
                                           (.ref sp 'default-value)))))
                            (.ref mod-decl 'slot-specs)))))
                (cons mid (object<-alist entries)))
              ;; Absent from explicit `yuanxu!` closure -> `enabled?: #f` ONLY (INV-1)
              (cons mid (.o bind-these: #f enabled?: #f))))
          all-ids))))

;;; ---------------------------------------------------------------------------
;;; Extract Slot Contributions Across Bands for One Module
;;; ---------------------------------------------------------------------------

(def (collect-object-slot-entries obj source-id)
  (if (not (object? obj))
    '()
    (map (lambda (k) (cons k (cons source-id (.ref obj k))))
         (.all-slots obj))))

(def (resolve-global-profile-targets gp admitted-ids catalog-by-id)
  (let ((targets (.ref gp 'targets)))
    (let loop ((rest targets) (acc '()))
      (if (null? rest)
        (reverse acc)
        (let ((t (car rest)))
          (cond
           ((tag-selector? t)
            (let* ((tag (.ref t 'tag))
                   (matched (filter (lambda (mid)
                                      (let ((md (hash-get catalog-by-id mid)))
                                        (and md (module-has-tag? md tag))))
                                    admitted-ids)))
              (loop (cdr rest)
                    (append (map (lambda (m) (cons m 'tag-targeted)) matched) acc))))
           ((symbol? t)
            (if (memq t admitted-ids)
              (loop (cdr rest) (cons (cons t 'explicit) acc))
              ;; INV-1: Global profile targeting an unadmitted module NEVER pulls it in
              (loop (cdr rest) acc)))
           (else (loop (cdr rest) acc))))))))

;; Resolve a module's concise POO `.o` dispatch table (`profiles: (.o env.mode: (.o ...))`)
;; for the requested `target-stage` ('assembly or 'runtime).
;; Returns (values matched-profiles receipts diagnostics).
(def (evaluate-profiles-table mod-decl target-stage admitted-ids catalog-by-id sys-proxy)
  (let ((mid (.ref mod-decl 'identity))
        (ptable (.ref mod-decl 'profiles-table))
        (matched '())
        (receipts '())
        (diags '()))
    (when (object? ptable)
      (for-each
       (lambda (dotted-key)
         (let-values (((target-mod target-slot) (parse-dotted-slot-path dotted-key)))
           (cond
            ((not target-mod)
             (set! diags
                   (cons (make-convergence-diagnostic
                          'invalid-slot-path mid dotted-key mid dotted-key
                          "Profile dispatch key must use dotted `module.slot` syntax")
                         diags)))
            ((not (hash-key? catalog-by-id target-mod))
             (set! diags
                   (cons (make-convergence-diagnostic
                          'unknown-target-module mid dotted-key mid target-mod
                          "Profile dispatch references unknown module")
                         diags)))
            ((not (memq target-mod admitted-ids))
             ;; INV-1: target module not admitted in explicit closure -> stays inert
             (void))
            (else
             (let* ((tdecl (hash-ref catalog-by-id target-mod))
                    (spec (find-slot-spec tdecl target-slot)))
               (if (not spec)
                 (set! diags
                       (cons (make-convergence-diagnostic
                              'unknown-interface-slot mid dotted-key target-mod target-slot
                              (string-append "Misspelled or undeclared Interface slot: "
                                             (symbol->string dotted-key)))
                             diags))
                 (let ((branches (.ref ptable dotted-key)))
                   ;; Validate all branch keys against slot contract's allowed-values (INV-2)
                   (when (object? branches)
                     (for-each
                      (lambda (branch-key)
                        (unless (slot-value-valid? spec branch-key)
                          (set! diags
                                (cons (make-convergence-diagnostic
                                       'invalid-slot-enum-value mid dotted-key branch-key target-slot
                                       (string-append "Invalid branch value `"
                                                      (symbol->string branch-key)
                                                      "` for slot " (symbol->string dotted-key)))
                                      diags))))
                      (.all-slots branches)))
                   ;; Evaluate ONLY branches matching `target-stage` (INV-6)
                   (when (and (eq? (.ref spec 'stage) target-stage)
                              (object? branches))
                     (let ((cur-val (.ref (.ref sys-proxy target-mod) target-slot)))
                       (when (and (symbol? cur-val) (.slot? branches cur-val))
                         (let* ((raw (.ref branches cur-val))
                                (profs (normalize-profile-list raw)))
                           (for-each
                            (lambda (p)
                              (let ((pid (if (and (object? p) (.slot? p 'profile-id))
                                           (.ref p 'profile-id)
                                           dotted-key)))
                                (set! matched (cons (cons pid p) matched))
                                (set! receipts
                                      (cons (make-activation-receipt
                                             (list mid pid)
                                             'derived-profiles
                                             target-stage
                                             'derived
                                             (list (list target-mod target-slot cur-val))
                                             (string-append "Derived via POO .o table "
                                                            (symbol->string dotted-key)
                                                            "=" (symbol->string cur-val)))
                                            receipts))))
                            profs))))))))))))
       (.all-slots ptable)))
    (values (reverse matched) (reverse receipts) (reverse diags))))

;; Apply one band's slot contributions per module (with same-band peer conflict checks INV-4).
(def (apply-band-table! band-entries-by-mod admitted-ids catalog-by-id slot-table)
  (let ((diags '()))
    (for-each
     (lambda (mid)
       (let ((mod-decl (hash-ref catalog-by-id mid))
             (mod-band (hash-get band-entries-by-mod mid))
             (cur-table (hash-ref slot-table mid)))
         (when mod-band
           (for-each
            (lambda (slot-name)
              (let ((spec (find-slot-spec mod-decl slot-name))
                    (entries (reverse (hash-ref mod-band slot-name))))
                (cond
                 ((not spec)
                  (set! diags
                        (cons (make-convergence-diagnostic
                               'unknown-interface-slot mid slot-name (car (car entries)) slot-name
                               (string-append "Profile targets undeclared slot "
                                              (symbol->string mid) "." (symbol->string slot-name)))
                              diags)))
                 (else
                  (let-values (((ok? merged peer-diags)
                                (merge-band-contributions mid spec entries)))
                    (if (not ok?)
                      (set! diags (append diags peer-diags))
                      (if (not (slot-value-valid? spec merged))
                        (set! diags
                              (cons (make-convergence-diagnostic
                                     'invalid-slot-value mid slot-name (car (car entries)) merged
                                     "Slot value violates ObjectContract allowed-values")
                                    diags))
                        (let* ((lower (if (hash-key? cur-table slot-name)
                                        (hash-ref cur-table slot-name)
                                        (.ref spec 'default-value)))
                               (next (apply-band-value spec lower merged)))
                          (hash-put! cur-table slot-name next)))))))))
            (hash-keys mod-band)))))
     admitted-ids)
    diags))

(def (record-band-entry! band-by-mod mid slot-name src-id val)
  (let ((m (or (hash-get band-by-mod mid)
               (let ((t (make-hash-table-eq)))
                 (hash-put! band-by-mod mid t)
                 t))))
    (hash-put! m slot-name (cons (cons src-id val) (or (hash-get m slot-name) '())))))

;;; ---------------------------------------------------------------------------
;;; Public Phase 1 + Phase 2 Assembly Convergence
;;; ---------------------------------------------------------------------------

(def (converge-assembly catalog-decls admitted-modules
                        explicit-flags: (explicit-flags '())
                        global-profiles: (global-profiles '())
                        module-profiles: (module-profiles '()))
  ;; `explicit-flags`: alist of (feature-id . #t/#f) where #f is Band 4b `-feature` veto.
  ;; `module-profiles`: alist of (module-id . (list ProfileObj ...)).
  (let* ((catalog-by-id (make-hash-table-eq))
         (slot-table (make-hash-table-eq))
         (receipts '())
         (diags '()))
    (for-each (lambda (md) (hash-put! catalog-by-id (.ref md 'identity) md))
              catalog-decls)
    ;; Validate every admitted module exists in catalog
    (for-each
     (lambda (mid)
       (if (not (hash-key? catalog-by-id mid))
         (set! diags (cons (make-convergence-diagnostic
                            'unknown-module mid 'enabled? 'yuanxu! mid
                            "Admitted module not found in catalog")
                           diags))
         (let* ((md (hash-ref catalog-by-id mid))
                (st (make-hash-table-eq)))
           ;; Band 0: CoreDefaults
           (for-each (lambda (sp) (hash-put! st (.ref sp 'name) (.ref sp 'default-value)))
                     (.ref md 'slot-specs))
           (when (object? (.ref md 'defaults))
             (for-each (lambda (k) (hash-put! st k (.ref (.ref md 'defaults) k)))
                       (.all-slots (.ref md 'defaults))))
           (hash-put! slot-table mid st)
           (set! receipts (cons (make-activation-receipt
                                 mid 'core-defaults 'assembly 'explicit '()
                                 "Module core explicitly admitted in yuanxu!")
                                receipts)))))
     admitted-modules)

    (if (pair? diags)
      (make-convergence-result 'rejected admitted-modules '() '() (.o) (reverse receipts) (reverse diags))
      (let* ((flag-map (make-hash-table-eq))
             (active-features '())
             (active-feature-decls '())
             (feature-reads-by-id (make-hash-table-eq)))
        (for-each (lambda (p) (hash-put! flag-map (car p) (cdr p))) explicit-flags)

        ;; Phase 1a: Evaluate Global Profiles (Band 4a) for assembly-stage slots first
        ;; so assembly-stage `.o` tables (e.g., `env.mode`) observe Global Profile settings!
        (let ((gp-band (make-hash-table-eq)))
          (for-each
           (lambda (gp)
             (let* ((pid (.ref gp 'profile-id))
                    (vals (.ref gp 'values))
                    (targets (resolve-global-profile-targets gp admitted-modules catalog-by-id)))
               (for-each
                (lambda (tpair)
                  (let ((mid (car tpair))
                        (act-kind (cdr tpair)))
                    (for-each
                     (lambda (slot-name)
                       (record-band-entry! gp-band mid slot-name pid (.ref vals slot-name)))
                     (.all-slots vals))
                    (set! receipts (cons (make-activation-receipt
                                          (list mid pid) 'global-profiles 'assembly act-kind '()
                                          "Global Profile bound in yuanxu! :profiles")
                                         receipts))))
                targets)))
           global-profiles)
          (set! diags (append diags (apply-band-table! gp-band admitted-modules catalog-by-id slot-table))))

        ;; Phase 1b: Evaluate Feature `enabled?:` inside `gerbil-poo` `slot-observation`!
        (let ((sys-proxy (build-sys-proxy catalog-by-id admitted-modules slot-table)))
          (for-each
           (lambda (mid)
             (let ((md (hash-ref catalog-by-id mid)))
               (for-each
                (lambda (fdecl)
                  (let* ((fid (.ref fdecl 'feature-id))
                         (efn (.ref fdecl 'enabled-fn))
                         (has-flag? (hash-key? flag-map fid))
                         (flag-val (and has-flag? (hash-ref flag-map fid))))
                    (cond
                     ;; Band 4b explicit `-feature` veto ALWAYS dominates (INV-3)
                     ((and has-flag? (not flag-val))
                      (set! receipts
                            (cons (make-activation-receipt
                                   fid 'module-profiles 'assembly 'vetoed '()
                                   "Explicit -feature veto in yuanxu! overrides Band 1 implied bridge")
                                  receipts)))
                     ;; Band 2 explicit `+feature`
                     ((and has-flag? flag-val)
                      (set! active-features (cons fid active-features))
                      (set! active-feature-decls (cons fdecl active-feature-decls))
                      (set! receipts
                            (cons (make-activation-receipt
                                   fid 'explicit-feature 'assembly 'explicit '()
                                   "Explicit +feature in yuanxu!")
                                  receipts)))
                     ;; Band 1 native POO `enabled?:` evaluated with `%call-with-recorded-slot-reads`
                     ((procedure? efn)
                      (let-values (((res reads)
                                    (%call-with-recorded-slot-reads
                                     (lambda () (efn sys-proxy))
                                     unique-roots?: #t)))
                        (hash-put! feature-reads-by-id fid reads)
                        (when res
                          (set! active-features (cons fid active-features))
                          (set! active-feature-decls (cons fdecl active-feature-decls))
                          (set! receipts
                                (cons (make-activation-receipt
                                       fid 'implied-bridge 'assembly 'implied
                                       (map (lambda (r) (if (pair? r) (cdr r) r)) reads)
                                       "Implied bridge activated via native POO enabled?: slot")
                                      receipts))))))))
                (.ref md 'features))))
           admitted-modules)

          ;; Validate feature `requires:` and `conflicts:` + SCC cycle check (INV-2)
          (let ((active-set (reverse active-features)))
            (for-each
             (lambda (fdecl)
               (let ((fid (.ref fdecl 'feature-id)))
                 (for-each
                  (lambda (req)
                    (unless (or (memq req active-set) (memq req admitted-modules))
                      (set! diags (cons (make-convergence-diagnostic
                                         'missing-feature-dependency (.ref fdecl 'owner-module-id)
                                         fid fid req
                                         "Active feature missing required dependency")
                                        diags))))
                  (.ref fdecl 'requires))
                 (for-each
                  (lambda (conf)
                    (when (memq conf active-set)
                      (set! diags (cons (make-convergence-diagnostic
                                         'feature-conflict (.ref fdecl 'owner-module-id)
                                         fid fid conf
                                         "Mutually exclusive features active simultaneously")
                                        diags))))
                  (.ref fdecl 'conflicts))))
             active-feature-decls)

            ;; Apply Band 1/2 feature contributions (including open extension slots `union`/`refine`)
            (let ((feat-band (make-hash-table-eq)))
              (for-each
               (lambda (fdecl)
                 (let ((fid (.ref fdecl 'feature-id))
                       (contribs (.ref fdecl 'contributions)))
                   (when (object? contribs)
                     (for-each
                      (lambda (target-mod)
                        (when (memq target-mod admitted-modules)
                          (let ((cobj (.ref contribs target-mod)))
                            (when (object? cobj)
                              (for-each
                               (lambda (slot-name)
                                 (record-band-entry! feat-band target-mod slot-name fid
                                                     (.ref cobj slot-name)))
                               (.all-slots cobj))))))
                      (.all-slots contribs)))))
               (reverse active-feature-decls))
              (set! diags (append diags (apply-band-table! feat-band admitted-modules catalog-by-id slot-table))))

            ;; Phase 2a: Band 3 Derived Profiles via POO `.o` dispatch tables (assembly stage ONLY — INV-6)
            (let ((derived-band (make-hash-table-eq))
                  (sys-after-gp (build-sys-proxy catalog-by-id admitted-modules slot-table)))
              (for-each
               (lambda (mid)
                 (let ((md (hash-ref catalog-by-id mid)))
                   (let-values (((matched m-receipts m-diags)
                                 (evaluate-profiles-table md 'assembly admitted-modules catalog-by-id sys-after-gp)))
                     (set! receipts (append (reverse m-receipts) receipts))
                     (set! diags (append diags m-diags))
                     (for-each
                      (lambda (mp)
                        (let ((pid (car mp))
                              (pobj (cdr mp)))
                          (for-each
                           (lambda (slot-name)
                             (unless (eq? slot-name 'profile-id)
                               (record-band-entry! derived-band mid slot-name pid (.ref pobj slot-name))))
                           (.all-slots pobj))))
                      matched))))
               admitted-modules)
              (set! diags (append diags (apply-band-table! derived-band admitted-modules catalog-by-id slot-table))))

            ;; Phase 2b: Band 4b Plural Per-Module Profiles (overrides Band 4a via C4!)
            (let ((mod-band (make-hash-table-eq)))
              (for-each
               (lambda (entry)
                 (let ((mid (car entry))
                       (profs (cdr entry)))
                   (when (memq mid admitted-modules)
                     (for-each
                      (lambda (pobj)
                        (let ((pid (if (.slot? pobj 'profile-id) (.ref pobj 'profile-id) 'local-profile)))
                          (for-each
                           (lambda (slot-name)
                             (unless (eq? slot-name 'profile-id)
                               (record-band-entry! mod-band mid slot-name pid (.ref pobj slot-name))))
                           (.all-slots pobj))
                          (set! receipts (cons (make-activation-receipt
                                                (list mid pid) 'module-profiles 'assembly 'explicit '()
                                                "Per-module Profile bound in yuanxu! profiles:")
                                               receipts))))
                      profs))))
               module-profiles)
              (set! diags (append diags (apply-band-table! mod-band admitted-modules catalog-by-id slot-table))))

            ;; Phase 2c: Band 5 GovernanceFloor monotonic `meet` (INV-5: un-escalatable!)
            (for-each
             (lambda (mid)
               (let* ((md (hash-ref catalog-by-id mid))
                      (floor (.ref md 'governance-floor))
                      (cur (hash-ref slot-table mid)))
                 (when (object? floor)
                   (for-each
                    (lambda (slot-name)
                      (let ((spec (find-slot-spec md slot-name)))
                        (when (and spec (eq? (.ref spec 'combiner) 'meet))
                          (let ((cur-val (if (hash-key? cur slot-name)
                                           (hash-ref cur slot-name)
                                           (.ref spec 'default-value)))
                                (floor-val (.ref floor slot-name)))
                            (hash-put! cur slot-name (apply-band-value spec floor-val cur-val))))))
                    (.all-slots floor)))))
             admitted-modules)

            (let ((compiled-closure (append admitted-modules active-set))
                  (effective
                   (object<-alist
                    (map (lambda (mid)
                           (let ((st (hash-ref slot-table mid)))
                             (cons mid
                                   (object<-alist
                                    (map (lambda (k) (cons k (hash-ref st k)))
                                         (hash-keys st))))))
                         admitted-modules))))
              (make-convergence-result
               (if (null? diags) 'ready 'rejected)
               admitted-modules
               active-set
               compiled-closure
               effective
               (reverse receipts)
               diags))))))))

;;; ---------------------------------------------------------------------------
;;; Dynamic Runtime-Stage C4 Overlay (Zero Recompilation — INV-6)
;;; ---------------------------------------------------------------------------

(def (converge-runtime-overlay catalog-decls assembly-result runtime-slot-updates)
  ;; `runtime-slot-updates`: alist of (module-id . POO-object-of-runtime-slots)
  (let* ((admitted (.ref assembly-result 'admitted-modules))
         (catalog-by-id (make-hash-table-eq))
         (slot-table (make-hash-table-eq))
         (eff (.ref assembly-result 'effective-configs))
         (receipts (reverse (.ref assembly-result 'receipts)))
         (diags '()))
    (for-each (lambda (md) (hash-put! catalog-by-id (.ref md 'identity) md)) catalog-decls)
    ;; Clone current effective slots
    (for-each
     (lambda (mid)
       (let ((st (make-hash-table-eq))
             (cur (.ref eff mid)))
         (for-each (lambda (k) (hash-put! st k (.ref cur k))) (.all-slots cur))
         (hash-put! slot-table mid st)))
     admitted)
    ;; Apply runtime-stage state slot updates (validated strictly as `stage: 'runtime`)
    (for-each
     (lambda (entry)
       (let ((mid (car entry))
             (upd (cdr entry)))
         (when (memq mid admitted)
           (let ((md (hash-ref catalog-by-id mid))
                 (st (hash-ref slot-table mid)))
             (for-each
              (lambda (sn)
                (let ((spec (find-slot-spec md sn)))
                  (cond
                   ((not spec)
                    (set! diags (cons (make-convergence-diagnostic
                                       'unknown-runtime-slot mid sn 'runtime sn
                                       "Unknown runtime slot update")
                                      diags)))
                   ((not (eq? (.ref spec 'stage) 'runtime))
                    (set! diags (cons (make-convergence-diagnostic
                                       'assembly-slot-mutated-at-runtime mid sn 'runtime sn
                                       "Refusing to mutate assembly-stage slot during runtime overlay")
                                      diags)))
                   (else
                    (hash-put! st sn (.ref upd sn))))))
              (.all-slots upd))))))
     runtime-slot-updates)
    ;; Evaluate ONLY runtime-stage branches of `.o` dispatch tables (compiled-closure UNCHANGED!)
    (let ((sys-rt (build-sys-proxy catalog-by-id admitted slot-table))
          (rt-band (make-hash-table-eq)))
      (for-each
       (lambda (mid)
         (let ((md (hash-ref catalog-by-id mid)))
           (let-values (((matched m-receipts m-diags)
                         (evaluate-profiles-table md 'runtime admitted catalog-by-id sys-rt)))
             (set! receipts (append (reverse m-receipts) receipts))
             (set! diags (append diags m-diags))
             (for-each
              (lambda (mp)
                (let ((pid (car mp))
                      (pobj (cdr mp)))
                  (for-each
                   (lambda (slot-name)
                     (unless (eq? slot-name 'profile-id)
                       (record-band-entry! rt-band mid slot-name pid (.ref pobj slot-name))))
                   (.all-slots pobj))))
              matched))))
       admitted)
      (set! diags (append diags (apply-band-table! rt-band admitted catalog-by-id slot-table)))
      (let ((next-eff
             (object<-alist
              (map (lambda (mid)
                     (let ((st (hash-ref slot-table mid)))
                       (cons mid
                             (object<-alist
                              (map (lambda (k) (cons k (hash-ref st k)))
                                   (hash-keys st))))))
                   admitted))))
        (make-convergence-result
         (if (null? diags) 'ready 'rejected)
         admitted
         (.ref assembly-result 'active-features)
         ;; INV-6: runtime overlay NEVER expands compiled-closure!
         (.ref assembly-result 'compiled-closure)
         next-eff
         (reverse receipts)
         diags)))))
