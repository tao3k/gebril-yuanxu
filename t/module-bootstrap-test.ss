;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source-only Graph admission is independent of compiler execution.
(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :std/source this-source-file)
        (only-in :clan/poo/object .get .call .o)
        (only-in :core/types poo-flow-contract-admit poo-flow-validation-evidence-accepted?)
        (only-in :core/module-system/interface poo-flow-load-modules))
(export module-bootstrap-test)
(def root (path-expand ".." (path-directory (this-source-file))))
(def module-bootstrap-test
  (test-suite "Source tool consumes uncompiled JsonSchema publication"
    (test-case "init selects a source Graph and exposes the declared Contract"
      (let* ((view (poo-flow-load-modules (path-expand "init.ss" root)))
             (graph (.get view build-graph))
             (scope (.get view modules Modules json-schema))
             (contract (.call scope contract 'bootstrap/value
                         '((type . "object") (required . ("value"))
                           (properties . ((value . ((type . "string")))))))))
        (check-equal? (.get view selected-graph module-order)
                      '(json-schema ops funflow nix opentofu null aws-validation aws))
        (check-equal? (> (length (.get graph entries)) 15) #t)
        (check-equal? (poo-flow-validation-evidence-accepted?
                       (poo-flow-contract-admit contract (.o value: "pass") #f)) #t)
        (check-equal? (poo-flow-validation-evidence-accepted?
                       (poo-flow-contract-admit contract (.o value: 7) #f)) #f)))))
