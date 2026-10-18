;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object "./func.ss" "./config.ss" "./selected-packages.ss")
(export ProcessScript. SelectedPackages.)
(.def (ProcessScript. script [])
  command: '()
  config: Config
  directory: (.get config directory)
  environment: (.get config environment)
  timeout: (.get config timeout)
  log: (.get config log)
  check-status: (.get config check-status)
  .run: (lambda arguments (run-script script arguments)))
