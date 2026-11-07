;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Exercise the actual source-only root entry without a whole Core compile.
(import :std/test
        (only-in :std/error Error? Error-message)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :gerbil/expander eval-syntax current-expander-context
                 make-top-context syntax->list)
        (only-in :yuanxu/module-system/source/admission module-source-read))
(export core-build-entry-test)
(def root (getenv "CORE_QUALIFICATION_ROOT" #f))
(def (script-main path)
  (parameterize ((current-expander-context (make-top-context)))
    (eval-syntax '(import :gerbil/core))
    (for-each eval-syntax (syntax->list (read-syntax-from-file path)))
    (eval-syntax 'main)))
(def (write-source path text)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))
(def (rejects? pattern thunk)
  (with-catch
    (lambda (exception)
      (let (text (if (Error? exception) (Error-message exception) ""))
        (if (pregexp-match pattern text) #t
            (begin (displayln "UNEXPECTED-REJECTION " text) #f))))
      (lambda () (thunk) #f)))
  (def (spec-of run)
    (call-with-input-string
      (call-with-output-string
        (lambda (out) (parameterize ((current-output-port out)) (run "spec")))) read))
  (def (target-name target)
    (if (string? target) target (cadr target)))
  (def core-build-entry-test
    (if root
    (test-suite "Actual Core entry delegates to Module System Building"
      (test-case "cold source entry selects JsonSchema and rechecks input bytes"
        (check-equal? (file-exists? (path-expand "lib/yuanxu" (getenv "GERBIL_PATH"))) #f)
        (check-equal? (file-exists? (path-expand "bootstrap.ss" root)) #f)
        (def run (script-main (path-expand "build.ss" root)))
        (displayln "ROOT-ENTRY-READY") (force-output)
        (def spec (spec-of run))
        (def names (map target-name spec))
        (let (seen (make-hash-table))
          (for-each (lambda (name)
                      (check-equal? (hash-key? seen name) #f)
                      (hash-put! seen name #t)) names))
        (for-each
          (lambda (name)
            (check-equal? (length (filter (cut equal? <> name) names)) 1))
          '("modules/json-schema/types" "modules/json-schema/config"
            "modules/json-schema/func" "modules/json-schema/objects"
            "modules/json-schema/interface" "object-types/contracts" "utilities/algorithms"
            "module-system/building/interface" "core-spec"))
        (check-equal?
          (filter (lambda (name)
                    (or (string-prefix? "modules/nix/" name)
                        (string-prefix? "modules/opentofu/" name)
                        (string-prefix? "modules/building/" name))) names) '())
        (for-each
          (lambda (control)
            (let* ((path (path-expand (car control) root)) (text (module-source-read path)))
              (dynamic-wind
                (lambda () (write-source path (string-append text "\n;; changed after preparation\n")))
                (lambda ()
                  (check-equal?
                    (rejects? (cdr control)
                              (lambda () (run "spec"))) #t))
                (lambda () (write-source path text)))))
          '(("build.ss" . "stale selected build input")
            ("core-spec.ss" . "stale prepared build source")
            ("object-types/contracts.ss" . "compiler tool source changed; use a fresh reader")))
        (check-equal? (spec-of run) spec)
        (def fresh (script-main (path-expand "build.ss" root)))
        (check-equal? (spec-of fresh) spec)
        (fresh "clean")
        (let* ((path (path-expand "init.ss" root)) (text (module-source-read path)))
          (dynamic-wind
            (lambda () (write-source path (string-append text "\n;; changed selection\n")))
            (lambda ()
              (check-equal? (rejects? "stale module scope generation"
                                     (lambda () (fresh "spec"))) #t))
            (lambda () (write-source path text))))
        ;; Init generation drift refuses the selected session permanently, even
        ;; after restoration. It cannot be revived by restoring bytes.
        (check-equal? (rejects? "module scope session was refused"
                               (lambda () (fresh "spec"))) #t)
        (check-equal? (file-exists? (path-expand "lib/yuanxu" (getenv "GERBIL_PATH"))) #f)
        (displayln "ROOT-ENTRY-SELECTED-TARGETS " (length spec))))
    (begin
      (displayln "SKIP core-build-entry: CORE_QUALIFICATION_ROOT is unset")
      (test-suite "core-build-entry (source-only opt-in)" (void)))))
