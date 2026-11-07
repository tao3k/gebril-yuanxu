;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object "./process-script.ss" "./selected-packages.ss"
        (only-in "./func.ss" run-script-batch))
(export ProcessScript. ScriptBatch. SelectedPackages.)
(.def (ScriptBatch. batch [])
  scripts: '()
  concurrency: 1
  .run: (lambda () (run-script-batch batch)))
