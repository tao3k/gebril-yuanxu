;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Shared source-role and publication admission. No expansion or activation.
(import (only-in :clan/poo/type Record)
        (only-in :gerbil/expander core-read-module/sexp)
        (runtime: :clan/poo/object)
        (only-in :clan/poo/mop Type element? validate)
        (only-in :clan/poo/slot-observation call-with-slot-read-observer slot-read-receiver slot-read-key)
        (only-in :yuanxu/module-system/source/role-forms yuanxu-module-allowed-entrypoint-roles
                 yuanxu-module-required-role-files module-role-file)
        (only-in :std/list/list any)
        (only-in :yuanxu/object-types/contracts yuanxu-contract-admit yuanxu-value-admit yuanxu-validation-evidence-accepted?)
        :yuanxu/module-system/source/observations
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/source/publication
        (only-in :yuanxu/module-system/source/interface yuanxu-module-interface)
        (only-in :yuanxu/module-system/authoring/import-policy
                 SourceInspectionPolicy. yuanxu-module-owner-import-datum-observations)
        (only-in :yuanxu/module-system/authoring/admission
                 call-with-module-authoring-read-scope
                 yuanxu-module-authoring-admit-datums
                 yuanxu-module-authoring-admission-accepted?
                 yuanxu-module-authoring-admission-diagnostics)
        (only-in :yuanxu/module-system/authoring/roles make-default-module-authoring-profile
                 ModuleAuthoringProfileContract))
(export yuanxu-module-required-role-files yuanxu-module-allowed-entrypoint-roles
        yuanxu-module-style-policy-prototype yuanxu-default-module-style-policy
        module-source-type module-source-read module-source-name? module-source-admit-current!
        module-compiler-interface-source
        call-with-module-source-read-cache call-with-module-source-fresh-reads
        call-with-module-source-callback
        call-with-collected-module-sources
        module-source-observe current-module-source-observer current-module-source-phase
        current-module-process-trace-budget
        call-with-module-source-operation-measurement module-source-measure-operation module-source-measure-replay
        module-source-checked-operation module-source-operation-procedure
        module-source-operation-resume module-source-object-policy
        admit-module-value! admit-module-publication! admit-module-configuration! module-source-style-policy-current?
        module-source-publication-policy)

(def (yuanxu-module-role-reference? datum module-name role)
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
      (or (yuanxu-module-role-reference? (car datum) module-name role)
          (yuanxu-module-role-reference? (cdr datum) module-name role)))
     ((vector? datum)
      (yuanxu-module-role-reference? (vector->list datum) module-name role))
     (else #f))))

(def (yuanxu-module-top-form-references-role? datums head module-name role)
  (and (any (lambda (form)
              (and (pair? form)
                   (eq? (car form) head)
                   (yuanxu-module-role-reference?
                    (cdr form) module-name role)))
            datums)
       #t))

(def (yuanxu-module-dependency-direction-validate! module-name module-root read-datums)
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
         (when (read-datums path)
           (let (datums (read-datums path))
             (for-each
              (lambda (forbidden-role)
                (when (yuanxu-module-top-form-references-role?
                       datums 'import module-name
                       (symbol->string forbidden-role))
                  (error "YUANXU-MODULE-E007 reversed module role dependency"
                         module-name source-role forbidden-role)))
              (cdr layer))))))
     layers)))

;;; The loader applies the Interface-owned authoring Profile to each stable
;;; role before exposing any entrypoint.  Admission reads inert datums only;
;;; it neither expands nor evaluates module source.
(def (yuanxu-module-role-authoring-validate! policy module-name module-root reader read-datums)
  ;; Interface creation validates the authoring Profile and its child roles.
  ;; Their temporary evidence belongs to the SAME region as datum dispatch.
  (call-with-module-authoring-read-scope
    (lambda ()
      (let* ((prototype
               (if (and (eq? policy yuanxu-default-module-style-policy)
                        (module-source-style-policy-current?))
                 (let ((reads '()))
                   (def value
                     (call-with-slot-read-observer
                       (lambda (read)
                         (when (and (eq? (slot-read-receiver read) policy)
                                    (eq? (slot-read-key read) '%authoring-interface))
                           (set! reads (cons read reads))))
                       (lambda () (.ref policy '%authoring-interface))))
                   ;; This is the actual runtime cached constructor token. Its
                   ;; edges retain every Type/field check, including temporary
                   ;; normalization receivers. Authenticate/recheck them on
                   ;; every use, even when this public function has no Reader.
                   (unless (pair? reads) (error "unissued source authoring Interface"))
                   (replay-slot-reads! (reverse reads) (lambda (_receiver _key) (void)))
                   value)
                 ;; Custom policies keep their ordinary constructor/Type calls.
                 (yuanxu-module-interface "source-policy" (Record) '()
                   authoring: (.ref policy 'authoring))))
             (interface
              (.cc prototype
                'id (if (symbol? module-name) (symbol->string module-name) module-name)
                'metadata (list (cons 'module-root module-root)))))
        (for-each
          (lambda (role)
            (let* ((path
                    (path-expand (module-role-file role) module-root))
                   (admission
                    (yuanxu-module-authoring-admit-datums
                      interface (if (eq? role 'func) 'funs role) (read-datums path))))
              (unless (yuanxu-module-authoring-admission-accepted? admission)
                (error "YUANXU-MODULE-E009 role violates Interface authoring Contract"
                       module-name role path
                       (car (yuanxu-module-authoring-admission-diagnostics admission))))))
          (filter
            (lambda (role)
              (reader (path-expand (module-role-file role) module-root) #f))
            yuanxu-module-allowed-entrypoint-roles))))))


(def (yuanxu-module-source-admit! policy module-name module-root reader)
  (unless (eq? (module-source-type module-root) 'directory)
    (error "module source must be a directory" module-name module-root))
  (when (file-exists? (path-expand "init.ss" module-root))
    (error "YUANXU-MODULE-E005 init.ss belongs to the selection root" module-name))
  ;; Read each selected role once. The caller may record these exact bytes in
  ;; its generation; all checks consume the same inert source snapshot.
  (let ((texts (make-hash-table)) (parsed (make-hash-table)))
    (for-each
     (lambda (role)
       (let* ((file (module-role-file role))
              (path (path-expand file module-root))
              (required? (member file yuanxu-module-required-role-files)))
         (when (or required? (module-source-type path))
           (unless (eq? (module-source-type path) 'regular)
             (error "module role must be a regular file" module-name role path))
           (let* ((text (reader path))
                  (datums (module-source-measure-operation 'source-parse
                            (lambda () (call-with-input-string text read-all)))))
             (observe-source 'role-parses)
             (unless (pair? datums)
               (error "module role cannot be empty" module-name role path))
             (hash-put! texts path text)
             (hash-put! parsed path datums)))))
     yuanxu-module-allowed-entrypoint-roles)
    (def (read-role path (required? #t))
      (if (hash-key? texts path) (hash-ref texts path)
        (if required? (error "source role was not admitted" path) #f)))
    (def (read-datums path) (hash-get parsed path))
    ;; One private parse per role/policy invocation. Structural checks and the
    ;; authoring protocol inspect the SAME source datums. Discard this snapshot
    ;; after the call; re-read/reparse and re-dispatch on the next invocation.
    (module-source-measure-operation 'source-direction
      (lambda () (yuanxu-module-dependency-direction-validate!
        (path-strip-directory (path-strip-trailing-directory-separator module-root)) module-root read-datums)))
    (module-source-measure-operation 'source-import-policy
      (lambda () (hash-for-each
     (lambda (path text)
       (for-each
        (lambda (datum)
          (let (findings (yuanxu-module-owner-import-datum-observations
                           (string->symbol path) datum (.ref policy 'source-policy)))
            (when (pair? findings)
              (error "YUANXU-MODULE-E008 module owner imports aggregate facade"
                     module-name path (car findings)))))
        (read-datums path))) texts)))
    (module-source-measure-operation 'source-authoring
      (lambda () (yuanxu-module-role-authoring-validate!
        policy module-name module-root read-role read-datums))))
  module-root)

(def yuanxu-module-style-policy-prototype
  (.o (module-style-policy? #t)
      ;; Keep raw construction separate from the checked Interface value below.
      ;; Derived policy receivers still get their own Profile/defaults.
      (authoring (make-default-module-authoring-profile))
      ;; Normalize the policy-owned Profile through the public constructor once
      ;; per runtime receiver. Owners derive only their id/location. Every datum
      ;; still goes through fresh typed Generic analysis below; no accepted source or
      ;; obligation result is cached. Runtime reads retain the constructor's
      ;; complete Type/metadata support, including inherited-policy invalidation.
      (%authoring-interface
        (let* ((value (yuanxu-module-interface "source-policy" (Record) '() authoring: authoring))
               (profile (.ref value 'authoring))
               (fields (.ref ModuleAuthoringProfileContract 'responsibilities)))
          ;; Bind the checked OUTPUT as well as the constructor's input reads.
          ;; Runtime names/preparation records reject later mutations of a
          ;; normalized receiver. Use the actual Contract's declared fields;
          ;; do not inspect unrelated optional extension values.
          (.all-slots profile)
          (for-each
            (lambda (name)
              (let (child (.ref profile name))
                (when (object? child) (.all-slots child))))
            (.all-slots fields))
          value))
      source-policy: SourceInspectionPolicy.
      validate: yuanxu-module-source-admit!))
(def yuanxu-default-module-style-policy
  (.o (:: @ yuanxu-module-style-policy-prototype)))

;; Capture the maintained policy BEFORE exposing it for extension. Include its
;; actual Profile children; changing a role need not edit the containing slot.
(def (module-source-style-policy-support)
  (let* ((policy yuanxu-default-module-style-policy)
         (profile (.ref policy 'authoring)))
    (append (list policy profile (.ref policy 'source-policy))
        (filter object?
          (map (cut .ref profile <>) '(executor types objects funs config interface build))))))
(def default-style-policy-current
  (module-source-object-policy (module-source-style-policy-support)))
(def (module-source-style-policy-current?) (default-style-policy-current))
(def (module-source-publication-policy)
  ;; Snapshot the actual policy/Contract references before role execution.
  ;; Runtime initializer scratch reads are not admission requirements.
  (module-source-object-policy
    (cons ModulePublicationContract (module-source-style-policy-support))
    reject-protocols?: #f))

(def (admit-module-value! contract candidate context-value)
  (let (evidence (yuanxu-value-admit contract candidate context-value))
    (unless (yuanxu-validation-evidence-accepted? evidence)
      (error "module scope admission refused" (.ref contract 'identity) evidence))
    evidence))

;; Resolve an existing declaration path. Missing associations are programmer
;; errors and must not turn into a permissive user configuration Type.
(def (configuration-path scope path owner)
  (let loop ((value scope) (remaining path))
    (if (null? remaining) value
      (begin
        (unless (and (object? value) (.slot? value (car remaining)))
          (error "module configuration Contract path is missing" owner path))
        (loop (.ref value (car remaining)) (cdr remaining))))))

;; A public config is checked against its declared Type before scope admission.
;; core.admissions owns the association. Type validation owns recursive
;; wrapping and closed-field rules; an internal config slot alone is no grant.
;; Check only final linked receivers, not incomplete source-role fragments.
(def (admit-module-configuration! scope core owner context)
  (unless (and (object? scope) (.slot? scope 'config))
    (error "module configuration value is missing" owner))
  (let* ((declarations (if (.slot? core 'admissions) (.ref core 'admissions) (.o)))
         (paths
           (filter-map
             (lambda (name)
               (let (entry (.ref declarations name))
                 (and (equal? (.ref entry 'export-path) '(config))
                      (.ref entry 'contract-path))))
             (.all-slots declarations))))
    (unless (pair? paths)
      (error "module configuration declaration is missing" owner))
    (when (pair? (cdr paths))
      (error "multiple module configuration Contract declarations" owner))
    (let* ((descriptor (configuration-path scope (car paths) owner))
           (_type (unless (element? Type descriptor)
                    (error "module configuration declaration is not a Type" owner descriptor)))
           (candidate (.ref scope 'config))
           (checked
             (if (.slot? descriptor '.admit)
               (begin
                 (unless (procedure? (.ref descriptor '.admit))
                   (error "module configuration admission is not a procedure" owner))
                 (let (evidence (yuanxu-contract-admit descriptor candidate context))
                   (unless (yuanxu-validation-evidence-accepted? evidence)
                     (error "module configuration admission refused" owner
                            (.ref descriptor 'identity) (.ref evidence 'diagnostics) evidence))
                   (.ref evidence 'candidate)))
               (validate descriptor candidate))))
      (if (eq? candidate checked) scope (.cc scope 'config checked)))))
(def (admit-module-publication! source expected-id publication context-value)
  (unless (yuanxu-module-source-ref? source)
    (error "module publication requires a SourceRef" expected-id source))
  (let* ((evidence (admit-module-value! ModulePublicationContract publication context-value))
         ;; The public value Contract may return a different checked receiver.
         ;; Owner checks must describe THAT subject, not the pre-check input.
         (checked (.ref evidence 'candidate))
         (metadata (yuanxu-module-source-ref-metadata source))
         (owner (assq 'module-id metadata))
         (declaration (assq 'declaration-id metadata)))
    ;; A relative declaration label is never an alias certificate. Bind the
    ;; complete key to Gerbil's actual source identity before admitting it.
    (when declaration
      (unless (eq? (yuanxu-module-source-ref-kind source) 'local)
        (error "root-qualified publication requires a local native source" expected-id))
      (let-values (((_prelude native-id _namespace _body)
                     (core-read-module/sexp (yuanxu-module-source-ref-value source))))
        (unless (eq? expected-id native-id)
          (error "root-qualified publication differs from native source identity" expected-id native-id))))
    (unless (and (or (not declaration) owner)
                 (eq? (if declaration (cdr declaration) expected-id) (.ref checked 'identity))
                 (or (not owner) (eq? expected-id (cdr owner))))
      (error "publication source owner mismatch" expected-id source))
    evidence))
