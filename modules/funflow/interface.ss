;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Declarative Core publication; role imports are produced by the module system.
(import (only-in :tao3k/yuanxu/module-system/source/declaration .def))
(.def Funflow
  identity: 'funflow
  tags: '(workflow)
  core:
  (.o scope-contract: FunflowScopeContract
      exports: (.o (:: @ FunflowModule.) config: Config))
  features: (.o))
