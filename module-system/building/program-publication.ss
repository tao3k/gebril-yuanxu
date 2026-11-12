;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Compiler projection of the admitted selection; no business scope execution.
(import (only-in :tao3k/yuanxu/module-system/source/preparation yuanxu-prepare-module-retained-source module-compiler-init-forms)
        (runtime: :clan/poo/object)
        (only-in :std/list/list find delete-duplicates/hash)
        (only-in :tao3k/yuanxu/module-system/source/deferred-declaration module-binding-action)
        (only-in :tao3k/yuanxu/module-system/source/observations module-source-read))
(export project-program-init init-compiler-forms)

(def (project-program-init view build entry)
  (def context (and (.slot? view 'context) (.ref view 'context)))
  (if (or (not context) (not (equal? (.ref entry 'path) (.ref context 'init-source)))) entry
    (let* ((input (.ref entry 'input))
           (graph (.ref build 'selected-graph))
           (ids (.ref graph 'module-order))
           (nodes (.ref graph 'nodes))
           (inputs (.ref build 'entries))
           (aliases (make-hash-table))
           (imports '()))
      (def (current!)
        ((.ref input 'admit-current))
        ((.ref build 'compiler-current)))
      (current!)
      (def (role-value input binding)
        (def identity (.ref input 'compiler-identity))
        (def key (cons identity binding))
        (or (hash-get aliases key)
          ;; These imports and references are serialized together in a private
          ;; compiler input. An uninterned symbol loses identity on read-back
          ;; and makes an unchanged source view differ on each build.
          (let (name (string->symbol (string-append "%yuanxu-publication-"
                                       (number->string (hash-length aliases)))))
            (hash-put! aliases key name)
            ;; This value import is the runtime edge to the publication.
            (set! imports (cons (list identity (.ref input 'path) binding name) imports))
            name)))
      (def (publication-input id)
        (def entry (find (lambda (entry)
                          (and (eq? (.ref entry 'kind) 'publication)
                               (eq? (.ref entry 'owner) id))) inputs))
        (unless entry (error "compiled init is missing its selected publication" id))
        (.ref entry 'input))
      (def (feature-value owner declared-owner name publication)
        (def id (string->symbol (string-append (symbol->string owner) "/" (symbol->string name))))
        (def node (find (lambda (node) (and (eq? (.ref node 'kind) 'feature)
                                          (eq? (.ref node 'identity) id))) nodes))
        (if (not node)
          `(error "Feature is outside compiled selection" ',id)
          (let* ((path (.ref node 'interface))
                 (entry (and path (find (lambda (entry) (equal? (.ref entry 'path) path)) inputs)))
                 (value (if path
                          (begin
                            (unless entry (error "compiled init is missing selected Feature input" id))
                            (role-value (.ref entry 'input) 'Feature))
                          `(.ref (.ref ,publication 'features) ',name)))
                 (descriptor (.ref node 'descriptor))
                 (declaration (.ref node 'declaration))
                 (expected (map (lambda (key) (cons key (.ref declaration key)))
                                '(kind feature-id owner-module-id requires optional-requires conflicts))))
            `(module-program-feature ,value ',declared-owner ',name ',expected ',id ',owner
               ',(map (lambda (key) (.ref descriptor key))
                      '(requires optional-requires conflicts))))))
      (def publications
        (map (lambda (id)
               (def node (find (lambda (node) (and (eq? (.ref node 'kind) 'module-core)
                                                 (eq? (.ref node 'identity) id))) nodes))
               (def original (.ref node 'publication))
               (def prepared (publication-input id))
               (def value (role-value prepared (.ref prepared 'binding)))
               (def features (.ref original 'features))
               (def names (if (list? features) features (.all-slots features)))
               `(,id (.o declaration: ',(.ref original 'identity)
                         publication: ,value
                         features: (.o ,@(map (lambda (name)
                                               `(,name ,(feature-value id (.ref original 'identity) name value))) names))))) ids))
      (def resolutions
        (map (lambda (id)
               (def node (find (lambda (node) (and (eq? (.ref node 'kind) 'module-core)
                                                 (eq? (.ref node 'identity) id))) nodes))
               (def requires (.ref (.ref (.ref node 'publication) 'core) 'requires))
               `(,id (.o ,@(map (lambda (reference)
                                 `(,reference ',((.ref graph 'resolve-module-id) id reference)))
                               (delete-duplicates/hash
                                 (map (lambda (alias) (.ref (.ref requires alias) 'module-id))
                                      (.all-slots requires))))))) ids))
      (def decisions
        (filter-map (lambda (row)
                      (and (memq (.ref row 'identity) ids)
                           (cons (.ref row 'identity)
                                 (.ref (.ref row 'selection) 'selection-flags))))
                    (.ref graph 'decisions)))
      (def (flatten namespace (prefix '()))
        (def names (.all-slots namespace))
        ;; A named empty namespace remains addressable in a compiled init.
        (if (and (null? names) (pair? prefix))
          (list (cons prefix #f))
          (foldr append '()
            (map (lambda (name)
                   (def path (append prefix (list name)))
                   (def value (.ref namespace name))
                   (if (symbol? value)
                     (if (memq value ids) (list (cons path value)) '())
                     (flatten value path))) names))))
      (def namespace
        (and (.slot? context 'namespace) ((.ref context 'namespace) identity)))
      (def rows
        (if namespace (flatten namespace)
          (map (lambda (id)
                 (cons (map string->symbol (string-split (symbol->string id) #\/)) id)) ids)))
      (def forms (call-with-input-string (module-source-read (.ref entry 'path)) read-all))
      (def declaration (find (lambda (form) (and (pair? form) (eq? (car form) 'yuanxu!))) forms))
      (unless declaration (error "compiled init has no admitted declaration" (.ref entry 'path)))
      (def original-forms (.ref input 'compiler-forms))
      ;; Headers are native compiler data, and remain unchanged. Replace only
      ;; the retained body include with the compiler-owned init publication.
      (def headers
        (let loop ((forms original-forms) (headers '()))
          (if (and (pair? forms) (keyword? (car forms)) (pair? (cdr forms)))
            (loop (cddr forms) (cons (cadr forms) (cons (car forms) headers)))
            (reverse headers))))
      (def emitted
        (append headers
          `((import (only-in :clan/poo/object .o .cc .ref)
                    (only-in :tao3k/yuanxu/module-system/source/link module-program-namespace module-program-feature)
                    (only-in :tao3k/yuanxu/module-system/selection/init-expansion expand-yuanxu-program-declaration)
                    ,@(map (lambda (row)
                              `(rename-in (only-in ,(cadr row) ,(caddr row))
                                 (,(caddr row) ,(cadddr row))))
                            (reverse imports)))
            (expand-yuanxu-program-declaration ,declaration ,(.ref entry 'path)
              (lambda ()
                (module-program-namespace ',(.ref input 'compiler-identity)
                  (.o ,@publications) (.o ,@resolutions) ',decisions ',rows))))))
      (current!)
      (.cc entry 'kind 'init-publication
        'input (.cc input 'compiler-forms emitted 'admit-current current!)))))

;; Both explicit publication and the official compiler use this same lowering.
(def (init-compiler-forms path)
  (or (module-compiler-init-forms path)
      (let* ((select (module-binding-action "tao3k/yuanxu/module-system/source/link" 'yuanxu-load-modules))
             (view (select (list path)))
             (graph (.get view build-graph))
             (input (yuanxu-prepare-module-retained-source path void))
             (entry (.o path input kind: 'source compiler-identity: (.get input compiler-identity)
                        options: '())))
        (.get (project-program-init view graph entry) input compiler-forms))))
