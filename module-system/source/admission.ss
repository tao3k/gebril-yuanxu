;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Shared source-role and publication admission. No expansion or activation.
(import (only-in :clan/poo/object .o .ref)
        (only-in :core/module-system/source/role-forms poo-flow-module-allowed-entrypoint-roles)
        (only-in :std/list/list any)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :core/types poo-flow-contract-admit poo-flow-validation-evidence-accepted?)
        :core/module-system/source/objects
        :core/module-system/source/publication
        (only-in :core/module-system/source/interface poo-flow-module-interface)
        (only-in :core/module-system/authoring/import-policy
                 SourceInspectionPolicy. poo-flow-module-owner-import-datum-observations)
        (only-in :core/module-system/authoring/admission
                 poo-flow-module-authoring-admit-port
                 poo-flow-module-authoring-admission-accepted?
                 poo-flow-module-authoring-admission-diagnostics)
        (only-in :core/module-system/authoring/roles poo-flow-default-module-authoring-profile))
(export poo-flow-module-required-role-files poo-flow-module-allowed-entrypoint-roles
        poo-flow-module-style-policy-prototype poo-flow-default-module-style-policy
        module-source-type module-source-read module-source-name? module-source-admit-current!
        call-with-module-source-read-cache call-with-module-source-fresh-reads
        call-with-collected-module-sources
        module-source-observe current-module-source-observer current-module-source-phase
        admit-module-value! admit-module-publication!)

(def poo-flow-module-required-role-files '("types.ss" "objects.ss" "config.ss" "interface.ss"))

(def (module-source-name? name)
  (and (string? name) (> (string-length name) 0)
       (not (member name '("." "..")))
       (andmap (lambda (c) (not (memv c '(#\/ #\\ #\:)))) (string->list name))))

(def current-module-source-observer (make-parameter #f))
;; Observer keys remain numeric counters: symbols for totals, or
;; (file-request/file-read phase path) for attribution. No observer, no path keys.
(def current-module-source-phase (make-parameter 'source))
(def (observe-source kind (amount 1))
  (when (current-module-source-observer)
    ((current-module-source-observer) kind amount)))
(def (module-source-type path)
  (module-source-observe read-module-source-type path))
(def (read-module-source-type path)
  (observe-source 'stats)
  (with-catch (lambda (_exception) #f)
              (lambda () (file-info-type (file-info path #f)))))
;; A reader validation is synchronous and effect-free. Reuse bytes and file-kind
;; observations only inside that boundary; every read requires regular-file
;; status. No cache survives an effect or an independent currentness call.
(def source-read-cache (make-parameter #f))
(def (call-with-module-source-fresh-reads thunk)
  ;; Admission is an authority boundary even when a caller has an outer pure
  ;; observation window. Restore that window afterwards; never inherit its bytes.
  (parameterize ((source-read-cache #f)) (thunk)))
(def (call-with-module-source-read-cache thunk)
  (observe-source 'checks)
  ;; Nested pure source guards share the outer validation's observations. The
  ;; owner MUST end this scope before expansion, writes or external effects.
  (cond
   ((source-read-cache) (thunk))
   ((not (current-module-source-observer))
    (parameterize ((source-read-cache (make-hash-table))) (thunk)))
   (else
    (let (started (real-time))
      (dynamic-wind void
        (lambda () (parameterize ((source-read-cache (make-hash-table))) (thunk)))
        (lambda () (observe-source 'check-seconds (- (real-time) started))))))))
(def (module-source-observe query . arguments)
  ;; Pure observations only, within the same validation boundary as file bytes.
  (let (cache (source-read-cache))
    (if cache
      (let (key (cons query arguments))
        (if (hash-key? cache key)
          (begin (observe-source 'query-hits) (hash-ref cache key))
          (let (value (apply query arguments))
            (observe-source 'query-misses)
            (hash-put! cache key value) value)))
      (apply query arguments))))
(def (observe-read-request path)
  (observe-source 'read-requests)
  (when (current-module-source-observer)
    (observe-source (list 'file-request (current-module-source-phase) path))))
(def (observe-read path)
  (observe-source 'reads)
  (when (current-module-source-observer)
    (observe-source (list 'file-read (current-module-source-phase) path))))
(def (module-source-read path)
  (observe-read-request path)
  (unless (eq? (module-source-type path) 'regular)
    (error "module role must be a regular file" path))
  (let (cache (source-read-cache))
    (if (and cache (hash-key? cache path)) (hash-ref cache path)
      (let (text (begin (observe-read path)
                       (call-with-input-file path read-all-as-string)))
        (when cache (hash-put! cache path text))
        text))))

;; Private per-admission observations; neither a field table nor a global log.
(defstruct source-observation (input message) final: #t)
(def source-collectors (make-parameter '()))
(def (check-source-current! entry message)
  (unless (if (cdr entry)
            (and (eq? (module-source-type (car entry)) 'regular)
                 (equal? (cdr entry) (module-source-read (car entry))))
            (not (module-source-type (car entry))))
    (error message (car entry))))
(def (call-with-collected-module-sources consume)
  (def by-path (make-hash-table))
  (def observed '())
  (def (collect! entry message)
    (def previous (or (hash-get by-path (car entry)) '()))
    ;; De-duplicate matching revisions without hashing whole source texts or
    ;; replacing an earlier revision of the same path with a later one.
    (unless (any (lambda (item)
                   (equal? (cdr (source-observation-input item)) (cdr entry))) previous)
      (let* ((input (cons (string-copy (car entry))
                         (and (cdr entry) (string-copy (cdr entry)))))
             (item (make-source-observation input message)))
        (hash-put! by-path (car input) (cons item previous))
        (set! observed (cons item observed)))))
  (def (current!)
    ;; No candidate traversal, and no re-reporting a replay into an outer scope.
    ;; Only actual admission checks enroll observations, not this final pass.
    (call-with-module-source-fresh-reads
      (lambda ()
        (for-each
          (lambda (item)
            (check-source-current! (source-observation-input item)
                                  (source-observation-message item)))
          (reverse observed)))))
  (parameterize ((source-collectors (cons collect! (source-collectors))))
    (consume current!)))
(def (module-source-admit-current! observations
        (message "stale selected build input; regenerate the build entry"))
  ;; One authority for JSON, native slot sources and publication guards. Nested
  ;; admission contributes observations to every active enclosing scope.
  (for-each
    (lambda (entry)
      (check-source-current! entry message)
      (for-each (lambda (collect!) (collect! entry message)) (source-collectors)))
    observations))

(def (poo-flow-module-role-reference? datum module-name role)
  (let ((leaf (string-append role ".ss"))
        (relative (string-append "./" role))
        (suffix (string-append "/" (if (symbol? module-name) (symbol->string module-name) module-name) "/" role)))
    (cond
     ((symbol? datum)
      (let (reference (symbol->string datum))
        (or (string=? reference relative)
            (string-suffix? suffix reference))))
     ((string? datum)
      (or (string=? datum leaf) (string-suffix? suffix datum)))
     ((pair? datum)
      (or (poo-flow-module-role-reference? (car datum) module-name role)
          (poo-flow-module-role-reference? (cdr datum) module-name role)))
     ((vector? datum)
      (poo-flow-module-role-reference? (vector->list datum) module-name role))
     (else #f))))

(def (poo-flow-module-top-form-references-role? datums head module-name role)
  (and (any (lambda (form)
              (and (pair? form)
                   (eq? (car form) head)
                   (poo-flow-module-role-reference?
                    (cdr form) module-name role)))
            datums)
       #t))

(def (poo-flow-module-dependency-direction-validate! module-name module-root reader)
  (let ((layers '((types objects func config interface build)
                  (func objects config interface build)
                  (objects config interface build)
                  (config interface build)
                  (interface build))))
    (for-each
     (lambda (layer)
       (let* ((source-role (car layer))
              (path (path-expand
                     (string-append (symbol->string source-role) ".ss")
                     module-root)))
         (when (reader path #f)
           (let (datums (call-with-input-string (reader path) read-all))
             (for-each
              (lambda (forbidden-role)
                (when (poo-flow-module-top-form-references-role?
                       datums 'import module-name
                       (symbol->string forbidden-role))
                  (error "POO-FLOW-MODULE-E007 reversed module role dependency"
                         module-name source-role forbidden-role)))
              (cdr layer))))))
     layers)))

;;; The loader applies the Interface-owned authoring Profile to each stable
;;; role before exposing any entrypoint.  Admission reads inert datums only;
;;; it neither expands nor evaluates module source.
(def (poo-flow-module-role-authoring-validate! policy module-name module-root reader)
  (let* ((authoring (.ref policy 'authoring))
         (interface
          (poo-flow-module-interface
           (if (symbol? module-name) (symbol->string module-name) module-name) (.o)
           (list (cons 'module-root module-root))
           authoring: authoring)))
    (for-each
     (lambda (role)
       (let* ((path
               (path-expand
                (string-append (symbol->string role) ".ss") module-root))
              (admission
               (call-with-input-string
                (reader path)
                (lambda (port)
                  (poo-flow-module-authoring-admit-port
                   interface (if (eq? role 'func) 'funs role) port)))))
         (unless (poo-flow-module-authoring-admission-accepted? admission)
           (error "POO-FLOW-MODULE-E009 role violates Interface authoring Contract"
                  module-name role path
                  (car (poo-flow-module-authoring-admission-diagnostics
                        admission))))))
     (filter
      (lambda (role)
        (reader (path-expand (string-append (symbol->string role) ".ss") module-root) #f))
      '(types objects func config interface build)))))


(def (poo-flow-module-source-admit! policy module-name module-root reader)
  (unless (eq? (module-source-type module-root) 'directory)
    (error "module source must be a directory" module-name module-root))
  (when (file-exists? (path-expand "init.ss" module-root))
    (error "POO-FLOW-MODULE-E005 init.ss belongs to the selection root" module-name))
  ;; Read each selected role once. The caller may record these exact bytes in
  ;; its generation; all checks consume the same inert source snapshot.
  (let (texts (make-hash-table))
    (for-each
     (lambda (role)
       (let* ((path (path-expand (string-append (symbol->string role) ".ss") module-root))
              (required? (memq role '(types objects config interface))))
         (when (or required? (module-source-type path))
           (unless (eq? (module-source-type path) 'regular)
             (error "module role must be a regular file" module-name role path))
           (let (text (reader path))
             (unless (pair? (call-with-input-string text read-all))
               (error "module role cannot be empty" module-name role path))
             (hash-put! texts path text)))))
     poo-flow-module-allowed-entrypoint-roles)
    (def (read-role path (required? #t))
      (if (hash-key? texts path) (hash-ref texts path)
        (if required? (error "source role was not admitted" path) #f)))
    (poo-flow-module-dependency-direction-validate!
     (path-strip-directory (path-strip-trailing-directory-separator module-root)) module-root read-role)
    (hash-for-each
     (lambda (path text)
       (for-each
        (lambda (datum)
          (let (findings (poo-flow-module-owner-import-datum-observations
                           (string->symbol path) datum (.ref policy 'source-policy)))
            (when (pair? findings)
              (error "POO-FLOW-MODULE-E008 module owner imports aggregate facade"
                     module-name path (car findings)))))
        (call-with-input-string text read-all))) texts)
    (poo-flow-module-role-authoring-validate! policy module-name module-root read-role))
  module-root)

(def poo-flow-module-style-policy-prototype
  (.o (module-style-policy? #t)
      (authoring (poo-flow-default-module-authoring-profile))
      source-policy: SourceInspectionPolicy.
      validate: poo-flow-module-source-admit!))
(def poo-flow-default-module-style-policy
  (.o (:: @ poo-flow-module-style-policy-prototype)))

(def (admit-module-value! contract candidate context-value)
  (let (evidence (poo-flow-contract-admit contract candidate context-value))
    (unless (poo-flow-validation-evidence-accepted? evidence)
      (error "module scope admission refused" (.ref contract 'identity) evidence))
    evidence))
(def (admit-module-publication! source expected-id publication context-value)
  (unless (poo-flow-module-source-ref? source)
    (error "module publication requires a SourceRef" expected-id source))
  (let* ((evidence (admit-module-value! ModulePublicationContract publication context-value))
         (owner (assq 'module-id (poo-flow-module-source-ref-metadata source))))
    (unless (and (eq? expected-id (.ref publication 'identity))
                 (or (not owner) (eq? expected-id (cdr owner))))
      (error "publication source owner mismatch" expected-id source))
    evidence))
