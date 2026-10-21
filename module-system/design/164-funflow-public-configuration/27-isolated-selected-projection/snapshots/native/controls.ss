;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;; This policy is fixture-upstream maintenance, never a user work/completion list.
(.def (FixturePolicy @ ProfileAdmissionPolicy)
  check-contracts: (.o build: BuildCheckContract))
(def context (.o target: Release))
(def result (admit-selected-profile FixturePolicy Release context))
(def descriptor (.get result effective-contract))
(def entries (.get result responsibility-evidence))
(def (entry-for evidence name)
  (car (filter (lambda (entry) (eq? (.get entry responsibility) name))
               (.get evidence responsibility-evidence))))
(check 'automatic-accepted (receipt-ok? descriptor Release context result))
(check 'final-child-coverage (covers-responsibilities? descriptor Release context result))
(check 'shape-prerequisite-recorded (= (length (.get result prerequisite-evidence)) 1))
(check 'selector-derived (equal? (.get result required-checks) '(build test package smoke)))
(check 'four-actual-child-receipts (= (length entries) 4))
(check 'smoke-default-contract
  (eq? (.get (entry-for result 'smoke) contract-identity) (.get CheckPolicyContract identity)))
(check 'build-stricter-contract
  (eq? (.get (entry-for result 'build) contract-identity) (.get BuildCheckContract identity)))
(check 'smoke-final-candidate
  (eq? (.get (entry-for result 'smoke) candidate) (.get Release smoke)))
(check 'parent-pipeline-unchanged (eq? parent-pipeline (.get Root pipeline)))
(check 'parent-list-unchanged (eq? parent-checks (.get Root pipeline checks)))
(check 'final-ordered-identities (final-identities? Release))
(check 'only-parent-and-child-forced (and (= pipeline-forces 2) (= checks-forces 2)))
(check 'unselected-unused-not-projected
  (not (.slot? (.get descriptor responsibilities) 'unused)))
(check 'unselected-unused-not-forced (= unused-forces 0))
(report 'automatic-admitted (.get result accepted?))
(report 'required-checks (.get result required-checks))
(report 'final-commands (map (lambda (c) (.get c commands)) (.get Release pipeline checks)))
(report 'parent-commands (map (lambda (c) (.get c commands)) parent-checks))
(report 'initial-force-counts (list pipeline-forces checks-forces unused-forces))

(.def (Typo @ Release)
  pipeline: =>.+ (.o selected-checks: '(build test package smkoe)))
(def typo-context (.o target: Typo))
(def typo-result (admit-selected-profile FixturePolicy Typo typo-context))
(check 'typo-rejected (not (.get typo-result accepted?)))
;; Inspect the genuine Core rejection nested inside the adapter's failure.
(def typo-native (.get (car (.get typo-result obligation-evidence)) evidence))
(def typo-child (entry-for typo-native 'smkoe))
(check 'typo-native-missing-role (not (.get typo-child accepted?)))
(check 'typo-not-filtered
  (eq? (.get (car (.get typo-child diagnostics)) kind) 'missing-responsibility))
(report 'typo-admitted (.get typo-result accepted?))
(report 'typo-native-diagnostic (.get (car (.get typo-child diagnostics)) kind))

;; Deliberately faulty Contract override: run REAL native admission first, then
;; corrupt only its evidence list. This is an internal fault, not user input.
(.def (OmittingTemplate @ SelectedChecksContract)
  .admit:
  (lambda (candidate context)
    (let* ((clean (.cc SelectedChecksContract
                    'responsibilities (.get @ responsibilities)))
           (native (yuanxu-contract-admit clean candidate context)))
      (.cc native 'responsibility-evidence
        (filter (lambda (entry) (not (eq? (.get entry responsibility) 'smoke)))
                (.get native responsibility-evidence))))))
(.def (FaultyPolicy @ FixturePolicy) selected: OmittingTemplate)
(def faulty-descriptor
  (project-selected-contract FaultyPolicy (.get Release pipeline selected-checks)))
(def incomplete-native (yuanxu-contract-admit faulty-descriptor Release context))
(check 'fault-has-stale-accepted-header (.get incomplete-native accepted?))
(check 'fault-only-three-child-receipts
  (= (length (.get incomplete-native responsibility-evidence)) 3))
(check 'missing-evidence-coverage-rejected
  (not (covers-responsibilities? faulty-descriptor Release context incomplete-native)))
(def missing-result (admit-selected-profile FaultyPolicy Release context))
(check 'end-to-end-missing-evidence-rejected (not (.get missing-result accepted?)))
(report 'corrupt-header-accepted (.get incomplete-native accepted?))
(report 'omitted-smoke-admitted (.get missing-result accepted?))

;; An old parent Check receipt cannot stand in for the final child's receipt.
(def wrong-entries
  (map (lambda (entry)
         (if (eq? (.get entry responsibility) 'build)
           (.cc entry 'candidate (.get Root build)) entry)) entries))
(check 'parent-receipt-identity-rejected
  (not (covers-responsibilities? descriptor Release context
         (.cc result 'responsibility-evidence wrong-entries))))

(.def (Frozen @ Release) pipeline: =>.+ (.o checks: parent-checks))
(def frozen-context (.o target: Frozen))
(def frozen-result (admit-selected-profile FixturePolicy Frozen frozen-context))
(check 'stale-parent-list-rejected (not (.get frozen-result accepted?)))
(def frozen-native (.get (car (.get frozen-result obligation-evidence)) evidence))
(check 'stale-final-identity-reason
  (eq? (.get (car (.get frozen-native obligation-evidence)) kind) 'stale-final-checks))
(report 'stale-parent-admitted (.get frozen-result accepted?))

(.def (SameCountFrozen @ Root)
  build: =>.+ (.o commands: '("gerbil" "build" "--release"))
  pipeline: =>.+ (.o checks: parent-checks))
(def same-context (.o target: SameCountFrozen))
(def same-result (admit-selected-profile FixturePolicy SameCountFrozen same-context))
(check 'same-count-three
  (= (length (.get SameCountFrozen pipeline selected-checks)) (length parent-checks)))
(check 'same-count-stale-rejected (not (.get same-result accepted?)))
(report 'same-count-stale-admitted (.get same-result accepted?))

(.def (BadSmoke @ Release) smoke: =>.+ (.o commands: '("forbidden")))
(def bad-context (.o target: BadSmoke))
(def bad-result (admit-selected-profile FixturePolicy BadSmoke bad-context))
(check 'bad-smoke-policy-rejected (not (.get bad-result accepted?)))
(report 'bad-smoke-admitted (.get bad-result accepted?))

(.def (BadBuild @ Release) build: =>.+ (.o commands: '("cargo" "build")))
(def bad-build-context (.o target: BadBuild))
(check 'stricter-build-not-weakened
  (not (.get (admit-selected-profile FixturePolicy BadBuild bad-build-context) accepted?)))
(check 'generic-family-would-accept-build
  (.get (yuanxu-contract-admit CheckPolicyContract (.get BadBuild build) bad-build-context)
        accepted?))

(.def (Duplicate @ Release)
  pipeline: =>.+ (.o selected-checks: '(build smoke smoke)))
(def dup-context (.o target: Duplicate))
(check 'duplicate-selector-rejected
  (not (.get (admit-selected-profile FixturePolicy Duplicate dup-context) accepted?)))
(.def (InvalidNames @ Release)
  pipeline: =>.+ (.o selected-checks: '("build")))
(def names-context (.o target: InvalidNames))
(check 'non-symbol-selector-rejected-before-projection
  (not (.get (admit-selected-profile FixturePolicy InvalidNames names-context) accepted?)))
(.def (Reserved @ Release) pipeline: =>.+ (.o selected-checks: '(pipeline)))
(def reserved-context (.o target: Reserved))
(def reserved-result (admit-selected-profile FixturePolicy Reserved reserved-context))
(check 'reserved-role-rejected
  (not (.get reserved-result accepted?)))
(check 'reserved-name-diagnostic-captures-lexical-value
  (eq? (.get (car (.get reserved-result obligation-evidence)) name) 'pipeline))
(check 'negative-controls-still-unused-lazy (= unused-forces 0))
(report 'unused-before-matched-control unused-forces)

;; Matched control: the same inherited thunk is forced when actually selected.
(.def (SelectUnused @ Release)
  pipeline: =>.+ (.o selected-checks: '(unused)))
(def unused-context (.o target: SelectUnused))
(def unused-result (admit-selected-profile FixturePolicy SelectUnused unused-context))
(check 'selected-unused-admitted (.get unused-result accepted?))
(check 'selected-unused-forced-once (= unused-forces 1))
(check 'selected-unused-final-candidate
  (eq? (.get (entry-for unused-result 'unused) candidate) (.get SelectUnused unused)))
(check 'selected-unused-cache-stable (= unused-forces 1))
(report 'unused-after-matched-control unused-forces)
(report 'assertions assertions)
