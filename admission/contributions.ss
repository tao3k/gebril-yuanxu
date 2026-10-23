;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Selected Core routes -> source-bound rows, guarded at native admission.
(import :clan/poo/object
        (only-in :clan/poo/mop .defgeneric validate)
        (only-in :std/list/list every append-map)
        (only-in :yuanxu/module-system/source/publication ContributionRouteContract)
        (only-in :yuanxu/object-types/contracts yuanxu-context-contract-obligations)
        (only-in :yuanxu/module-system/source/admission call-with-module-source-read-cache))
(export bind-publication-contributions yuanxu-contract-contribution-obligations)

;; The domain owns interpretation; the platform owns completeness/provenance.
(.defgeneric (yuanxu-contract-contribution-obligations contract candidate rows context)
  slot: .contribution-obligations)

(def indexes (make-hash-table-eq weak-keys: #t))
(def (observe value) (cons value (object-revision value)))
(def (observations-current! observations)
  (unless (every (lambda (entry) (equal? (cdr entry) (object-revision (car entry))))
                 observations)
    (error "contribution object changed")))

(def (index-routes graph)
  (def routes (make-hash-table-eq))
  (def targets (make-hash-table-eq))
  (def observations '())
  (for-each
    (lambda (node)
      (when (eq? (.get node kind) 'module-core)
        (let* ((publication (.get node publication))
               (core (.get publication core)))
          (hash-put! targets (.get node owner) core)
          (set! observations
            (append (map observe (list node publication core)) observations))
          (when (.slot? core 'contributions)
            (let (declarations (.get core contributions))
              (set! observations (cons (observe declarations) observations))
              (for-each
                (lambda (key)
                  (def raw (.ref declarations key))
                  (def before (observe raw))
                  (def route (validate ContributionRouteContract raw))
                  (def owner (.get route target-owner))
                  (def name (.get route target-admission))
                  (def bucket
                    (or (hash-get routes owner)
                        (let (value (make-hash-table-eq))
                          (hash-put! routes owner value) value)))
                  (def edge
                    (.cc (.o) node: node key: key route: route
                        path: (map values (.get route export-path))))
                  (set! observations (cons before observations))
                  (hash-put! bucket name
                    (cons edge (or (hash-get bucket name) '()))))
                (.all-slots declarations)))))))
    (.get graph nodes))
  ;; References to unselected owners stay inert; selected targets must exist.
  (hash-for-each
    (lambda (owner bucket)
      (let (core (hash-get targets owner))
        (when core
          (hash-for-each
            (lambda (name _edges)
              (unless (and (.slot? core 'admissions)
                           (.slot? (.get core admissions) name))
                (error "contribution targets unknown selected admission" owner name)))
            bucket))))
    routes)
  ;; Do not retain the weak cache key in its value.
  (.cc (.o) revision: (object-revision graph) routes: routes observations: observations))

;; A route-free index needs only already-demanded native metadata. A cache miss
;; or any contribution declaration takes the guarded reader path below. This
;; constructs an index, never a source approval or publication receipt.
(def (cached-route-free-index graph)
  (let/cc unavailable
    (def (cached receiver slot)
      (unless (object? receiver) (unavailable #f))
      (.ref/cached receiver slot (lambda () (unavailable #f))))
    (def revision (object-revision graph))
    (def observations '())
    (for-each
      (lambda (node)
        (when (eq? (cached node 'kind) 'module-core)
          (let* ((publication (cached node 'publication))
                 (core (cached publication 'core)))
            ;; Presence inspection does not demand the declaration's value.
            (when (.slot? core 'contributions) (unavailable #f))
            (set! observations
              (append (map observe (list node publication core)) observations)))))
      (cached graph 'nodes))
    (.cc (.o) revision: revision routes: (make-hash-table-eq)
         observations: observations)))

(def (selected-index selection graph)
  (def index
    (or (hash-get indexes graph)
        (let (value (cached-route-free-index graph))
          (when value (hash-put! indexes graph value)) value)))
  ;; A completed empty index can be inspected without reading any author slot.
  ;; Nonempty routes or cold metadata retain their original guarded reader.
  (unless (and index (zero? (hash-length (.get index routes))))
    (call-with-module-source-read-cache
      (lambda ()
        ((.get selection sources-current))
        ((.get graph admit-current))))
    (unless index
      (set! index (index-routes graph))
      (hash-put! indexes graph index)))
  (index-current! graph index)
  index)
(def (index-current! graph index)
  (unless (equal? (.get index revision) (object-revision graph))
    (error "selected contribution graph changed"))
  (observations-current! (.get index observations)))
(def (incoming index owner name)
  (def bucket (hash-get (.get index routes) owner))
  (reverse (if bucket (or (hash-get bucket name) '()) '())))

(def (walk-export scope path)
  (def observations '())
  (def payload
    (foldl (lambda (name receiver)
             (unless (and (object? receiver) (.slot? receiver name))
               (error "unresolved contribution export" path name))
             (set! observations (cons (observe receiver) observations))
             (.ref receiver name)) scope path))
  (unless (object? payload) (error "contribution export must be a POO object" path))
  (values payload observations))
(def (collect selection edge)
  (def owner (.get edge node owner))
  (def record (.call selection .selected-record owner))
  (unless (eq? (.get record publication) (.get edge node publication))
    (error "selected contribution publication mismatch" owner))
  (def prepared ((.get selection prepare-publication) owner))
  (unless (and (eq? (.get prepared identity) owner)
               (equal? (.get prepared generation) (.get record generation)))
    (error "selected contribution preparation mismatch" owner))
  ((.get prepared admit-current))
  (defvalues (payload receivers) (walk-export (.get record scope) (.get edge path)))
  (def origin
    (.cc (.o) owner: owner key: (.get edge key) record: record
        publication: (.get record publication) source: (.get record source)
        generation: (.get record generation) export-path: (map values (.get edge path))))
  (def row (.cc (.o) payload: payload origin: origin))
  ((.get prepared admit-current))
  (.cc (.o) row: row prepared: prepared observations:
    (append receivers
      (map observe (list edge record (.get record source) payload origin row)))))

(def (coverage! selection edges expected rows)
  (unless (and (list? rows) (= (length edges) (length rows)))
    (error "incomplete contribution collection"))
  (for-each
    (lambda (edge registered row)
      (unless (eq? row registered) (error "substituted contribution origin"))
      (def origin (.get row origin))
      (def record (.call selection .selected-record (.get edge node owner)))
      (unless (and (eq? (.get origin record) record)
                   (eq? (.get origin source) (.get record source))
                   (eq? (.get origin publication) (.get edge node publication))
                   (eq? (.get origin owner) (.get record identity))
                   (eq? (.get origin key) (.get edge key))
                   (equal? (.get origin generation) (.get record generation))
                   (equal? (.get origin export-path) (.get edge path)))
        (error "substituted contribution origin"))
      (defvalues (payload _receivers) (walk-export (.get record scope) (.get edge path)))
      (unless (eq? payload (.get row payload)) (error "substituted contribution payload")))
    edges expected rows))

(def (bind-publication-contributions selection owner name publication)
  (def graph (.get publication graph selected-graph))
  (def index (selected-index selection graph))
  (def edges (incoming index owner name))
  ;; With no incoming rows, only native index inspection precedes this source
  ;; collection boundary. Demand it BEFORE cold Contract metadata/handlers;
  ;; an empty index never grants permission to read them from stale sources.
  (def source-base (and (null? edges) (.get publication context)))
  (def descriptor (.get publication contract))
  ;; Only contextual requirements are admission producers. Public value Types
  ;; under value-contract have their own validation protocol, not this authority.
  (def contracts (make-hash-table-eq))
  (def contract-observations '())
  (def (register! current)
    (unless (hash-get contracts current)
      (hash-put! contracts current #t)
      (set! contract-observations (cons (observe current) contract-observations))
      (when (.slot? current 'responsibilities)
        (let (requirements (.get current responsibilities))
          (set! contract-observations (cons (observe requirements) contract-observations))
          (for-each (lambda (slot) (register! (.ref requirements slot)))
                    (.all-slots requirements))))))
  (register! descriptor)
  (def handles? (and (.slot? descriptor '.contribution-obligations)
                    (procedure? (.get descriptor .contribution-obligations))))
  (when (and (pair? edges) (not handles?))
    (error "selected admission has contributions but no contribution protocol" owner name))
  (def collected (map (lambda (edge) (collect selection edge)) edges))
  (def rows (map (lambda (item) (.get item row)) collected))
  (def observations
    (append contract-observations
            (append-map (lambda (item) (.get item observations)) collected)))
  (def base (or source-base (.get publication context)))
  (def (current! context)
    (call-with-module-source-read-cache
      (lambda ()
        ((.get base admit-current))
        (unless (and (eq? (.get context selected-graph) graph)
                     (equal? (.get context graph-generation) (.get graph generation)))
          (error "contributions belong to another selected graph"))
        (index-current! graph index)
        (for-each (lambda (item) ((.get item prepared admit-current))) collected)
        (coverage! selection edges rows (.get context contributions))
        (observations-current! observations)
        ((.get selection sources-current)))))
  (def context
    (.o (:: @ base)
      contributions: (map values rows)
      admit-current: (lambda () (current! @))
      ;; Analysis retains registered descriptor and contribution observations.
      ;; Root current! still certifies the complete selection before/after open
      ;; callbacks and at return. No source-byte cache spans child obligations.
      .responsibility-obligations:
      (lambda (actual candidate)
        (unless (hash-get contracts actual)
          (error "admission descriptor differs from selected publication"))
        (observations-current! observations)
        (if (or (.slot? base '.contract-obligations) (eq? actual descriptor)
                (not (eq? (.get @ .contract-obligations) platform-obligations)))
          (yuanxu-context-contract-obligations @ actual candidate)
          '()))
      .contract-obligations:
      (lambda (actual candidate)
        (unless (hash-get contracts actual)
          (error "admission descriptor differs from selected publication"))
        (def inherited? (.slot? base '.contract-obligations))
        (def contributed? (and (eq? actual descriptor) handles?))
        (current! @)
        ;; A registered child with no platform callback has no intervening
        ;; obligation/effect here. Its own domain obligation already ran in
        ;; the kernel. Do not repeat the identical source guard before return.
        (if (not (or inherited? contributed?)) '()
          (let* ((inherited (if inherited?
                             (yuanxu-context-contract-obligations base actual candidate) '()))
                 (contributed (if contributed?
                                (yuanxu-contract-contribution-obligations
                                  actual candidate (.get @ contributions) @) '())))
            (unless (list? contributed)
              (error "contribution obligations must return diagnostics"))
            ;; Real callbacks retain a fresh post-call guard, including the
            ;; inherited-only case. No byte window spans either callback.
            (current! @)
            (append inherited contributed))))))
  ;; A derived/replaced platform handler is an open callback, not the bound
  ;; analytic entry. It must run with its original guard semantics.
  (def platform-obligations (.get context .contract-obligations))
  (current! context)
  (.cc publication context: context))
