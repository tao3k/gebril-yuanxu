;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(.def PostgreSQL
  identity: 'services/postgresql
  core:
  (.o requires: (.o)
      scope-contract: PostgreSQLScopeContract
      exports: (.o (:: @ PostgreSQL.) config: Config document: Document
                 types: (.o port: Port Config: PostgreSQLConfigContract)))
  features: (.o))
