;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :yuanxu/ops/interface Ops) :clan/poo/object "./fixtures.ss"
        (only-in :yuanxu/observability/testing-script make-compiler-progress-reader)
        (only-in :std/source this-source-file))
(export Build Fixture)
(def owner (path-expand "../../.." (path-directory (this-source-file))))
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
                  "-u" "SDKROOT" "gerbil" "-:max-heap=2G,debug=q" "build.ss")
  directory: (.get Fixture root)
  ;; Inherit the project's available-CPU setting; do not pin a worker count.
  ;; Complete build invocations remain sequential under the same watchdog.
  environment: (.o GERBIL_PATH: (.get Fixture state))
  timeout: 60
  check-status: #f)
