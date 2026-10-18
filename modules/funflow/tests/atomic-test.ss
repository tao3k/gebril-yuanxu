;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :core/object-syntax/path-slots
        (only-in :clan/poo/object .get .call .ref/cached)
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :core/modules/funflow/objects Job. Task.)
        (only-in :core/observability/testing-fixture poo-flow-test-fixture))
(export funflow-atomic-test)
(.def Workspace
  .acquire: (lambda () (let (directory (make-temporary-file-name "funflow-atomic-"))
                         (create-directory directory) directory))
  .release: clear-temporary-file!)
(.def (Build @ Job.)
  tasks: (.o build: (.o (:: @ Task.) command: '("printf" "build"))
             unused: (error "unselected task was forced"))
  selected: '(build))
(def funflow-atomic-test
  (test-suite "Funflow module atomic Job"
    (poo-flow-test-fixture "cached parent graph keeps child values and unused tasks lazy" (workspace Workspace)
      (def parent (.get Build graph))
      (.def (Release @ Build)
        tasks.build.command: '("printf" "release"))
      (check-equal? (.get (.call Release .run workspace) steps build output) "release")
      (check-equal? (.ref/cached (.get Release tasks) 'unused) #f)
      (check-equal? (.get Build tasks build command) '("printf" "build")))))
