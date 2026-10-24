;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;; Test fixture only: actual public Core admission, no Module/Loader adaptation.
(import :clan/poo/object :yuanxu/types
        (only-in :std/list/list every))

(def assertions 0)
(def (check name result)
  (unless result (error "combined-native-control-failed" name))
  (set! assertions (+ assertions 1)))
(def (report name value) (write (list name value)) (newline))
(def pipeline-forces 0)
(def checks-forces 0)
(def Root
  (.o (:: effective-config [])
    build: (.o value: 'build)
    test: (.o value: 'test)
    package: (.o value: 'package)
    pipeline:
    (begin
      (set! pipeline-forces (+ pipeline-forces 1))
      (.o selected-checks: '(build test package)
          checks:
          (begin
            (set! checks-forces (+ checks-forces 1))
            (map (lambda (name) (.ref effective-config name)) selected-checks))))))

(def parent-pipeline (.get Root pipeline))
(def parent-checks (.get parent-pipeline checks))
(check 'parent-cache-warmed (and (= pipeline-forces 1) (= checks-forces 1)))
(.def Policy policy: 'release)
(.def (Joined @ [Root Policy]))
(def Override (.o build: =>.+ (.o value: 'release-build)))
(def Patched (.+ Joined Override))
(def Copied (.cc Patched 'label 'release))
(.def (Final @ Copied)
  smoke: (.o value: 'smoke)
  pipeline: =>.+ (.o selected-checks: '(build test package smoke)))

(check 'all-declarations-lazy (and (= pipeline-forces 1) (= checks-forces 1)))
(check 'multiple-direct-parents
  (and (memq Root (object-supers Joined)) (memq Policy (object-supers Joined))))
(check 'plus-left-retained (memq Joined (object-supers Patched)))
(check 'plus-right-own-root-absent (not (memq Override (object-supers Patched))))
(check 'copy-own-source-absent (not (memq Patched (object-supers Copied))))
(check 'copy-keeps-native-parents (equal? (object-supers Copied) (object-supers Patched)))
(check 'copy-label (.get Copied label))
(check 'policy-retained (eq? (.get Final policy) 'release))
(check 'unrelated-demand-keeps-pipeline-lazy (= pipeline-forces 1))

(def (final-identities? candidate)
  (let ((actual (.get candidate pipeline checks))
        (expected (map (lambda (name) (.ref candidate name))
                       (.get candidate pipeline selected-checks))))
    (and (= (length actual) (length expected)) (every eq? actual expected))))
(def (empty-obligations candidate context) '())
(def CheckObjectContract
  (yuanxu-predicate-contract 'combined/check-object object? empty-obligations))
(def PipelineObjectContract
  (yuanxu-predicate-contract 'combined/pipeline-object object? empty-obligations))
(def (final-obligations candidate context)
  (if (and (eq? candidate (.get context target)) (final-identities? candidate))
    '() (list (.o kind: 'stale-final-checks))))
(.def (ProfileShapeContract @ YuanxuObjectContract.)
  identity: 'combined/profile-shape
  proto: Root
  responsibilities:
  (.o build: CheckObjectContract pipeline: PipelineObjectContract)
  .obligations: final-obligations)

;; Correlate real public Core evidence, not an invented boolean admit method.
(def (receipt-ok? contract candidate context evidence)
  (and (yuanxu-validation-evidence? evidence)
       (yuanxu-validation-evidence-accepted? evidence)
       (eq? (.get evidence contract-identity) (.get contract identity))
       (eq? (.get evidence candidate) candidate)
       (eq? (.get evidence context) context)
       (eq? (.get evidence classification type-identity) (.get contract identity))
       (eq? (.get evidence classification candidate) candidate)
       (eq? (.get evidence classification context) context)))
(def context (.o target: Final))
(def evidence (yuanxu-contract-admit ProfileShapeContract Final context))
(check 'final-public-admission (receipt-ok? ProfileShapeContract Final context evidence))
(def actual (.get Final pipeline checks))
(def values (map (lambda (check-object) (.get check-object value)) actual))
(check 'final-business-values (equal? values '(release-build test package smoke)))
(check 'ordered-final-identities (final-identities? Final))
(check 'new-smoke-identity (eq? (list-ref actual 3) (.get Final smoke)))
(check 'parent-pipeline-stable (eq? parent-pipeline (.get Root pipeline)))
(check 'parent-list-stable (eq? parent-checks (.get Root pipeline checks)))
(check 'child-pipeline-distinct (not (eq? parent-pipeline (.get Final pipeline))))
(check 'child-list-distinct (not (eq? parent-checks actual)))
(check 'two-receiver-forces (and (= pipeline-forces 2) (= checks-forces 2)))
(report 'final-values values)
(report 'parent-values (map (lambda (c) (.get c value)) parent-checks))
(report 'final-shape-admitted (.get evidence accepted?))
(report 'receiver-forces (list pipeline-forces checks-forces))

(.def (Frozen @ Final)
  pipeline: =>.+ (.o checks: parent-checks))
(def frozen-context (.o target: Frozen))
(def frozen-evidence
  (yuanxu-contract-admit ProfileShapeContract Frozen frozen-context))
(check 'stale-parent-list-refused (not (.get frozen-evidence accepted?)))
(check 'stale-parent-reason
  (eq? (.get (car (.get frozen-evidence obligation-evidence)) kind) 'stale-final-checks))
(report 'stale-parent-admitted (.get frozen-evidence accepted?))

;; Same list length is not sufficient: one refined build still has new identity.
(.def (SameCount @ Copied))
(.def (SameCountFrozen @ SameCount)
  pipeline: =>.+ (.o checks: parent-checks))
(def same-context (.o target: SameCountFrozen))
(def same-evidence
  (yuanxu-contract-admit ProfileShapeContract SameCountFrozen same-context))
(check 'same-count (equal? (.get SameCountFrozen pipeline selected-checks) '(build test package)))
(check 'same-count-stale-refused (not (.get same-evidence accepted?)))
(report 'same-count-stale-admitted (.get same-evidence accepted?))

;; This policy and closure Contract are TEST-LOCAL, not implemented adapters.
(def (check-policy-obligations candidate context)
  (if (eq? (.get candidate value) 'forbidden)
    (list (.o kind: 'forbidden-check)) '()))
(def CheckPolicyContract
  (yuanxu-predicate-contract 'combined/check-policy object? check-policy-obligations))
(def (closed-selection? candidate context)
  (let ((required (.get candidate pipeline selected-checks))
        (completed (.get context completed-checks)))
    (and (every (lambda (name) (memq name completed)) required)
         (every (lambda (name) (memq name required)) completed))))
(def (selected-closure-obligations candidate context)
  (cond
    ((not (eq? candidate (.get context target)))
     (list (.o kind: 'wrong-final-target)))
    ((not (closed-selection? candidate context))
     (list (.o kind: 'incomplete-selected-closure)))
    (else
     (let* ((names (.get candidate pipeline selected-checks))
            (checks (map (lambda (name) (.ref candidate name)) names)))
       (if (every
             (lambda (child)
               (receipt-ok? CheckPolicyContract child context
                 (yuanxu-contract-admit CheckPolicyContract child context)))
             checks)
         '() (list (.o kind: 'selected-child-refused)))))))
(def SelectionClosureContract
  (yuanxu-predicate-contract
    'combined/selection-closure object? selected-closure-obligations))

(def missing-context (.o target: Final completed-checks: '(build test package)))
(def outer-only (yuanxu-contract-admit ProfileShapeContract Final missing-context))
(def missing-evidence (yuanxu-contract-admit SelectionClosureContract Final missing-context))
(check 'outer-only-can-pass (receipt-ok? ProfileShapeContract Final missing-context outer-only))
(check 'missing-smoke-refused (not (.get missing-evidence accepted?)))
(check 'missing-smoke-reason
  (eq? (.get (car (.get missing-evidence obligation-evidence)) kind) 'incomplete-selected-closure))
(report 'outer-only-admitted (.get outer-only accepted?))
(report 'missing-child-closure-admitted (.get missing-evidence accepted?))

(def complete-context
  (.o target: Final completed-checks: '(build test package smoke)))
(def complete-evidence
  (yuanxu-contract-admit SelectionClosureContract Final complete-context))
(check 'complete-child-admissions
  (receipt-ok? SelectionClosureContract Final complete-context complete-evidence))
(report 'complete-closure-admitted (.get complete-evidence accepted?))

;; A complete name list cannot replace admission of each final child value.
(.def (BadSmoke @ Final) smoke: =>.+ (.o value: 'forbidden))
(def bad-context
  (.o target: BadSmoke completed-checks: '(build test package smoke)))
(def bad-outer (yuanxu-contract-admit ProfileShapeContract BadSmoke bad-context))
(def bad-child (yuanxu-contract-admit SelectionClosureContract BadSmoke bad-context))
(check 'bad-smoke-outer-can-pass (.get bad-outer accepted?))
(check 'bad-smoke-child-refused (not (.get bad-child accepted?)))
(check 'bad-smoke-reason
  (eq? (.get (car (.get bad-child obligation-evidence)) kind) 'selected-child-refused))
(report 'bad-smoke-outer-admitted (.get bad-outer accepted?))
(report 'bad-smoke-closure-admitted (.get bad-child accepted?))
(report 'assertions assertions)
