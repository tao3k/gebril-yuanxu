;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Module Core remains mandatory. Internal Core nodes let the existing Feature
;;; resolver check one selected dependency Graph without another ordering policy.
(import (runtime: :clan/poo/object)
        (only-in :clan/poo/object/slot-observation %call-with-recorded-slot-reads)
        (only-in :clan/poo/object/read-projection owned-read-function-scope?)
        (only-in :tao3k/yuanxu/ops/progress current-execution-progress execution-progress!)
        (only-in :tao3k/yuanxu/module-system/graph/funs module-closure)
        (only-in :tao3k/yuanxu/module-system/source/observations
                 call-with-module-source-callback module-source-measure-operation current-module-source-observer)
        (only-in :tao3k/yuanxu/module-system/feature/model feature-descriptor feature-selection feature-profile)
        (only-in :tao3k/yuanxu/module-system/feature/resolver resolve-feature-profile schedule-core-rows)
        (only-in :tao3k/yuanxu/module-system/feature/feature-manifest feature-manifest-bundle)
        (only-in :tao3k/yuanxu/module-system/feature/composition feature-composition-plan)
        (only-in :tao3k/yuanxu/module-system/convergence/types make-activation-receipt))
(export select-module-graph module-feature-declaration module-selected-feature?)

;; One complete value from the EXISTING Feature publisher. Runtime .cc copies
;; direct persistent specifications, never this prototype's evaluated cells.
;; No business module, optional Feature or acceptance result is materialized.
(def runtime-construction-current? object-construction-current?)
(def core-feature-prototype
  ;; A changed constructor or unknown callback at IMPORT time cannot mint a
  ;; trusted template merely by restoring its metadata before the first use.
  (and (owned-read-function-scope?) (runtime-construction-current?)
       (feature-descriptor
         (.o feature-id: 'module-system/:core owner-module-id: 'module-system))))
(def core-feature-reads
  ;; Authenticate the completed FLAT descriptor, whose constants no longer
  ;; depend on the temporary input specification. Its input is not a live
  ;; prototype: feature-descriptor copies it into independent constant slots.
  (if (not core-feature-prototype) '()
    (let-values (((_ reads)
                (%call-with-recorded-slot-reads
                  (lambda ()
                    (for-each (cut .ref core-feature-prototype <>)
                              (.all-slots core-feature-prototype)))
                  unique-roots?: #t)))
      reads)))
(def (core-feature-template-current?)
  (and core-feature-prototype (owned-read-function-scope?) (runtime-construction-current?)
       (with-catch (lambda (_changed-template) #f)
         (lambda () (reobserve-slot-reads! core-feature-reads) #t))))
(def (core-feature-descriptor id owner required)
  (if (core-feature-template-current?)
    (.cc core-feature-prototype feature-id: id owner-module-id: owner
      requires: (map values required))
    ;; Unknown observers/initializers keep the original specification reads
    ;; and constructor effects. Never catch a constructor's own exception.
    (feature-descriptor (.o feature-id: id owner-module-id: owner requires: required))))
(def (core-node-id id)
  ;; ':' cannot occur in an admitted module path or init feature name.
  (string->symbol (string-append (symbol->string id) "/:core")))
(def (feature-node-id owner-id name)
  (string->symbol (string-append (symbol->string owner-id) "/" (symbol->string name))))
;; Find the authored leaf in this selection. Relative leaf names may recur
;; across package windows, so a compiler request must resolve unambiguously.
(def (module-selected-feature? graph leaf feature)
  (def owners
    (filter-map
      (lambda (node)
        (and (eq? (.ref node 'kind) 'module-core)
             (eq? (.ref (.ref node 'publication) 'identity) leaf)
             (.ref node 'identity)))
      (.ref graph 'nodes)))
  (match owners
    ([] #f)
    ([owner] (and (memq (feature-node-id owner feature) (.ref graph 'feature-order)) #t))
    (else (error "Feature request has ambiguous Module leaves" leaf feature owners))))
(def (signed-feature flag)
  (let (text (symbol->string flag))
    (values (string->symbol (substring text 1 (string-length text)))
            (char=? (string-ref text 0) #\+))))
(def (module-feature-index descriptors)
  ;; One derived POO slot index per selected graph, not a per-Module full scan.
  (def owners (make-hash-table-eq))
  (def order '())
  (for-each
    (lambda (descriptor)
      (def owner (.ref descriptor 'owner-module-id))
      (unless (hash-key? owners owner) (set! order (cons owner order)))
      (hash-put! owners owner (cons descriptor (or (hash-get owners owner) '()))))
    descriptors)
  (object<-alist
    (map (lambda (owner) (cons owner (reverse (hash-ref owners owner)))) (reverse order))))

;; Source and compiled publications share the same native Feature defaults.
(def (module-feature-declaration value owner name)
  (if (and (object? value) (not (.slot? value 'kind)))
    (.mix value
      (feature-descriptor
        (.o feature-id: (feature-node-id owner name) owner-module-id: owner)))
    value))

(def (select-module-graph context root-values read-publication current!
                          (imported-owners (lambda (_id) '()))
                          owner-record: (read-owner-record #f))
  (def (module-key owner required)
    (if (.slot? context 'resolve-module-id)
      ((.ref context 'resolve-module-id) owner required) required))
  (def (feature-key owner required)
    (if (not (.slot? context 'resolve-module-id)) required
      (let* ((text (symbol->string required)) (separator (string-rindex text #\/)))
        (unless separator (error "Feature dependency requires an owner and name" required))
        (let* ((owner-name (string->symbol (substring text 0 separator)))
               (declared (.ref (publication-for owner) 'identity))
               (target (if (eq? owner-name declared) owner (module-key owner owner-name))))
          (string->symbol (string-append (symbol->string target)
                            (substring text separator (string-length text))))))))
  (def publications (make-hash-table-eq))
  (def imports (make-hash-table-eq))
  (def (publication-for id)
    (or (hash-get publications id)
        (let (value (read-publication id))
          (hash-put! publications id value)
          value)))
  (let* ((intent (and (.slot? context 'intent) (.ref context 'intent)))
         (decision-values (if intent (.ref intent 'decisions) '()))
         (origin (and (.slot? context 'init-source) (.ref context 'init-source)))
         (explicit? (and intent (eq? (.ref intent 'mode) 'explicit)))
         (selected-index (list->hash-table (map (lambda (id) (cons id #t)) (.ref context 'selected))))
         (denied-index (list->hash-table (map (lambda (id) (cons id #t)) (.ref context 'denied-modules))))
         (modules
          (module-source-measure-operation 'selected-owner-closure
           (lambda () (module-closure root-values identity
           (lambda (id)
             (let (owners
                    (if read-owner-record
                      ;; The Linker supplies both fields from one admitted
                      ;; record without an intervening callback.
                      (let-values (((publication owners) (read-owner-record id)))
                        (hash-put! publications id publication)
                        owners)
                      (begin (publication-for id) (imported-owners id))))
               (for-each
                 (lambda (required)
                   (when (hash-get denied-index required)
                     (error "required module disabled" id required origin (.ref context 'generation)))
                   (when (and explicit? (not (hash-get selected-index required)))
                     (error "required module not explicitly declared" id required origin
                            (.ref context 'generation))))
                 owners)
               (hash-put! imports id owners)
               owners))))))
         (_closure-current (current!))
         (nodes (make-hash-table))
         (decision-index (make-hash-table))
         (negative
          (foldr append '()
           (map (lambda (row)
                  (filter-map
                   (lambda (flag)
                     (let-values (((name enabled?) (signed-feature flag)))
                       (and (not enabled?) (feature-node-id (.ref row 'identity) name))))
                   (.ref (.ref row 'selection) 'selection-flags))) decision-values))))
    (for-each (lambda (row) (hash-put! decision-index (.ref row 'identity) row)) decision-values)
    (def (row-for id)
      (and (hash-key? decision-index id) (hash-ref decision-index id)))
    (def (register-core! key id owners)
      (hash-put! nodes key (.o kind: 'module-core identity: id owner: id
                              publication: (publication-for id) imports: owners)))
    (def (feature-interface owner id name)
      (and (.slot? context 'collect-entrypoint)
           ((.ref context 'collect-entrypoint)
             owner id (list "features" (symbol->string name) "interface.ss"))))
    (def (feature-descriptor-for owner-id name features interface)
        (let* ((declared
                 (if (list? features)
                   (let (publication (publication-for owner-id))
                     (unless interface (error "missing selected Feature interface" owner-id name))
                     (unless (and (.slot? publication 'feature-reader)
                                  (procedure? (.ref publication 'feature-reader)))
                       (error "no source reader for selected Feature" owner-id name))
                     ((.ref publication 'feature-reader) name))
                   (.ref features name)))
               (owner (.ref (publication-for owner-id) 'identity))
               (descriptor-value
                 ;; Interface authors declare native POO values. This owner
                 ;; supplies existing Feature metadata; it does not force the
                 ;; refinement, Contract or component payload while selecting.
                 ;; Explicit descriptors retain their identities and are checked
                 ;; below, including forged owner/identity refusal.
                 (module-feature-declaration declared owner name))
               (id (feature-node-id owner-id name)))
          (unless (and (object? descriptor-value)
                       (andmap (cut .slot? descriptor-value <>)
                               '(kind feature-id owner-module-id requires optional-requires conflicts))
                       (eq? (.ref descriptor-value 'kind) 'feature-descriptor)
                       (eq? (.ref descriptor-value 'feature-id)
                            (feature-node-id (.ref (publication-for owner-id) 'identity) name))
                       (eq? (.ref descriptor-value 'owner-module-id)
                            (.ref (publication-for owner-id) 'identity))
                       (andmap (lambda (slot)
                                 (let (ids (.ref descriptor-value slot))
                                   (and (list? ids) (andmap symbol? ids))))
                               '(requires optional-requires conflicts)))
            (error "invalid published Feature descriptor or owner" owner-id name origin))
          (for-each
           (lambda (slot)
             (for-each
              (lambda (required)
                (when (memv #\: (string->list (symbol->string required)))
                  (error "Feature dependency cannot name Module Core" id required origin)))
              (.ref descriptor-value slot))) '(requires optional-requires conflicts))
          (values
            (if (eq? id (.ref descriptor-value 'feature-id)) descriptor-value
              (.cc descriptor-value 'feature-id id 'owner-module-id owner-id
                'requires (map (cut feature-key owner-id <>) (.ref descriptor-value 'requires))
                'optional-requires (map (cut feature-key owner-id <>) (.ref descriptor-value 'optional-requires))
                'implied-modules (if (.slot? descriptor-value 'implied-modules)
                                   (map (cut module-key owner-id <>) (.ref descriptor-value 'implied-modules))
                                   '())
                'conflicts (map (cut feature-key owner-id <>) (.ref descriptor-value 'conflicts))))
            descriptor-value)))
    (let* ((admitted-set
            (let ((tbl (make-hash-table-eq)))
              (for-each (lambda (id) (hash-put! tbl id #t)) modules)
              (for-each (lambda (id)
                          (unless (hash-get denied-index id)
                            (hash-put! tbl id #t)))
                        (.ref context 'selected))
              tbl))
           (implied-candidates
            (foldr append '()
             (map
              (lambda (owner-id)
                (let* ((publication (publication-for owner-id))
                       (dir-features? (.slot? publication 'feature-reader))
                       (inline-implied? (.slot? publication 'implied-features)))
                  (cond
                   (dir-features?
                    (let ((features (if (.slot? publication 'features)
                                      (.ref publication 'features) '())))
                      (if (and (pair? features) (.slot? context 'feature-implied-modules))
                        (filter-map
                         (lambda (name)
                           (let ((id (feature-node-id owner-id name)))
                             (and (not (memq id negative))
                                  (not (and (row-for owner-id)
                                            (let ((row (row-for owner-id)))
                                              (ormap (lambda (flag)
                                                       (let-values (((fname en?) (signed-feature flag)))
                                                         (and en? (eq? fname name))))
                                                     (.ref (.ref row 'selection) 'selection-flags)))))
                                  (let ((prereqs ((.ref context 'feature-implied-modules) owner-id name)))
                                    (and (pair? prereqs)
                                         (andmap (lambda (req-mod)
                                                   (hash-get admitted-set (module-key owner-id req-mod)))
                                                 prereqs)
                                         (list owner-id name (map (cut module-key owner-id <>) prereqs)))))))
                         features)
                        '())))
                   (inline-implied?
                    (let ((entries (.ref publication 'implied-features)))
                      (if (pair? entries)
                        (filter-map
                         (lambda (entry)
                           (let* ((name (car entry))
                                  (prereqs (cdr entry))
                                  (id (feature-node-id owner-id name)))
                             (and (pair? prereqs)
                                  (not (memq id negative))
                                  (not (and (row-for owner-id)
                                            (let ((row (row-for owner-id)))
                                              (ormap (lambda (flag)
                                                       (let-values (((fname en?) (signed-feature flag)))
                                                         (and en? (eq? fname name))))
                                                     (.ref (.ref row 'selection) 'selection-flags)))))
                                  (andmap (lambda (req-mod)
                                            (hash-get admitted-set (module-key owner-id req-mod)))
                                          prereqs)
                                  (list owner-id name (map (cut module-key owner-id <>) prereqs)))))
                         entries)
                        '())))
                   (else '()))))
              modules)))
           (core-only?
            ;; Decision flags have already been demanded. Inspect the prepared
            ;; values without running an author getter to qualify the shortcut.
            (and (null? implied-candidates)
                 read-owner-record (not (current-module-source-observer))
                 (core-feature-template-current?)
                 (with-catch (lambda (_changed-route) #f)
                   (lambda ()
                     (andmap (lambda (row)
                               (null? (object-cached-value
                                        (object-cached-value row 'selection) 'selection-flags)))
                             decision-values)))))
           (core-selections
            (module-source-measure-operation 'selected-core-projection
             (lambda () (map (lambda (id)
                   (let* ((key (core-node-id id))
                          (owners (hash-ref imports id))
                          (required (map core-node-id owners)))
                     (if core-only?
                       (begin
                         (register-core! key id owners)
                         (cons key required))
                       (let (descriptor-value (core-feature-descriptor key id required))
                         (register-core! key id owners)
                         (feature-selection descriptor-value))))) modules))))
           (explicit-feature-selections
            (foldr append '()
             (map
              (lambda (owner-id)
                (let (row (row-for owner-id))
                  (if (not row) '()
                    (filter-map
                     (lambda (flag)
                       (let-values (((name enabled?) (signed-feature flag)))
                         ;; Negative decisions validate the name, but do not force
                         ;; its descriptor or contribution payload.
                         (let* ((id (feature-node-id owner-id name))
                               (publication (publication-for owner-id))
                               (features (if (.slot? publication 'features)
                                           (.ref publication 'features) '())))
                           (unless (if (list? features) (memq name features) (.slot? features name))
                             (error "unknown init feature" owner-id name origin (.ref context 'generation)))
                           (if enabled?
                             (let* ((listed? (list? features))
                                    (source (and listed? (feature-interface owner-id id name))))
                               (let-values (((descriptor-value declaration)
                                             (feature-descriptor-for owner-id name features source)))
                                 (def interface (if listed? source (feature-interface owner-id id name)))
                                 (hash-put! nodes id (.o kind: 'feature identity: id owner: owner-id interface
                                                        activation: 'explicit
                                                        declaration descriptor: descriptor-value))
                                 (feature-selection
                                  (.+ descriptor-value
                                      (.o requires: (cons (core-node-id owner-id) (.ref descriptor-value 'requires)))))))
                             #f))))
                     (.ref (.ref row 'selection) 'selection-flags)))))
              ;; Independent Features follow init declaration order, not DFS or
              ;; publication slot enumeration order. Dependencies still win.
              ;; The closure populated publications for each visited Module.
              (if core-only? '()
                (filter (lambda (id) (hash-key? publications id))
                        (map (cut .ref <> 'identity) decision-values))))))
           (implied-feature-selections
            (if core-only? '()
              (map
               (lambda (entry)
                 (let* ((owner-id (car entry))
                        (name (cadr entry))
                        (prereqs (caddr entry))
                        (id (feature-node-id owner-id name))
                        (publication (publication-for owner-id))
                        (features (.ref publication 'features))
                        (interface (feature-interface owner-id id name)))
                   (let-values (((descriptor-value declaration)
                                 (feature-descriptor-for owner-id name features interface)))
                     (hash-put! nodes id (.o kind: 'feature identity: id owner: owner-id interface
                                            activation: 'implied
                                            implied-prereqs: prereqs
                                            declaration descriptor: descriptor-value))
                     (feature-selection
                      (.+ descriptor-value
                          (.o requires: (cons (core-node-id owner-id) (.ref descriptor-value 'requires))))))))
               implied-candidates)))
           (feature-selections (append explicit-feature-selections implied-feature-selections))
           (resolution (module-source-measure-operation 'selected-topological-resolution
                         (lambda ()
                           (if core-only?
                             (let-values (((order cycle-diagnostics)
                                           (module-source-measure-operation 'selected-core-rows
                                             (lambda () (schedule-core-rows core-selections)))))
                               (.o status: (if (null? cycle-diagnostics) 'ready 'rejected)
                                   feature-ids: order diagnostics: cycle-diagnostics))
                             (resolve-feature-profile
                               (feature-profile 'module-selection (append core-selections feature-selections)))))))
           (diagnostics (.ref resolution 'diagnostics)))
      (unless (eq? (.ref resolution 'status) 'ready)
        (error "selected Graph rejected" origin (.ref context 'generation)
               (map (lambda (diagnostic)
                      (let* ((id (.ref diagnostic 'feature-id))
                             (required (.ref diagnostic 'related-id)))
                        (list (cons 'code (.ref diagnostic 'code))
                              (cons 'requester (if (hash-key? nodes id)
                                                 (.ref (hash-ref nodes id) 'identity) id))
                              (cons 'required (if (hash-key? nodes required)
                                                (.ref (hash-ref nodes required) 'identity) required))
                              (cons 'denied? (and (memq required negative) #t))
                              (cons 'detail (.ref diagnostic 'detail))))) diagnostics)))
      (let ((ordered (map (cut hash-ref nodes <>) (.ref resolution 'feature-ids))))
        ;; Report completed topology before revalidating sources so the
        ;; progress hook cannot leave an unchecked publication.
        (when (pair? (current-execution-progress))
          (call-with-module-source-callback
            (lambda () (execution-progress! 'selected-topology (length ordered)))))
        ;; Slot evaluation above can run author code. Never publish the candidate
        ;; on the strength of an earlier source check.
        (current!)
        (.o admit-current: current! status: 'ready generation: (.ref context 'generation) init-source: origin
            resolve-module-id: module-key
            roots: root-values decisions: decision-values denied-modules: (.ref context 'denied-modules)
            denied-features: negative
            global-profiles:
            (if (and intent (.slot? intent 'global-profiles))
              (.ref intent 'global-profiles) '())
            module-profiles:
            (filter-map
             (lambda (row)
               (and (.slot? row 'profiles)
                    (let ((ps (.ref row 'profiles)))
                      (and (pair? ps) (cons (.ref row 'identity) ps)))))
             decision-values)
            activation-receipts:
            (let ((g-profiles (if (and intent (.slot? intent 'global-profiles))
                                (.ref intent 'global-profiles) '()))
                  (m-profiles
                   (filter-map
                    (lambda (row)
                      (and (.slot? row 'profiles)
                           (let ((ps (.ref row 'profiles)))
                             (and (pair? ps) (cons (.ref row 'identity) ps)))))
                    decision-values)))
              (append
               (map (lambda (node)
                      (let ((id (.ref node 'identity)))
                        (cond
                         ((eq? (.ref node 'kind) 'module-core)
                          (make-activation-receipt
                           id 'core-defaults 'assembly 'explicit '()
                           "Admitted module core in yuanxu! closure"))
                         ((and (.slot? node 'activation)
                               (eq? (.ref node 'activation) 'implied))
                          (let ((prereqs (if (.slot? node 'implied-prereqs)
                                           (.ref node 'implied-prereqs) '())))
                            (make-activation-receipt
                             id 'implied-bridge 'assembly 'implied
                             (map (lambda (m) (list m 'enabled? #t)) prereqs)
                             "Auto-bridged via implied-modules in yuanxu! closure")))
                         (else
                          (make-activation-receipt
                           id 'explicit-feature 'assembly 'explicit '()
                           "Explicit +feature selected in yuanxu!")))))
                    ordered)
               (map (lambda (fid)
                      (make-activation-receipt
                       fid 'module-profiles 'assembly 'vetoed '()
                       "Explicit -feature veto in Band 4b"))
                    negative)
               (map (lambda (gp)
                      (make-activation-receipt
                       gp 'global-profiles 'assembly 'explicit '()
                       "Global Profile declared in yuanxu! :profiles"))
                    g-profiles)
               (foldr append '()
                      (map (lambda (entry)
                             (map (lambda (mp)
                                    (make-activation-receipt
                                     (list (car entry) mp) 'module-profiles 'assembly 'explicit '()
                                     "Per-module Profile declared in yuanxu! profiles:"))
                                  (cdr entry)))
                           m-profiles))))
            nodes: ordered
            features-by-owner: (module-feature-index feature-descriptors)
            module-order: (map (cut .ref <> 'identity)
                               (filter (lambda (node) (eq? (.ref node 'kind) 'module-core)) ordered))
            feature-order: (map (cut .ref <> 'identity)
                                (filter (lambda (node) (eq? (.ref node 'kind) 'feature)) ordered))
            implied-features: (map (cut .ref <> 'identity)
                                   (filter (lambda (node)
                                             (and (eq? (.ref node 'kind) 'feature)
                                                  (.slot? node 'activation)
                                                  (eq? (.ref node 'activation) 'implied)))
                                           ordered))
            feature-contributions:
            (begin
              (current!)
              (let (value (feature-composition-plan
                           (feature-manifest-bundle 'module-selection feature-descriptors)))
                (current!) value))
            feature-descriptors:
            (map (cut .ref <> 'descriptor)
                 (filter (lambda (node) (eq? (.ref node 'kind) 'feature)) ordered)))))))
