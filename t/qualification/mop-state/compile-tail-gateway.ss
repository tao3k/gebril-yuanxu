;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Compile exactly one temporary source-event gateway; never edit installed Core.
(import :gerbil/compiler :gerbil/expander (only-in :std/misc/ports read-all-as-string))
(def root (path-expand (getenv "CORE_SOURCE_TAIL_ROOT")))
(def core (path-expand (getenv "CORE_SOURCE_TAIL_CORE")))
(def original
  "(def (observe-source kind (amount 1))\n  (when (and (symbol? kind) (current-module-source-operation-times))\n    (hash-update! (current-module-source-operation-times) (list 'source kind)\n      (cut + <> amount) 0))\n  (when (current-module-source-observer)\n    ((current-module-source-observer) kind amount)))")
(def candidate
  "(def (observe-source kind (amount 1))\n  (when (and (symbol? kind) (current-module-source-operation-times))\n    (hash-update! (current-module-source-operation-times) (list 'source kind)\n      (cut + <> amount) 0))\n  (when (current-module-source-observer)\n    (when (memq (current-module-source-phase) '(slot-replay return-currentness))\n      (error \"opaque source observer in return tail\"))\n    ((current-module-source-observer) kind amount)))")
;; Snapshot current runtime sources as one coherent package. A single relocated
;; Core library mixed with live source imports is correctly refused by the reader.
;; Copy source/data roles, not compiled artifacts or a frozen older qualification.
(def source-core (path-expand "source/yuanxu/" root))
(def (snapshot directory relative)
  (for-each
    (lambda (name)
      (unless (member name '(".git" ".gerbil" ".cache" ".lake" ".data" "docs" "dev"))
        (let ((input (path-expand name directory)) (local (string-append relative name)))
          (if (eq? (file-info-type (file-info input #f)) 'directory)
            (snapshot input (string-append local "/"))
            (when (or (member (path-extension name) '(".ss" ".scm" ".json"))
                      (string=? name "gerbil.pkg"))
              (let (output (path-expand local source-core))
                (create-directory* (path-directory output))
                (call-with-output-file output
                  (lambda (port) (display (call-with-input-file input read-all-as-string) port)))))))))
    (directory-files directory)))
(snapshot core "")
(def path (path-expand "source/yuanxu/module-system/source/admission.ss" root))
(def text (call-with-input-file (path-expand "module-system/source/admission.ss" core) read-all-as-string))
(def offset (string-contains text original))
(unless offset (error "source event gateway changed; re-audit before qualification"))
(when (string-contains (substring text (+ offset (string-length original)) (string-length text)) original)
  (error "ambiguous source event gateway"))
(create-directory* (path-directory path))
(create-directory* (path-expand "lib" root))
(call-with-output-file (list path: path truncate: #t)
  (lambda (port)
    (display (substring text 0 offset) port)
    (display candidate port)
    (display (substring text (+ offset (string-length original)) (string-length text)) port)))
(def original-import (current-expander-module-import))
(def seen (make-hash-table-eq))
;; The package has one ordinary namespace and one explicitly named prelude.
;; Route both to the same snapshot; never mix the host's prelude into its clone.
(def (snapshot-source name)
  (cond
    ((equal? name "tao3k/yuanxu/prelude") (path-expand "prelude.ss" source-core))
    ((and name (string-prefix? "yuanxu/" name))
     (path-expand (string-append (substring name (string-length "yuanxu/") (string-length name)) ".ss") source-core))
    (else #f)))
(def (source-import path (reload? #f))
  (def datum (syntax-e path))
  (def name (and (symbol? datum) (symbol->string datum)))
  (def source (and name (string-prefix? ":" name)
                     (snapshot-source (substring name 1 (string-length name)))))
  (original-import (if (and source (file-exists? source)) source path) reload?))
(def (visit context)
  (cond
    ((module-import? context) (visit (module-import-source context)))
    ((module-export? context) (visit (module-export-context context)))
    ((import-set? context) (visit (import-set-source context)))
    ((and (module-context? context) (not (hash-key? seen context)))
     (hash-put! seen context #t)
     (for-each visit (module-context-import context))
     (let* ((identity (expander-context-id context))
            (name (and (symbol? identity) (symbol->string identity)))
            (source (snapshot-source name)))
       (when (and source (file-exists? source))
         (displayln "SOURCE-TAIL-COMPILE " name) (force-output)
         (compile-module source [output-dir: (path-expand "lib" root)
                                 ;; Match the installed native Make cohort:
                                 ;; callers may use its optimized entry names.
                                 optimize: #t generate-ssxi: #t
                                 invoke-gsc: #t keep-scm: #t parallel: #t]))))))
(parameterize ((current-expander-context (make-top-context))
               (current-expander-module-import source-import))
  ;; The Harness imports init at runtime, and test-projection deliberately
  ;; delays TestingScript until .run. Compile those actual roots as well as
  ;; the test body; a static walk of the body alone misses their Core imports.
  ;; This prepares code only: no Script or selected business scope executes.
  (visit (core-import-module (path-expand "init.ss" source-core)))
  (visit (core-import-module (path-expand "observability/testing-script.ss" source-core)))
  (visit (core-import-module (path-expand "t/source-admission-gateway-test.ss" source-core)))
)
(execute-pending-compile-jobs!)
(displayln "SOURCE-TAIL-GATEWAY-COMPILED: one temporary dispatcher; current source import closure")
