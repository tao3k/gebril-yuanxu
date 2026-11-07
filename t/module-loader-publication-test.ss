;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Actual reader/link/publication; only module roles and destructive edits are fixtures.
(import :std/test :clan/poo/object
        (only-in :std/source this-source-file)
        (prefix-in :clan/poo/declarative-metadata metadata.)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in "./qualification/testing/directory.ss" DirectoryFixture write-source)
        (only-in "./qualification/service-publication/fixtures.ss" refused)
        (only-in :yuanxu/module-system/source/link yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/admission module-source-read)
        (only-in :yuanxu/admission/publication AdmissionPublication.)
        (only-in :yuanxu/module-system/source/objects make-yuanxu-module-local-source)
        (only-in :yuanxu/module-system/loader/objects
                 yuanxu-make-lazy-load-plan yuanxu-force-lazy-load-plan))
(export module-loader-publication-test)

(def roles-root (path-expand "fixtures/loader-publication" (path-directory (this-source-file))))
(.def (BackendPublicationFixture @ DirectoryFixture)
  prefix: "backend-publication-"
  .prepare:
  (lambda (workspace)
    (def root (.get workspace root))
    (write-source (path-expand "gerbil.pkg" root)
      (string-append "(package: " (symbol->string (gensym 'backend-fixture-))
        " prelude: :yuanxu/module-system/source/module-prelude)"))
    (for-each
      (lambda (role)
        (def file (string-append role ".ss"))
        (write-source (path-expand (string-append "modules/fixture/backend/" file) root)
          (module-source-read (path-expand file roles-root))))
      '("types" "config" "objects" "interface"))
    (write-source (path-expand "modules/fixture/unused/interface.ss" root) "(((cold")
    (write-source (path-expand "init.ss" root)
      "(yuanxu! mode: explicit :fixture (backend) (unused disable: #t))")
    (def selection (yuanxu-load-modules (path-expand "init.ss" root)))
    (def record (.call selection .selected-record 'fixture/backend))
    (.cc workspace selection: selection record: record
      publication: (.call AdmissionPublication. .for-export selection 'fixture/backend 'Backend))))

(def module-loader-publication-test
  (test-suite "Checked Backend source publication"
    (yuanxu-test-fixture "checked publication binds the normalized root without executing its callback"
      (fixture BackendPublicationFixture)
      (with-slots (record publication) fixture
        (def parent (.get publication value))
        (def cached (.get parent load))
        (def trace (.get record scope trace))
        (check-eq? parent (.get record scope Backend))
        (check-eq? (.get publication contract) (.get record scope types Admission))
        (check-equal? ((.get trace calls)) 0)
        (check-equal? (eq? cached (.get trace original)) #f)
        (.def (Child @ parent) name: 'child)
        (defvalues (evidence next failure) (.call publication .publish parent Child))
        (check-equal? failure #f)
        (check-equal? (.get evidence accepted?) #t)
        (check-eq? next (.get evidence candidate))
        (check-eq? (.get evidence admission-contract) (.get publication contract))
        (check-eq? (.get evidence context) (.get publication context))
        (check-equal? (.get next name) 'child)
        (check-equal? (.get parent name) 'published-backend)
        (check-eq? cached (.get parent load))
        (check-eq? (.get next load) (.get next load))
        (check-equal? ((.get trace calls)) 0)
        (def other-publication
          (.cc publication context: (.cc (.get publication context) marker: 'other)))
        (defvalues (rejected retained refusal)
          (metadata.publish (.call other-publication .bind-evidence next) parent
            (lambda (_) (values evidence next)) next))
        (check-equal? rejected #f)
        (check-eq? retained parent)
        (check-equal? (metadata.failure-phase refusal) 'logic)
        (def source (make-yuanxu-module-local-source 'request))
        (def plan (yuanxu-make-lazy-load-plan (list next) source))
        (check-eq? (.get next load) (.get (car (.get plan backends)) load))
        (def forced (yuanxu-force-lazy-load-plan plan))
        (check-equal? ((.get trace calls)) 1)
        (check-equal? (.get forced receipt code) 'loaded)
        (check-eq? source (.get forced receipt module request))
        (check-equal? (.get plan forced?) #f)
        (check-equal?
          (eq? (with-catch values
                 (lambda () ((.get next load) (make-yuanxu-module-local-source 'fail))))
               (.get trace failure)) #t)
        (check-equal? ((.get trace calls)) 2)))
    (yuanxu-test-fixture "malformed callback refuses before invocation"
      (fixture BackendPublicationFixture)
      (with-slots (record publication) fixture
        (def parent (.get publication value))
        (refused publication parent (.cc parent load: 17))
        (check-equal? ((.get record scope trace calls)) 0)))
    (yuanxu-test-fixture "cached publication still refuses changed role source"
      (fixture BackendPublicationFixture)
      (with-slots (root record selection publication) fixture
        (def parent (.get publication value))
        (.get parent load)
        (.get publication context)
        (write-source (path-expand "modules/fixture/backend/config.ss" root)
          "(.def Config name: 'changed)")
        (refused publication parent parent)
        (check-exception (.call AdmissionPublication. .for-export selection 'fixture/backend 'Backend) error?)
        (check-equal? ((.get record scope trace calls)) 0)
        ;; Already held Scheme procedures are not revoked by a source-file edit.
        ;; Admission currentness is not an execution sandbox or conditional commit.
        ((.get parent load) (make-yuanxu-module-local-source 'held))
        (check-equal? ((.get record scope trace calls)) 1)))))
