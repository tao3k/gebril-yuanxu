;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(.def BackendModule
  identity: 'fixture/backend
  core: (.o requires: (.o) scope-contract: BackendScopeContract
            admissions: (.o Backend: (.o export-path: '(Backend)
                                         contract-path: '(types Admission)))
            exports: (backend-scope Config))
  features: (.o))
