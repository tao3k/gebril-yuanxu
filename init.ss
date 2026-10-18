;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import "./module-system/selection/init-syntax.ss")

;; One selection epoch owns both windows. Mount names affect access paths;
;; requirements continue to use the original publication identities.
(poo-flow!
  :load-modules "./modules" mode: explicit rename: Modules
  (json-schema)
  (funflow)
  (nix)
  (opentofu)
  (ops @ "./ops")

  ;; Scenario declarations share the Graph and lazy test projection.
  ;; Selection does not realize providers or link business scopes.
  :load-modules "./scenarios" mode: explicit rename: Scenarios
  (null)
  (aws-validation)
  (aws))
