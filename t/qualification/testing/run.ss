;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; A command-line projection of the maintained TestingScript policy.
(import :clan/poo/object
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax core-read-module/sexp)
        (only-in :yuanxu/module-system/source/init module-init-export-name))

(def (main file vm-options seconds observation (harness #f))
  (unless (member observation '("false" "true" "trace"))
    (error "observe must be false, true, or trace" observation))
  (def budget (string->number seconds))
  (unless (and (exact-integer? budget) (> budget 0))
    (error "test budget must be a positive number of seconds" seconds))
  (def started (real-time))
  (def exports
    (parameterize ((current-expander-context (make-top-context)))
      (eval-syntax '(import :gerbil/core))
      (let* ((path (path-expand "init.ss")))
        (let-values (((_prelude identity _namespace _body) (core-read-module/sexp path)))
          (let (binding (module-init-export-name identity))
            (eval-syntax `(import (only-in ,path ,binding)))
            (eval-syntax binding))))))
  (unless (equal? observation "false")
    (displayln "test-entry phase=init seconds=" (- (real-time) started)))
  ;; The init import already owns this module. Its measurement function owns
  ;; the scalar table; do not activate source/slot observers during selection.
  (def measure-selection
    (and (not (equal? observation "false"))
      (parameterize ((current-expander-context (make-top-context)))
        (eval-syntax '(import :gerbil/core))
        (eval-syntax '(import (only-in :yuanxu/module-system/source/admission
                               call-with-module-source-operation-measurement)))
        (eval-syntax 'call-with-module-source-operation-measurement))))
  (def (select-files) (.call (.get exports tests) .for-files (list file)))
  (defvalues (demand operation-times)
    (if measure-selection (measure-selection select-files)
      (values (select-files) #f)))
  (unless (equal? observation "false")
    (displayln "test-entry phase=selection seconds=" (- (real-time) started)))
  (def (report-selection label times)
    (for-each
      (lambda (name)
        (displayln "test-selection sample=" label " phase=" name " seconds=" (or (hash-get times name) 0)
          " calls=" (or (hash-get times (list 'calls name)) 0)
          " metrics=" (map (lambda (metric) (cons metric (or (hash-get times (list metric name)) 0)))
                         '(visits characters cpu-user cpu-system wall-cpu-gap gc-user gc-system gc-wall
                           collections minor-faults major-faults vm-account accounting-invalid))))
      '(linker-import context directory-context selection-current selected-graph
        reader-bootstrap publication-read publication-admission candidate-read link-current reader-current
        reader-location-start reader-preparation-start reader-interface-start
        reader-compile-start reader-eval-start reader-admission-start metadata-replay source-read))
    (displayln "test-selection sample=" label " source="
      (map (lambda (kind) (cons kind (or (hash-get times (list 'source kind)) 0)))
        '(stats checks read-windows read-requests reads query-hits query-misses
          source-comparisons source-comparison-hits))))
  (when operation-times (report-selection 'cold operation-times))
  ;; Trace explicitly probes a second demand in this same VM. A new demand
  ;; does not inherit a verdict; selected! checks sources before the native
  ;; cached graph read. Do not add this diagnostic work to ordinary test runs.
  (when (equal? observation "trace")
    (let loop ((sample 1))
      (when (<= sample 20)
        (let-values (((warm warm-times) (measure-selection select-files)))
          (unless (eq? (.get demand selected-graph) (.get warm selected-graph))
            (error "selection probe did not reuse its native graph receiver"))
          (report-selection sample warm-times))
        (loop (+ sample 1)))))
  (.def (Test @ (.get demand execution))
    runtime-options: (list vm-options)
    profile: =>.+
    (.o max-duration-milliseconds: (* 1000 budget)
        emit?: (not (equal? observation "false"))
        trace-enabled?: (equal? observation "trace")))
  (def selected
    (if harness
      (.cc Test 'harness harness 'idle-timeout #f 'command (list "gxi" vm-options file))
      Test))
  (def result (.call selected .run))
  (unless (equal? observation "false")
    ;; Ops already measures the native command. Do not add another timer or
    ;; runner; subtract observed Case spans to locate harness import/setup.
    (displayln "test-entry phase=native-harness seconds=" (.get result seconds)))
  (unless (equal? observation "false")
    (displayln "test-entry phase=total seconds=" (- (real-time) started)))
  (display (.get result output)))

;; gxi invokes main after loading the script; never invoke it again here.
