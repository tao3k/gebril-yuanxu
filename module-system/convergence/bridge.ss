;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Pure functional bridge connecting Yuanxu's selected module graph (`select-module-graph`)
;;; to Design 165's 7-Band C4 Plural Profile Convergence (`converge-assembly` / `converge-runtime-overlay`).

(import (only-in :clan/poo/object .o .ref .slot? .all-slots object? object<-alist)
        (only-in :std/list/list filter filter-map find)
        (only-in ./types
                 tag-selector? make-global-profile
                 make-feature-decl make-module-decl
                 make-activation-receipt make-convergence-diagnostic
                 make-convergence-result)
        (only-in ./resolver parse-dotted-slot-path converge-assembly converge-runtime-overlay))
(export project-graph-convergence-decls
        converge-selected-graph
        apply-graph-runtime-overlay)

(def (lookup-profile-symbol sym registry catalogs)
  (let ((from-reg
         (cond
          ((and (object? registry) (.slot? registry sym)) (.ref registry sym))
          ((list? registry)
           (let ((hit (assq sym registry)))
             (and hit (cdr hit))))
          (else #f))))
    (or from-reg
        (let loop ((rest catalogs))
          (if (null? rest)
            #f
            (let ((cat (car rest)))
              (if (and (object? cat) (.slot? cat sym))
                (.ref cat sym)
                (loop (cdr rest)))))))))

(def (feature-enabled-fn-for-prereqs prereqs)
  (and (pair? prereqs)
       (lambda (sys)
         (let loop ((rest prereqs))
           (or (null? rest)
               (let ((m (car rest)))
                 (and (.slot? sys m)
                      (.ref (.ref sys m) 'enabled?)
                      (loop (cdr rest)))))))))

;; Build a canonical target resolver mapping exact qualified module IDs and
;; unambiguous declared leaf identities (e.g. 'env -> 'pkg/modules/env/interface).
(def (make-graph-module-resolver graph)
  (let* ((nodes (.ref graph 'nodes))
         (core-nodes (filter (lambda (n) (eq? (.ref n 'kind) 'module-core)) nodes))
         (exact-set (make-hash-table-eq))
         (leaf-counts (make-hash-table-eq))
         (leaf-map (make-hash-table-eq)))
    (for-each
     (lambda (cnode)
       (let* ((mid (.ref cnode 'identity))
              (pub (.ref cnode 'publication))
              (leaf (and (object? pub) (.slot? pub 'identity) (.ref pub 'identity))))
         (hash-put! exact-set mid mid)
         (when (symbol? leaf)
           (hash-put! leaf-counts leaf (+ 1 (or (hash-get leaf-counts leaf) 0)))
           (hash-put! leaf-map leaf mid))))
     core-nodes)
    (lambda (owner-id target-sym)
      (cond
       ((hash-get exact-set target-sym) => values)
       ((and (eq? 1 (hash-get leaf-counts target-sym))
             (hash-get leaf-map target-sym))
        => values)
       ((and owner-id (.slot? graph 'resolve-module-id))
        (with-catch (lambda (_) target-sym)
                    (lambda () ((.ref graph 'resolve-module-id) owner-id target-sym))))
       (else target-sym)))))

(def (qualify-profiles-table ptable owner-id resolve-mod)
  (if (not (object? ptable))
    (.o)
    (object<-alist
     (map (lambda (dotted-key)
            (let-values (((target-mod target-slot) (parse-dotted-slot-path dotted-key)))
              (if (and target-mod target-slot)
                (let* ((resolved (resolve-mod owner-id target-mod))
                       (new-key (string->symbol
                                 (string-append (symbol->string resolved) "."
                                                (symbol->string target-slot)))))
                  (cons new-key (.ref ptable dotted-key)))
                (cons dotted-key (.ref ptable dotted-key)))))
          (.all-slots ptable)))))

(def (project-graph-convergence-decls graph)
  (let* ((nodes (.ref graph 'nodes))
         (resolve-mod (make-graph-module-resolver graph))
         (core-nodes (filter (lambda (n) (eq? (.ref n 'kind) 'module-core)) nodes))
         (feat-nodes (filter (lambda (n) (eq? (.ref n 'kind) 'feature)) nodes)))
    (map
     (lambda (cnode)
       (let* ((mid (.ref cnode 'identity))
              (pub (.ref cnode 'publication))
              (tags (if (and (object? pub) (.slot? pub 'tags) (list? (.ref pub 'tags)))
                      (.ref pub 'tags) '()))
              (slot-specs (if (and (object? pub) (.slot? pub 'slot-specs) (list? (.ref pub 'slot-specs)))
                            (.ref pub 'slot-specs) '()))
              (defaults (if (and (object? pub) (.slot? pub 'defaults) (object? (.ref pub 'defaults)))
                          (.ref pub 'defaults) (.o)))
              (profiles-table
               (if (and (object? pub) (.slot? pub 'profiles) (object? (.ref pub 'profiles)))
                 (qualify-profiles-table (.ref pub 'profiles) mid resolve-mod)
                 (.o)))
              (governance-floor (if (and (object? pub) (.slot? pub 'governance-floor)
                                         (object? (.ref pub 'governance-floor)))
                                  (.ref pub 'governance-floor) #f))
              (owner-feats
               (filter-map
                (lambda (fnode)
                  (and (eq? (.ref fnode 'owner) mid)
                       (let* ((fid (.ref fnode 'identity))
                              (fid-str (symbol->string fid))
                              (sep (string-rindex fid-str #\/))
                              (fname (if sep
                                       (string->symbol (substring fid-str (+ sep 1) (string-length fid-str)))
                                       fid))
                              (desc (.ref fnode 'descriptor))
                              (prereqs (if (and (object? desc) (.slot? desc 'implied-modules))
                                         (.ref desc 'implied-modules) '()))
                              (reqs (if (and (object? desc) (.slot? desc 'requires))
                                      (.ref desc 'requires) '()))
                              (confs (if (and (object? desc) (.slot? desc 'conflicts))
                                       (.ref desc 'conflicts) '()))
                              (contribs (if (and (object? desc) (.slot? desc 'contributions)
                                                 (object? (.ref desc 'contributions)))
                                          (.ref desc 'contributions) (.o))))
                         (make-feature-decl mid fname
                                            enabled-fn: (feature-enabled-fn-for-prereqs prereqs)
                                            requires: reqs
                                            conflicts: confs
                                            contributions: contribs))))
                feat-nodes)))
         (make-module-decl mid
                           tags: tags
                           slot-specs: slot-specs
                           defaults: defaults
                           features: owner-feats
                           profiles: profiles-table
                           governance-floor: governance-floor)))
     core-nodes)))

(def (collect-publication-profile-catalogs graph)
  (filter-map
   (lambda (n)
     (and (eq? (.ref n 'kind) 'module-core)
          (let ((pub (.ref n 'publication)))
            (and (object? pub)
                 (.slot? pub 'profile-catalog)
                 (object? (.ref pub 'profile-catalog))
                 (.ref pub 'profile-catalog)))))
   (.ref graph 'nodes)))

(def (converge-selected-graph graph
                              global-profile-registry: (global-reg #f)
                              module-profile-registry: (module-reg #f))
  (let* ((decls (project-graph-convergence-decls graph))
         (catalogs (collect-publication-profile-catalogs graph))
         (admitted (.ref graph 'module-order))
         (nodes (.ref graph 'nodes))
         (explicit-feats
          (filter-map
           (lambda (n)
             (and (eq? (.ref n 'kind) 'feature)
                  (or (not (.slot? n 'activation))
                      (eq? (.ref n 'activation) 'explicit))
                  (.ref n 'identity)))
           nodes))
         (vetoed-feats (if (.slot? graph 'denied-features) (.ref graph 'denied-features) '()))
         (gp-names (if (.slot? graph 'global-profiles) (.ref graph 'global-profiles) '()))
         (mp-alist (if (.slot? graph 'module-profiles) (.ref graph 'module-profiles) '()))
         (unresolved-diags '())
         (resolve-mod (make-graph-module-resolver graph))
         (resolved-gp
          (filter-map
           (lambda (sym)
             (let ((val (lookup-profile-symbol sym global-reg catalogs)))
               (if val
                 (make-global-profile
                  (.ref val 'profile-id)
                  (map (lambda (t)
                         (if (and (symbol? t) (not (tag-selector? t)))
                           (resolve-mod #f t)
                           t))
                       (.ref val 'targets))
                  (.ref val 'values))
                 (begin
                   (when (or global-reg (pair? catalogs))
                     (set! unresolved-diags
                           (cons (make-convergence-diagnostic
                                  'unknown-global-profile sym sym 'global-profiles sym
                                  (string-append "Unresolved Global Profile in :profiles: "
                                                 (symbol->string sym)))
                                 unresolved-diags)))
                   #f))))
           gp-names))
         (resolved-mp
          (filter-map
           (lambda (entry)
             (let* ((mid (car entry))
                    (names (cdr entry))
                    (objs
                     (filter-map
                      (lambda (sym)
                        (let ((val (lookup-profile-symbol sym module-reg catalogs)))
                          (if val
                            val
                            (begin
                              (when (or module-reg (pair? catalogs))
                                (set! unresolved-diags
                                      (cons (make-convergence-diagnostic
                                             'unknown-module-profile mid sym 'module-profiles sym
                                             (string-append "Unresolved Module Profile in profiles:: "
                                                            (symbol->string sym)))
                                            unresolved-diags)))
                              #f))))
                      names)))
               (and (pair? objs) (cons mid objs))))
           mp-alist))
         (explicit-flags
          (append (map (lambda (f) (cons f #t)) explicit-feats)
                  (map (lambda (f) (cons f #f)) vetoed-feats)))
         (result
          (converge-assembly decls admitted
                             explicit-flags: explicit-flags
                             global-profiles: resolved-gp
                             module-profiles: resolved-mp))
         (all-diags (append (reverse unresolved-diags) (.ref result 'diagnostics)))
         (loader-receipts (if (.slot? graph 'activation-receipts)
                            (.ref graph 'activation-receipts) '()))
         (combined-receipts (append loader-receipts (.ref result 'receipts))))
    (make-convergence-result
     (if (null? all-diags) (.ref result 'status) 'rejected)
     (.ref result 'admitted-modules)
     (.ref result 'active-features)
     (.ref result 'compiled-closure)
     (.ref result 'effective-configs)
     combined-receipts
     all-diags)))

(def (apply-graph-runtime-overlay graph assembly-result runtime-slot-updates)
  (let* ((decls (project-graph-convergence-decls graph))
         (resolve-mod (make-graph-module-resolver graph))
         (qualified-updates
          (map (lambda (entry) (cons (resolve-mod #f (car entry)) (cdr entry)))
               runtime-slot-updates)))
    (converge-runtime-overlay decls assembly-result qualified-updates)))
