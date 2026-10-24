;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :yuanxu/ops/interface Ops) :clan/poo/object "./fixtures.ss"
        (only-in :yuanxu/observability/testing-script TestingScript. make-compiler-progress-reader)
        (only-in :yuanxu/module-system/source/admission module-source-read module-source-admit-current!)
        (only-in :std/source this-source-file))
(export Build InputChecks Fixture)
(def owner (path-expand "../../.." (path-directory (this-source-file))))
(def host-state (path-expand (gerbil-path)))
;; Lazy fixture data; declaring this object creates no fixture or process.
(.def Fixture
  value: (source-build-fixture owner)
  root: (.get value root)
  state: (.get value state)
  cold: (.get value cold))
;; Reuse the maintained Ops Script protocol. Only the test's .run starts it.
(.def (Build @ (.get Ops prototypes Script))
  progress: make-compiler-progress-reader
  idle-timeout: 60
  command: '("env" "-u" "CORE_QUALIFICATION_ROOT" "-u" "GERBIL_LOADPATH"
                  "-u" "SDKROOT" "gerbil" "-:max-heap=2G,debug=q" "env" "gxi" "build.ss")
  directory: (.get Fixture root)
  ;; Inherit the project's available-CPU setting; do not pin a worker count.
  ;; Complete build invocations remain sequential under the same watchdog.
  environment: (.o GERBIL_PATH: (.get Fixture state))
  timeout: 60
  check-status: #f)
;; Reuse the native source-currentness controls in a separate process too.
(.def (InputChecks @ TestingScript.)
  source:
  (let* ((file (path-normalize (path-expand "t/module-build-source-package-test.ss" owner)))
         (inputs (list (cons file (module-source-read file)))))
    (.o source-root: owner spec: (list file)
        admit-current: (cut module-source-admit-current! inputs)))
  directory: owner
  ;; Reuse the native Harness without selecting the same host init in another
  ;; Just layer. Keep the existing child deadlines; this is not more budget.
  timeout: (.get Build timeout)
  idle-timeout: (.get Build idle-timeout)
  ;; CLEAN removes the fixture's compiled Core. Bootstrap the test policy from
  ;; its host; source/context assertions still target the isolated fixture.
  environment: (.o GERBIL_PATH: host-state CORE_QUALIFICATION_ROOT: (.get Fixture root)))
