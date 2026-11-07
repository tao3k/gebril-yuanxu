;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Explicit module test inputs and native compiler specifications; no executor.
(import :std/test :clan/poo/object
        (only-in :gerbil/expander core-resolve-library-module-path __module-registry
                 core-import-module expander-context-id module-context-path)
        (only-in :yuanxu/module-system/building/source-closure for-each-build-module)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/source this-source-file)
        (only-in "../init.ss" yuanxu.init.exports))
(export init-test-input-test)

;; Rewrite only fixture bytes; assertions stay outside the exception catcher.
(def (put path text)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))
(def (refuses? operation)
  (with-catch (lambda (_) #t) (lambda () (operation) #f)))
(def tests (.get yuanxu.init.exports tests))
(def init-test-input-test
  (test-suite "Init-owned explicit test inputs"
    (test-case "support discovery expands generated imports without publishing Suite bodies"
      (def root (path-normalize (path-expand ".." (path-directory (this-source-file)))))
      (call-with-temporary-directory (path-expand "t/qualification/analysis-context-" root)
        (lambda (directory)
          (def helper (path-expand "support.ss" directory))
          (def phase (path-expand "phase.ss" directory))
          (def file (path-expand "probe-test.ss" directory))
          (put helper "(export value) (def value 7)\n")
          (put phase "(export enabled?) (def enabled? #t)\n")
          (put file
            "(import :std/test (phi: +1 \"./phase.ss\"))\n(defsyntax (use-support stx) (if enabled? #'(import \"./support.ss\") #'(begin)))\n(use-support)\n(error \"analysis evaluated the Suite runtime body\")\n(export probe-test)\n(def probe-test (test-suite \"generated imports\" (test-case \"value\" (check-equal? value 7))))\n")
          (check-equal? (hash-get __module-registry file) #f)
          (def build (.get (.call tests .for-files (list file)) build))
          ;; The native importer owns the dependency, but analysis does not
          ;; install the requesting Suite or a delayed evaluator for its body.
          (check-equal? (hash-get __module-registry file) #f)
          (check-equal? (and (hash-get __module-registry helper) #t) #t)
          (check-equal? (and (assoc helper (.get build source-inputs)) #t) #t)
          (def canonical (core-import-module file))
          (check-equal? (eq? (hash-get __module-registry file) canonical) #t)
          (check-equal? (eq? (hash-get __module-registry (expander-context-id canonical)) canonical) #t)
          (def expected '())
          (for-each-build-module canonical
            (lambda (context)
              (def path (module-context-path context))
              (when (member path (list helper phase))
                (set! expected
                  (cons (path-strip-extension
                          (substring path
                            (string-length (string-append (path-strip-trailing-directory-separator root) "/"))
                            (string-length path))) expected)))))
          ;; Compare the complete ordered local dependency projection with the
          ;; official importer, including a macro-generated and a phase-1 edge.
          (check-equal? (length expected) 2)
          (check-equal? (map cadr (.get build spec)) (reverse expected))
          (def next-helper (path-expand "next.ss" directory))
          (put next-helper "(export value) (def value 9)\n")
          (put file "(import :std/test \"./next.ss\") (export probe-test) (def probe-test (test-suite \"new dependency\" (test-case \"value\" (check-equal? value 9))))\n")
          (check-exception ((.get build admit-current)) error?)
          (def next-build (.get (.call tests .for-files (list file)) build))
          (check-equal? (length (.get next-build spec)) 1)
          (check-equal? (and (assoc next-helper (.get next-build source-inputs)) #t) #t)
          (check-equal? (assoc helper (.get next-build source-inputs)) #f)
          ;; Do not evict or replace the real loader's already registered copy.
          (check-equal? (eq? (hash-get __module-registry file) canonical) #t)
          (put helper "(export value) (def value 8)\n")
          (check-exception ((.get build admit-current)) error?))))
    (test-case "installed library stays an observed interface, local support stays source"
      (def root (path-expand ".." (path-directory (this-source-file))))
      (call-with-temporary-directory (path-expand "t/qualification/library-boundary-" root)
        (lambda (directory)
          (def helper (path-expand "helper.ss" directory))
          (def file (path-expand "probe-test.ss" directory))
          (put helper "(import (only-in :yuanxu/ops/interface Ops) (only-in :clan/poo/object .get)) (export answer) (def answer (.get Ops config timeout))\n")
          (put file "(import \"./helper.ss\") (export answer)\n")
          (def build (.get (.call tests .for-files (list file)) build))
          (def target (path-strip-extension
            (substring helper (string-length (string-append (path-strip-trailing-directory-separator root) "/"))
                              (string-length helper))))
          (check-equal? (.get build spec) (list (list 'gxc: target)))
          (def interface (core-resolve-library-module-path ':yuanxu/ops/interface))
          (check-equal? (and (assoc interface (.get build source-inputs)) #t) #t)
          (put helper "(export answer) (def answer 'changed)\n")
          (check-equal? (refuses? (.get build admit-current)) #t))))
    (test-case "different Suites share support inputs and retain independent source guards"
      (def root (path-expand ".." (path-directory (this-source-file))))
      (call-with-temporary-directory (path-expand "t/qualification/shared-support-" root)
        (lambda (directory)
          (def support (path-expand "support.ss" directory))
          (def first (path-expand "first-test.ss" directory))
          (def second (path-expand "second-test.ss" directory))
          (def target (path-strip-extension
                        (substring support
                          (string-length (string-append (path-strip-trailing-directory-separator root) "/"))
                          (string-length support))))
          ;; Both Suites import the identical package-owned compiled module.
          ;; Each Suite retains its own source demand; neither projection executes assertions.
          (def (suite file name expected)
            (put file
              (string-append "(import :std/test :yuanxu/" target ") (export " name "-test)\n"
                "(def " name "-test (test-suite \"" name "\" (test-case \"own verdict\" "
                "(check-equal? value " (number->string expected) "))))\n")))
          (put support "(export value) (def value 7)\n")
          (suite first "first" 7)
          (suite second "second" 7)
          (def a (.call tests .for-files (list first)))
          (def b (.call tests .for-files (list second)))
          (def directory-a (.get (.get a build) output-directory))
          (check-equal? directory-a (.get (.get b build) output-directory))
          ((.get (.get a build) admit-current))
          ((.get (.get b build) admit-current))
          (check-equal? (.slot? a '.run) #f)
          (check-equal? (.slot? b '.compile) #f)
          ;; Changing only a Suite must refuse its old demand. A fresh demand
          ;; may retain the support projection without approving or executing an assertion.
          (suite second "second" 8)
          (check-exception ((.get b admit-current)) error?)
          (def changed (.call tests .for-files (list second)))
          (check-equal? directory-a (.get (.get changed build) output-directory))
          ((.get changed admit-current))
          ;; Support changes invalidate the product and every old consumer.
          (put support "(export value) (def value 8)\n")
          (check-exception ((.get (.get a build) admit-current)) error?)
          (def new-support (.call tests .for-files (list first)))
          (check-equal? (equal? directory-a (.get (.get new-support build) output-directory)) #f))))
    (test-case "a selected Suite used for-syntax remains a compiler input"
      (def root (path-expand ".." (path-directory (this-source-file))))
      (call-with-temporary-directory (path-expand "t/qualification/macro-support-" root)
        (lambda (directory)
          (def helper (path-expand "helper-test.ss" directory))
          (def support (path-expand "support.ss" directory))
          (def file (path-expand "probe-test.ss" directory))
          (put helper "(export value) (def value 7)\n")
          (put support "(import (for-syntax \"./helper-test.ss\")) (export answer) (def answer 7)\n")
          (put file "(import \"./support.ss\") (export result) (def result answer)\n")
          (def demand (.call tests .for-files (list helper file)))
          (def inputs (.get (.get demand build) source-inputs))
          ;; Excluding every selected file would incorrectly drop this real
          ;; compile-time dependency. The runtime graph must retain its bytes.
          (check-equal? (and (assoc (path-normalize helper) inputs) #t) #t)
          (put helper "(export value) (def value 8)\n")
          (check-exception ((.get (.get demand build) admit-current)) error?))))
    (test-case "runtime support retains its package compiler declaration"
      (def root (path-expand ".." (path-directory (this-source-file))))
      (call-with-temporary-directory (path-expand "t/qualification/compiler-options-" root)
        (lambda (directory)
          ;; Keep support in the real package root: runtime Make must use the
          ;; package's identity and output placement, not a fabricated namespace.
          (def support (path-expand "support.ss" directory))
          (def file (path-expand "probe-test.ss" directory))
          (def config (path-expand "compiler-input.txt" directory))
          (def target (path-strip-extension
                        (substring support
                          (string-length (string-append (path-strip-trailing-directory-separator root) "/"))
                          (string-length support))))
          (put support
            "(import (only-in :std/ffi C-declare))\n(C-declare \"#ifndef YUANXU_RUNTIME_OPTIONS_PROBE\\n#error missing runtime compiler option\\n#endif\\n\")\n(export runtime-value) (def runtime-value 7)\n")
          (put file
            (string-append "(import :std/test :yuanxu/" target
              ") (export probe-test)\n(def probe-test (test-suite \"runtime compiler options\" (test-case \"real compiled support\" (check-equal? runtime-value 7))))\n"))
          (put config "-DYUANXU_RUNTIME_OPTIONS_PROBE")
          (def demand
            (.call tests .for-files (list file) (list config)
              (list (list 'gxc: target "-cc-options" "-DYUANXU_RUNTIME_OPTIONS_PROBE"))))
          (check-equal? (.get (.get demand build) spec)
                        (list (list 'gxc: target "-cc-options" "-DYUANXU_RUNTIME_OPTIONS_PROBE")))
          ;; A conflicting declaration cannot silently select arbitrary flags.
          (def duplicate
            (.call tests .for-files (list file) (list config)
              (list (list 'gxc: target "-cc-options" "-DYUANXU_RUNTIME_OPTIONS_PROBE")
                    (list 'gxc: target "-cc-options" "-DOTHER"))))
          (check-exception (.get duplicate build) error?)
          (put config "changed compiler input")
          (check-exception ((.get demand admit-current)) error?))))
    (test-case "explicit source projection never compiles or runs the Case"
      (call-with-temporary-directory "init-compile-"
        (lambda (directory)
          (def file (path-expand "sample-test.ss" directory))
          (def marker (path-expand "case-ran" directory))
          (put (path-expand "gerbil.pkg" directory) "(package: init-compile-fixture)\n")
          (put file
            (string-append
              "(import :std/test) (export sample-test)\n"
              "(def sample-test (test-suite \"compile boundary\" (test-case \"runtime only\" "
              "(call-with-output-file " (object->string marker)
              " (lambda (port) (display \"ran\" port))))))\n"))
          (def demand (.call tests .for-files (list file)))
          (check-equal? ((.get demand std-make-spec)) '())
          (check-equal? (file-exists? marker) #f)
          (check-equal? (.slot? demand '.compile) #f)
          (check-equal? (.slot? demand 'execution) #f)
          (put file "(import :std/test) (export sample-test) (def sample-test (test-suite \"changed\"))")
          (check-exception ((.get demand admit-current)) error?))))
    (test-case "external inputs invalidate an inert explicit demand"
      (call-with-temporary-directory "init-input-"
        (lambda (directory)
          (def file (path-expand "sample-test.ss" directory))
          (def input (path-expand "support.txt" directory))
          (put file "(export value)\n(def value 1)\n")
          (put input "original")
          (def demand (.call tests .for-files (list file) (list input)))
          (check-equal? (.get demand spec) (list file))
          (check-equal? (.slot? demand '.compile) #f)
          (check-equal? (.ref/cached demand 'selected-graph) #f)
          ((.get demand admit-current))
          (put input "changed")
          (check-equal? (refuses? (.get demand admit-current)) #t))))))
