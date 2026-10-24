;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Process execution does not import package selection or the build Graph.
(import :clan/poo/object "./func.ss" "./config.ss"
        (only-in :clan/poo/mop Function validate)
        (only-in :clan/poo/type String)
        (only-in "./types.ss" ProcessResultContract))
(export ProcessScript.)
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
          (lambda arguments (run-script script arguments))))
