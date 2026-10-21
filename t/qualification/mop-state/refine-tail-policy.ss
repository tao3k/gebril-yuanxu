;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Refine only the dispatcher and test in an already captured private Core cut.
(import :gerbil/compiler (only-in :std/misc/ports read-all-as-string))
(def root (path-expand (getenv "CORE_SOURCE_TAIL_ROOT")))
(def core (path-expand (getenv "CORE_SOURCE_TAIL_CORE")))
(def relative "module-system/source/admission.ss")
(def path (path-expand (string-append "source/yuanxu/" relative) root))
(def text (call-with-input-file path read-all-as-string))
(def unrestricted
  "(def (observe-source kind (amount 1))\n  (when (current-module-source-observer)\n    ((current-module-source-observer) kind amount)))")
(def return-only
  "(def (observe-source kind (amount 1))\n  (when (current-module-source-observer)\n    (when (eq? (current-module-source-phase) 'return-currentness)\n      (error \"opaque source observer in return tail\"))\n    ((current-module-source-observer) kind amount)))")
(def segment
  "(def (observe-source kind (amount 1))\n  (when (current-module-source-observer)\n    (when (memq (current-module-source-phase) '(slot-replay return-currentness))\n      (error \"opaque source observer in return tail\"))\n    ((current-module-source-observer) kind amount)))")
(def policy (getenv "CORE_SOURCE_TAIL_POLICY" "segment"))
(def candidate
  (cond ((string=? policy "segment") segment)
        ((string=? policy "return-only") return-only)
        ((string=? policy "unrestricted") unrestricted)
        (else (error "unknown isolated dispatcher policy" policy))))
(def matches (filter (cut string-contains text <>) (list unrestricted return-only segment)))
(unless (= (length matches) 1) (error "ambiguous captured dispatcher"))
(def original (car matches))
(def offset (string-contains text original))
(call-with-output-file (list path: path truncate: #t)
  (lambda (port)
    (display (substring text 0 offset) port)
    (display candidate port)
    (display (substring text (+ offset (string-length original)) (string-length text)) port)))
(def target
  (if (string=? policy "unrestricted") "t/source-admission-closed-tail-test.ss"
    "t/source-admission-gateway-test.ss"))
(call-with-output-file (list path: (path-expand (string-append "source/yuanxu/" target) root) truncate: #t)
  (lambda (port)
    (display (call-with-input-file (path-expand target core) read-all-as-string) port)))
(for-each
  (lambda (name)
    (compile-module (path-expand (string-append "source/yuanxu/" name) root)
      [output-dir: (path-expand "lib" root) invoke-gsc: #t keep-scm: #t])
    (execute-pending-compile-jobs!))
  (list relative target))
(displayln "SOURCE-TAIL-POLICY-COMPILED: " policy)
