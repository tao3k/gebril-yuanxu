;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Exercise the ordinary Core entry and the separate selected projection.
(import :std/test
        (only-in :tao3k/yuanxu/module-system/building/build-projection yuanxu-project-source-spec)
        (only-in :clan/poo/object .get .call .o)
        (only-in :std/source this-source-file)
        (only-in "./qualification/module-testing/fixtures.ss" selection-fixture)
        (only-in :std/error Error? Error-message)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :gerbil/expander eval-syntax current-expander-context
                 import-module)
        (only-in "./qualification/module-init/fixture.ss" import-fixture-init!)
        (only-in :tao3k/yuanxu/module-system/source/admission module-source-read))
(export core-build-entry-test test-setup! test-cleanup!)
(def Fixture (selection-fixture (path-expand ".." (path-directory (this-source-file)))))
(def resource #f)
(def root #f)
(def (test-setup!)
  (set! resource (.call Fixture .acquire))
  (set! root (.get resource root)))
(def (test-cleanup!)
  (when resource
    (begin0 (.call Fixture .release resource)
      (set! resource #f) (set! root #f))))
(def (script-main path (fresh? #f))
  (when fresh?
    (import-fixture-init! (path-expand "init.ss" (path-directory path)) #t))
  (parameterize ((current-expander-context (import-module path #t #t)))
    (def libraries (eval-syntax 'core-spec))
    (values (eval-syntax 'main) libraries
      (yuanxu-project-source-spec (path-expand "init.ss" root) libraries root path))))
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
    (test-suite "Core build entry and selected Module projection"
      (test-case "Core builds libraries and selected projection rechecks input bytes"
        (check-equal? (file-exists? (path-expand "lib/tao3k/yuanxu" (getenv "GERBIL_PATH"))) #f)
        (check-equal? (file-exists? (path-expand "bootstrap.ss" root)) #f)
        (defvalues (run libraries package) (script-main (path-expand "build.ss" root)))
        (displayln "ROOT-ENTRY-READY") (force-output)
        (def spec (spec-of run))
        (check-equal? spec libraries)
        (check-equal? (member "modules/json-schema/interface" (map target-name spec)) #f)
        (def selected-spec (.get package spec))
        ;; The projection owns the selected and retained target lists.
        (.call package .admit-spec selected-spec)
        (def names (map target-name selected-spec))
        (let (seen (make-hash-table))
          (for-each (lambda (name)
                      (check-equal? (hash-key? seen name) #f)
                      (hash-put! seen name #t)) names))
        (for-each
          (lambda (name)
            (check-equal? (cons name (length (filter (cut equal? <> name) names))) (cons name 1)))
          '("modules/json-schema/types" "modules/json-schema/config"
            "modules/json-schema/func" "modules/json-schema/objects"
            "modules/json-schema/interface" "types/contracts" "utilities/algorithms"
            "core-spec"))
        ;; Source tooling prepares the spec but is not a retained runtime target.
        (check-equal? (member "module-system/building/interface" names) #f)
        (check-equal? (member "module-system/building/script" names) #f)
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
                  (def entered? #f)
                  (check-equal?
                    (rejects? (cdr control)
                      (lambda ()
                        (.call package .compile
                          (path-expand "lib" (getenv "GERBIL_PATH"))
                          (lambda () (set! entered? #t) (run "compile"))))) #t)
                  (check-equal? entered? #f))
                (lambda () (write-source path text)))))
          '(("build.ss" . "stale selected build input")
            ("core-spec.ss" . "stale prepared build source")
            ("types/contracts.ss" . "compiler tool source changed; use a fresh reader")))
        (check-equal? (spec-of run) spec)
        (defvalues (fresh _fresh-libraries fresh-package) (script-main (path-expand "build.ss" root) #t))
        (check-equal? (spec-of fresh) spec)
        (fresh "clean")
        (let* ((path (path-expand "init.ss" root)) (text (module-source-read path)))
          (dynamic-wind
            (lambda () (write-source path (string-append text "\n;; changed selection\n")))
            (lambda ()
              (check-equal? (rejects? "stale module scope generation"
                                     (.get fresh-package admit-current)) #t))
            (lambda () (write-source path text))))
        ;; Init generation drift refuses the selected session permanently, even
        ;; after restoration. It cannot be revived by restoring bytes.
        (check-equal? (rejects? "module scope session was refused"
                               (.get fresh-package admit-current)) #t)
        (check-equal? (file-exists? (path-expand "lib/tao3k/yuanxu" (getenv "GERBIL_PATH"))) #f)
        (displayln "ROOT-ENTRY-SELECTED-TARGETS " (length spec)))))
