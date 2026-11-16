;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Process execution does not import package selection or the build Graph.
(import :clan/poo/object "./config.ss"
        (only-in :clan/poo/type Function validate String)
        (only-in "./types.ss" ProcessResultContract)
        (for-template "./func.ss")
        (only-in :tao3k/yuanxu/module-system/source/compiled-role
                 bind-deferred-interfaces deferred-interface-values)
        (only-in :tao3k/yuanxu/module-system/source/module-binding module-binding-action))
(export ProcessScript.)

(bind-deferred-interfaces "./func.ss")

;; A script prototype and its contract can be inspected without initializing
;; process execution. Only calling an effectful slot demands the native owner.
(def script-runtime
  (.o operations: (deferred-interface-values
                    "./func.ss" tao3k/yuanxu/ops/func
                    (run-script call-with-script-coprocess) module-binding-action)))

(.def (ProcessScript. script [])
  command: '()
  config: Config
  directory: (.get config directory)
  environment: (.get config environment)
  timeout: (.get config timeout)
  idle-timeout: (.get config idle-timeout)
  progress: (.get config progress)
  log: (.get config log)
  check-status: (.get config check-status)
  .run: (validate (Function (list ProcessResultContract) '() rest: String)
          (lambda arguments ((.get script-runtime operations run-script) script arguments)))
  .with-process:
  (lambda (exchange)
    ((.get script-runtime operations call-with-script-coprocess) script exchange)))
