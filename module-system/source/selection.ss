;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Module Core remains mandatory. Internal Core nodes let the existing Feature
;;; resolver check one selected dependency Graph without another ordering policy.
(import (only-in :clan/poo/object .o .+ .ref .slot? .all-slots object?)
        (only-in :core/module-system/graph/funs module-closure)
        (only-in :core/feature-system/model feature-descriptor feature-selection feature-profile)
        (only-in :core/feature-system/resolver resolve-feature-profile)
        (only-in :core/feature-system/feature-manifest feature-manifest-bundle)
        (only-in :core/feature-system/composition feature-composition-plan))
(export select-module-graph)
(def (core-node-id id)
  ;; ':' cannot occur in an admitted module path or init feature name.
  (string->symbol (string-append (symbol->string id) "/:core")))
(def (feature-node-id owner-id name)
  (string->symbol (string-append (symbol->string owner-id) "/" (symbol->string name))))
(def (signed-feature flag)
  (let (text (symbol->string flag))
    (values (string->symbol (substring text 1 (string-length text)))
            (char=? (string-ref text 0) #\+))))
(def (select-module-graph context root-values publication-for current!)
  (let* ((intent (and (.slot? context 'intent) (.ref context 'intent)))
         (decision-values (if intent (.ref intent 'decisions) '()))
         (origin (and (.slot? context 'init-source) (.ref context 'init-source)))
         (modules
          (module-closure root-values identity
           (lambda (id)
             (let (requirements (.ref (.ref (publication-for id) 'core) 'requires))
               (map (lambda (alias)
                       (let (required (.ref (.ref requirements alias) 'module-id))
                         (when (memq required (.ref context 'denied-modules))
                           (error "required module disabled" id required origin (.ref context 'generation)))
                         required))
                    (.all-slots requirements))))))
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
    (def (feature-descriptor-for owner-id name)
      (let (features (.ref (publication-for owner-id) 'features))
        (unless (.slot? features name)
          (error "unknown init feature" owner-id name origin (.ref context 'generation)))
        (let* ((descriptor-value (.ref features name)) (id (feature-node-id owner-id name)))
          (unless (and (object? descriptor-value)
                       (andmap (cut .slot? descriptor-value <>)
                               '(kind feature-id owner-module-id requires optional-requires conflicts))
                       (eq? (.ref descriptor-value 'kind) 'feature-descriptor)
                       (eq? (.ref descriptor-value 'feature-id) id)
                       (eq? (.ref descriptor-value 'owner-module-id) owner-id)
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
          descriptor-value)))
    (let* ((core-selections
            (map (lambda (id)
                   (let* ((key (core-node-id id))
                          (requirements (.ref (.ref (publication-for id) 'core) 'requires))
                          (required (map (lambda (alias)
                                           (core-node-id (.ref (.ref requirements alias) 'module-id)))
                                         (.all-slots requirements)))
                          (descriptor-value (feature-descriptor
                                       (.o feature-id: key owner-module-id: id requires: required))))
                     (hash-put! nodes key (.o kind: 'module-core identity: id owner: id
                                             publication: (publication-for id)))
                     (feature-selection descriptor-value))) modules))
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
                         (unless (.slot? (.ref (publication-for owner-id) 'features) name)
                           (error "unknown init feature" owner-id name origin (.ref context 'generation)))
                         (let (id (feature-node-id owner-id name))
                           (if enabled?
                             (let (descriptor-value (feature-descriptor-for owner-id name))
                               (hash-put! nodes id (.o kind: 'feature identity: id owner: owner-id
                                                      descriptor: descriptor-value))
                               (feature-selection
                                (.+ descriptor-value
                                    (.o requires: (cons (core-node-id owner-id) (.ref descriptor-value 'requires))))))
                             #f))))
                     (.ref (.ref row 'selection) 'selection-flags)))))
              ;; Independent Features follow init declaration order, not DFS or
              ;; publication slot enumeration order. Dependencies still win.
              (filter (lambda (id) (memq id modules))
                      (map (cut .ref <> 'identity) decision-values)))))
           (resolution (resolve-feature-profile
                        (feature-profile 'module-selection (append core-selections feature-selections))))
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
        (.o admit-current: current! status: 'ready generation: (.ref context 'generation) init-source: origin
            roots: root-values decisions: decision-values denied-modules: (.ref context 'denied-modules)
            denied-features: negative
            nodes: ordered
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
