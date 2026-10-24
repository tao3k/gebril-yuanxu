;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Built-in Core library. Importing or obtaining a Script never executes it.
(import "./config.ss" "./types.ss" "./func.ss" "./objects.ss")
(export Ops)
(.def Ops
  config: Config
  types: (.o ProcessScript: ProcessScriptContract ProcessResult: ProcessResultContract Config: OpsConfigContract
             Environment: OpsEnvironmentContract)
  validate: validate-script
  prepare-command: prepare-script-command
  merge-environment: merge-script-environment
  preview: preview-script
  run: run-script
  prototypes:
  (.o Script: (.cc ProcessScript. 'config config)
      SelectedPackages: SelectedPackages.))
