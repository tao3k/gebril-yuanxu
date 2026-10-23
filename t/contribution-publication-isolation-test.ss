;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Test-local collection adapter. Real MOP, source guards, selected/build graph,
;;; delayed CLOS bundle, Core .admit and checked publisher. No Loader call.
(import (only-in :std/error Error? Error-message) :std/test :std/list/list :clan/poo/object
        (only-in :clan/poo/mop define-type)
        (only-in :std/io/tempfile make-temporary-file-name)
        (prefix-in :clan/poo/declarative-metadata metadata.)
        :yuanxu/poo-clos/interface
        (only-in :yuanxu/object-types/contracts YuanxuContract. yuanxu-classification-evidence)
        (only-in :yuanxu/admission/publication AdmissionPublication.)
        (only-in :yuanxu/module-system/source/selection select-module-graph)
        (only-in :yuanxu/module-system/source/build module-build-graph)
        (only-in :yuanxu/module-system/source/objects make-yuanxu-module-source-ref)
        (only-in :yuanxu/module-system/source/admission module-source-read module-source-admit-current!))
(export contribution-publication-isolation-test test-cleanup!)

(def completed 0)
(def (done!) (set! completed (+ completed 1)))
(def (test-cleanup!)
  (unless (= completed 8) (error "incomplete contribution controls" completed))
  (displayln "CONTRIBUTION-PUBLICATION: 8 cases completed"))
(def (write-source path text)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))
(def (with-sources consume)
  (def directory (make-temporary-file-name "contribution-publication-"))
  (create-directory directory)
  (def paths (map (lambda (name) (path-expand name directory))
                 '("application.ss" "operations.ss" "security.ss")))
  (dynamic-wind
    (lambda () (for-each (lambda (path) (write-source path "; selected v1\n")) paths))
    (lambda () (consume paths))
    (lambda () (for-each delete-file paths) (delete-directory directory))))

(.def PortRequirement.)
(define-type (PortAdmission. @ YuanxuContract.))
(def RequirementProtocol (poo-clos-generic-protocol 'isolation/port-requirement))
(.defgeneric project-port (admission payload origin) (protocol RequirementProtocol))
(def (dispatcher)
  (.defmethod-bundle Methods RequirementProtocol
    (.defmethod (project-port (admission (prototype PortAdmission.))
                              (payload (prototype PortRequirement.)) origin)
      (def port (.get payload value))
      (unless (and (exact-integer? port) (<= 1 port 65535))
        (error "invalid policy port" port))
      (list (.cc (.o) value: port origin: origin))))
  (poo-clos-compose-method-bundles
    (poo-clos-generic-function 'project-port 3 protocol: RequirementProtocol)
    (list Methods)))

(.def (Parent @ [] config)
  config: (.o (:: @ [] postgresql)
            postgresql: (.cc (.o) settings: (.cc (.o) port: 5432))
            gitea: (.cc (.o) port: (.get postgresql settings port)))
  plan: (.cc (.o) server: (.get config postgresql settings port)
            client: (.get config gitea port)))
(.def (Release @ Parent)
  config: =>.+ (.o postgresql: =>.+ (.o settings: =>.+ (.cc (.o) port: 5433))))

(def (observe object) (cons object (object-revision object)))
(def (revisions-current! observations)
  (unless (every (lambda (entry) (equal? (cdr entry) (object-revision (car entry))))
                 observations)
    (error "contribution object changed")))

;; Match each private edge with its actual selected record and export identity.
(def (error-message=? expected)
  (lambda (failure) (and (Error? failure) (equal? (Error-message failure) expected))))
(def (coverage! edges rows)
  (unless (= (length edges) (length rows)) (error "incomplete collection"))
  (for-each
    (lambda (edge row)
      (def record (.get edge record))
      (def origin (.get row origin))
      (unless (and (eq? (.get row edge) edge)
                   (eq? (.get origin record) record)
                   (eq? (.get origin owner) (.get record identity))
                   (eq? (.get origin source) (.get record source))
                   (eq? (.get origin publication) (.get record publication))
                   (equal? (.get origin generation) (.get record generation))
                   (eq? (.get origin key) (.get edge key))
                   (equal? (.get origin export-path) (.get edge export-path))
                   (eq? (.get row payload)
                        (.ref (.get record scope) (car (.get edge export-path)))))
        (error "substituted contribution origin")))
    edges rows))
(def (collect edge)
  (def record (.get edge record))
  ((.get record admit-current))
  (def scope (.get record scope))
  (def before (observe scope))
  (def payload (.ref scope (car (.get edge export-path))))
  (def origin
    (.cc (.o) owner: (.get record identity) record: record
        source: (.get record source) publication: (.get record publication)
        generation: (.get record generation) key: (.get edge key)
        export-path: (.get edge export-path)))
  (def row (.cc (.o) edge: edge payload: payload origin: origin))
  (.cc (.o) row: row observations:
    (cons before (map observe (list edge record (.get record source)
                                   (.get record publication) payload origin row)))))

(def (local-relations candidate)
  (def server (.get candidate config postgresql settings port))
  (def client (.get candidate config gitea port))
  (cond
    ((not (= server client)) (list (.cc (.o) kind: 'connection-mismatch)))
    ((not (and (= server (.get candidate plan server))
               (= client (.get candidate plan client))))
     (list (.cc (.o) kind: 'stale-parent-plan)))
    (else '())))

;; Selected declarations/record scopes are bounded fixtures, not an implemented
;; core.contributions resolver. Real selected/build graph handles source guards.
(def (platform paths ports)
  (def ids '(application operations security))
  (def inputs (map (lambda (path) (cons path (module-source-read path))) paths))
  (def (current!) (module-source-admit-current! inputs))
  (def sources (map (lambda (path) (make-yuanxu-module-source-ref 'local path '())) paths))
  (def publications
    (map (lambda (id) (.cc (.o) identity: id core: (.cc (.o) requires: (.cc (.o))) features: (.cc (.o)))) ids))
  (def selected
    (select-module-graph
      (.cc (.o) generation: "isolation-1" selected: ids denied-modules: '() init-source: #f)
      ids (lambda (id) (cdr (assq id (map cons ids publications)))) current!))
  (def build
    (module-build-graph selected
      (lambda (id)
        (.cc (.o) identity: id generation: "isolation-1" compiler-identity: id
            source: (cdr (assq id (map cons ids sources)))
            role-sources: '() source-inputs: inputs admit-current: current!))))
  (def records
    (map (lambda (id source publication port)
           (.cc (.o) identity: id generation: "isolation-1" source: source publication: publication
               scope: (.cc (.o) database-port: (.o (:: @ PortRequirement.) value: port))
               admit-current: current!))
         (cdr ids) (cdr sources) (cdr publications) ports))
  (def edges
    (map (lambda (record) (.cc (.o) record: record key: 'database-port
                             export-path: '(database-port))) records))
  (def collected (map collect edges))
  (def rows (map (lambda (item) (.get item row)) collected))
  (coverage! edges rows)
  (def observations (append-map (lambda (item) (.get item observations)) collected))
  (def (batch-current!) (current!) (revisions-current! observations) (coverage! edges rows))
  (def dispatch (dispatcher))
  (def descriptor
    (.o (:: @ PortAdmission.)
      identity: 'isolation/application
      .classify: (lambda (candidate context)
                   (def issues (local-relations candidate))
                   (yuanxu-classification-evidence
                     'isolation/application candidate (null? issues) issues context))
      .obligations:
      (lambda (candidate _context)
        (batch-current!)
        (def constraints
          (append-map
            (lambda (row) (poo-clos-call dispatch @ (.get row payload) (.get row origin))) rows))
        (def actual (.get candidate config postgresql settings port))
        (def issues
          (if (every (lambda (row) (= actual (.get row value))) constraints) '()
            (list (.cc (.o) kind: 'unsatisfied-joint-port-requirements constraints: constraints))))
        (batch-current!)
        issues)))
  (def publication (.cc AdmissionPublication. graph: build schemas: '() contract: descriptor))
  (def base (.get publication context))
  (def context
    (.o (:: @ base)
      admit-current: (lambda () ((.get base admit-current)) (batch-current!))))
  (.cc (.o) publication: (.cc publication context: context) descriptor: descriptor
      edges: edges rows: rows records: records))

(def (underlying-cause value)
  (if (metadata.failure? value)
    (underlying-cause (metadata.failure-cause value)) value))
(def (refused view candidate (expected-message #f))
  (defvalues (receipt next failure) (.call (.get view publication) .publish Parent candidate))
  (check-equal? receipt #f)
  (check-equal? (eq? next Parent) #t)
  (check-equal? (metadata.failure? failure) #t)
  (when expected-message
    (check-equal? ((error-message=? expected-message) (underlying-cause failure)) #t)))

(def contribution-publication-isolation-test
  (test-suite "Isolated complete collection and checked publication"
    (test-case "two distinct selected origins survive joint refusal"
      (with-sources (lambda (paths)
        (def view (platform paths '(5433 5440)))
        (check-equal? (map (lambda (row) (.get row origin owner)) (.get view rows))
                      '(operations security))
        (def evidence (.call (.get view descriptor) .admit Release (.get view publication context)))
        (check-equal? (.get evidence accepted?) #f)
        (def constraints (.get (car (.get evidence obligation-evidence)) constraints))
        (check-equal? (map (lambda (row) (.get row origin owner)) constraints)
                      '(operations security))
        (check-equal? (map (lambda (row) (.get row value)) constraints) '(5433 5440))
        (refused view Release) (done!))))
    (test-case "missing and duplicated row refuse exact coverage"
      (with-sources (lambda (paths)
        (def view (platform paths '(5433 5433)))
        (check-exception (coverage! (.get view edges) (cdr (.get view rows))) (error-message=? "incomplete collection"))
        (check-exception (coverage! (.get view edges)
                          (list (car (.get view rows)) (car (.get view rows))))
                         (error-message=? "substituted contribution origin"))
        (done!))))
    (test-case "same-label replacement source refuses identity binding"
      (with-sources (lambda (paths)
        (def view (platform paths '(5433 5433)))
        (def rows (.get view rows))
        (def forged (.cc (.get (car rows) origin)
                      source: (make-yuanxu-module-source-ref 'local (cadr paths) '())))
        (check-exception
          (coverage! (.get view edges)
            (cons (.cc (car rows) origin: forged) (cdr rows)))
          (error-message=? "substituted contribution origin"))
        ;; Also reject replacement after assembly at the checked publisher.
        (.put! (car rows) 'origin forged)
        (refused view Release)
        (done!))))
    (test-case "source bytes changed after assembly refuse publication"
      (with-sources (lambda (paths)
        (def view (platform paths '(5433 5433)))
        (write-source (cadr paths) "; selected v2\n")
        (refused view Release "stale selected build input; regenerate the build entry") (done!))))
    (test-case "supported MOP mutation refuses old batch"
      (with-sources (lambda (paths)
        (def view (platform paths '(5433 5433)))
        (.put! (.get (car (.get view rows)) payload) 'value 6000)
        (refused view Release "contribution object changed") (done!))))
    (test-case "cached parent leaves do not freeze child final preview"
      (with-sources (lambda (paths)
        (check-equal? (.get Parent plan server) 5432)
        (check-equal? (.get Parent plan client) 5432)
        (.def (FreshRelease @ Parent)
          config: =>.+ (.o postgresql: =>.+ (.o settings: =>.+ (.o port: 5433))))
        (def view (platform paths '(5433 5433)))
        (defvalues (receipt next failure) (.call (.get view publication) .publish Parent FreshRelease))
        (check-equal? failure #f)
        (check-equal? (.get receipt accepted?) #t)
        (check-equal? (eq? (.get receipt candidate) next) #t)
        (check-equal? (.get next plan server) 5433)
        (check-equal? (.get next plan client) 5433)
        (check-equal? (.get Parent plan server) 5432) (done!))))
    (test-case "explicitly reattached cached parent plan refuses"
      (with-sources (lambda (paths)
        (def cached (.get Parent plan))
        (check-equal? (.get cached server) 5432)
        (.def (Frozen @ Release) plan: cached)
        (refused (platform paths '(5433 5433)) Frozen) (done!))))
    (test-case "final mismatching client refuses local association"
      (with-sources (lambda (paths)
        (.def (Wrong @ Release) config: =>.+ (.o gitea: =>.+ (.cc (.o) port: 6000)))
        (refused (platform paths '(5433 5433)) Wrong) (done!))))))
