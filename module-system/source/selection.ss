;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Module Core remains mandatory. Internal Core nodes let the existing Feature
;;; resolver check one selected dependency Graph without another ordering policy.
(import (runtime: :clan/poo/object)
        (only-in :clan/poo/slot-layout make-slot-cache)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads)
        (only-in :yuanxu/object-family/read-projection owned-read-function-scope?)
        (only-in :yuanxu/module-system/graph/funs module-closure)
        (only-in :yuanxu/module-system/source/observations module-source-measure-operation)
        (only-in :yuanxu/module-system/feature/model feature-descriptor feature-selection feature-profile)
        (only-in :yuanxu/module-system/feature/resolver resolve-feature-profile)
        (only-in :yuanxu/module-system/feature/feature-manifest feature-manifest-bundle)
        (only-in :yuanxu/module-system/feature/composition feature-composition-plan))
(export select-module-graph)

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
(def (core-feature-descriptor id owner required)
  (def closed?
    (and core-feature-prototype (owned-read-function-scope?) (runtime-construction-current?)
         (with-catch (lambda (_changed-template) #f)
           (lambda () (reobserve-slot-reads! core-feature-reads) #t))))
  (if closed?
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

(def (select-module-graph context root-values read-publication current!
                          (read-dependencies #f))
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
  ;; Candidate-owned sites cannot retain its last publication in a global root.
  ;; Runtime shared shapes remain reusable; optional payloads stay demand-filled.
  (def publication-core-site (make-slot-cache 'core))
  (def core-requires-site (make-slot-cache 'requires))
  ;; Resolve each selected declaration once for this candidate Graph. Reuse the
  ;; actual publication object for Core/Feature edges, not a source observation
  ;; or an admission result across declaration expansion/initialization.
  (def publications (make-hash-table-eq))
  (def (publication-for id)
    (if (hash-key? publications id) (hash-ref publications id)
      (let (value (read-publication id))
        (hash-put! publications id value) value)))
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
             (let (required-ids
                    (if read-dependencies
                      (call-with-values (lambda () (read-dependencies id))
                        (lambda (value ids)
                          ;; Populate the SAME publication index as the normal
                          ;; reader. Core/Feature resolution must not reread it.
                          (hash-put! publications id value)
                          ids))
                      (let (requirements (.ref/inline
                              (.ref/inline (publication-for id) publication-core-site)
                              core-requires-site))
                        (map (lambda (alias) (.ref (.ref requirements alias) 'module-id))
                             (.all-slots requirements)))))
               (map (lambda (reference)
                      (def required (module-key id reference))
                      (when (hash-get denied-index required)
                        (error "required module disabled" id required origin (.ref context 'generation)))
                      (when (and explicit? (not (hash-get selected-index required)))
                        (error "required module not explicitly declared" id required origin
                               (.ref context 'generation)))
                      required)
                    required-ids)))))))
         ;; Dependency projection can leave a private candidate pending. Close
         ;; it BEFORE decision slots, Feature construction or any open resolver
         ;; callback. Generic readers keep their independent publication tails.
         (_closure-current (when read-dependencies (current!)))
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
                 (if (and (object? declared) (not (.slot? declared 'kind)))
                   (.mix declared
                     (feature-descriptor
                       (.o feature-id: (feature-node-id owner name) owner-module-id: owner)))
                   declared))
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
          (if (eq? id (.ref descriptor-value 'feature-id)) descriptor-value
            (.cc descriptor-value 'feature-id id 'owner-module-id owner-id
              'requires (map (cut feature-key owner-id <>) (.ref descriptor-value 'requires))
              'optional-requires (map (cut feature-key owner-id <>) (.ref descriptor-value 'optional-requires))
              'conflicts (map (cut feature-key owner-id <>) (.ref descriptor-value 'conflicts))))))
    (let* ((core-selections
            (module-source-measure-operation 'selected-core-projection
             (lambda () (map (lambda (id)
                   (let* ((key (core-node-id id))
                          (requirements (.ref/inline
                            (.ref/inline (publication-for id) publication-core-site)
                            core-requires-site))
                          (required (map (lambda (alias)
                                           (core-node-id (module-key id (.ref (.ref requirements alias) 'module-id))))
                                         (.all-slots requirements)))
                          (descriptor-value (core-feature-descriptor key id required)))
                     (hash-put! nodes key (.o kind: 'module-core identity: id owner: id
                                             publication: (publication-for id)))
                     (feature-selection descriptor-value))) modules))))
           (feature-selections
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
                         (let ((id (feature-node-id owner-id name))
                               (features (.ref (publication-for owner-id) 'features)))
                           (unless (if (list? features) (memq name features) (.slot? features name))
                             (error "unknown init feature" owner-id name origin (.ref context 'generation)))
                           (if enabled?
                             (let* ((listed? (list? features))
                                    (source (and listed? (feature-interface owner-id id name)))
                                    (descriptor-value (feature-descriptor-for owner-id name features source))
                                    (interface (if listed? source (feature-interface owner-id id name))))
                               (hash-put! nodes id (.o kind: 'feature identity: id owner: owner-id interface
                                                      descriptor: descriptor-value))
                               (feature-selection
                                (.+ descriptor-value
                                    (.o requires: (cons (core-node-id owner-id) (.ref descriptor-value 'requires))))))
                             #f))))
                     (.ref (.ref row 'selection) 'selection-flags)))))
              ;; Independent Features follow init declaration order, not DFS or
              ;; publication slot enumeration order. Dependencies still win.
              ;; The closure populated publications for each visited Module.
              (filter (lambda (id) (hash-key? publications id))
                      (map (cut .ref <> 'identity) decision-values)))))
           (resolution (module-source-measure-operation 'selected-topological-resolution
                         (lambda () (resolve-feature-profile
                           (feature-profile 'module-selection (append core-selections feature-selections))))))
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
      (let (ordered (map (cut hash-ref nodes <>) (.ref resolution 'feature-ids)))
        ;; Slot evaluation above can run author code. Never publish the candidate
        ;; on the strength of an earlier source check.
        (current!)
        (.o admit-current: current! status: 'ready generation: (.ref context 'generation) init-source: origin
            resolve-module-id: module-key
            roots: root-values decisions: decision-values denied-modules: (.ref context 'denied-modules)
            denied-features: negative
            nodes: ordered
            features-by-owner: (module-feature-index feature-descriptors)
            module-order: (map (cut .ref <> 'identity)
                               (filter (lambda (node) (eq? (.ref node 'kind) 'module-core)) ordered))
            feature-order: (map (cut .ref <> 'identity)
                                (filter (lambda (node) (eq? (.ref node 'kind) 'feature)) ordered))
            feature-contributions:
            (begin
              (current!)
              (let (value (feature-composition-plan
                           (feature-manifest-bundle 'module-selection feature-descriptors)))
                (current!) value))
            feature-descriptors:
            (map (cut .ref <> 'descriptor)
                 (filter (lambda (node) (eq? (.ref node 'kind) 'feature)) ordered)))))))
