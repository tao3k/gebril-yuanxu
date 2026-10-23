;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import "./module-system/selection/init-syntax.ss")

;; One selection epoch owns both windows. Mount names affect access paths;
;; requirements continue to use the original publication identities.
(yuanxu!
  :load-modules "./modules" mode: explicit rename: Modules
  (json-schema)
  (funflow)

  ;; Same module protocol, separate window. Library roots never own Scenarios.
  :load-modules "./scenarios" mode: explicit rename: Scenarios
  :services
  (postgresql @ "./scenarios/gitea-postgresql/postgresql")
  (gitea @ "./scenarios/gitea-postgresql/gitea")
  :applications
  (gitea-postgresql @ "./scenarios/gitea-postgresql"))
