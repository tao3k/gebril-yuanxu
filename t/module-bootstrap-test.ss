;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; This gate intentionally needs no Core testing library outside the tool closure.
(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :clan/poo/object .get .call .o)
        (only-in :core/types poo-flow-contract-admit poo-flow-validation-evidence-accepted?)
        (only-in :core/module-system/interface poo-flow-load-modules)
        (only-in :core/modules/building/build-projection poo-flow-core-write-build-entry))
(export module-bootstrap-test)
(def root (path-expand ".." (path-directory (this-source-file))))
(def (remove-tree path)
  (if (eq? (file-info-type (file-info path #f)) 'directory)
    (begin (for-each (lambda (name) (remove-tree (path-expand name path))) (directory-files path))
           (delete-directory path)) (delete-file path)))
(def module-bootstrap-test
  (test-suite "Bootstrap tool consumes uncompiled JsonSchema publication"
    (test-case "init, selected Graph, native Contract and build entry"
      (let ((view (poo-flow-load-modules (path-expand "init.ss" root)))
            (output (make-temporary-file-name "bootstrap-selected-")))
        (dynamic-wind
         void
         (lambda ()
           (check-equal? (.get view selected-graph module-order) '(json-schema))
           (let* ((artifact (poo-flow-core-write-build-entry view output))
                  (scope (.get view modules json-schema))
                  (contract (.call scope contract 'bootstrap/value
                              '((type . "object") (required . ("value"))
                                (properties . ((value . ((type . "string")))))))))
             (check-equal? (> (length (.get artifact spec)) 15) #t)
             (check-equal? (poo-flow-validation-evidence-accepted?
                            (poo-flow-contract-admit contract (.o value: "pass") #f)) #t)
             (check-equal? (poo-flow-validation-evidence-accepted?
                            (poo-flow-contract-admit contract (.o value: 7) #f)) #f)))
         (lambda () (when (file-exists? output) (remove-tree output))))))))
