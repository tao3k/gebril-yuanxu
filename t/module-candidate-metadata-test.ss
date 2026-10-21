;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in "./module-candidate-stage-test" with-other-source)
        (only-in "./module-publication-test" write-file)
        (only-in :core/module-system/source/publication ModulePublicationContract)
        (only-in :core/module-system/source/admission poo-flow-default-module-style-policy)
        (only-in :core/observability/testing-case poo-flow-test-case))
(export module-candidate-metadata-test)
(def (stale-metadata? failure)
  (and (Error? failure) (string=? (Error-message failure) "stale module publication policy")))

(def module-candidate-metadata-test
  (test-suite "Native candidate evidence is current before Graph visibility"
    (poo-flow-test-case "initializer scratch queries are not enduring admission requirements"
      (with-other-source
        (lambda (root first _other)
          (write-file (path-expand "init.ss" root)
            "(poo-flow! mode: explicit :custom (example) (other))")
          ;; Real native construction, not a fake evidence/currentness closure.
          ;; The old whole-interpreter replay incorrectly retained this query.
          (write-file (path-expand "config.ss" first)
            "(import (only-in :clan/poo/object .o .slot? .put!)) (def Scratch (.o)) (.slot? Scratch 'identity) (.put! Scratch 'identity 'temporary) (def Greeting \"hello\") (export Greeting)"))
        (lambda (_root _first _other view)
          (def graph (.get view selected-graph))
          (check-equal? (.get graph status) 'ready)
          (check-equal? (length (.get graph module-order)) 2)
          (.call view sources-current)
          (check-equal? (eq? graph (.get view selected-graph)) #t))))
    (poo-flow-test-case "policy and actual Contract edits cannot publish an earlier candidate"
      ;; Policy first: the default Contract remains unchanged for the second
      ;; schedule. Restoring a value does NOT restore its native revision.
      (for-each
        (lambda (kind)
          (def target (if (eq? kind 'policy)
                        poo-flow-default-module-style-policy ModulePublicationContract))
          (def slot (if (eq? kind 'policy) 'validate '.obligations))
          (def previous (.ref target slot))
          (dynamic-wind
            void
            (lambda ()
              (with-other-source
                (lambda (root _first other)
                  (write-file (path-expand "init.ss" root)
                    "(poo-flow! mode: explicit :custom (example) (other))")
                  (write-file (path-expand "config.ss" other)
                    (if (eq? kind 'policy)
                      "(import (only-in :clan/poo/object .ref .put!) (only-in :core/module-system/source/admission poo-flow-default-module-style-policy)) (.put! poo-flow-default-module-style-policy 'validate (.ref poo-flow-default-module-style-policy 'validate)) (def Greeting \"other\") (export Greeting)"
                      (string-append
                        "(import (only-in :clan/poo/object .put!) (only-in :core/module-system/source/publication ModulePublicationContract)) "
                        "(.put! ModulePublicationContract '.obligations (lambda (_value _context) (call-with-output-file "
                        (object->string (path-expand "must-not-call" root))
                        " (lambda (p) (display \"called\" p))) '())) "
                        "(def Greeting \"other\") (export Greeting)"))))
                (lambda (root _first _other view)
                  ;; An auto directory has no selected roots. Force the two
                  ;; actual declarations through init before testing commit.
                  (check-exception (.get view selected-graph) stale-metadata?)
                  (check-equal? (.ref/cached view 'selected-graph) #f)
                  ;; The replacement obligation is a negative injection. The
                  ;; complete epoch guard must refuse BEFORE invoking it.
                  (check-equal? (file-exists? (path-expand "must-not-call" root)) #f))))
            (lambda () (.put! target slot previous))))
        '(policy contract)))))
