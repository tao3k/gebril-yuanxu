;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/source this-source-file)
        (only-in :clan/poo/object .get)
        (only-in "../init.ss" tao3k/yuanxu.init.exports)
        (only-in "../core-spec.ss" core-spec)
        (only-in "./qualification/module-init/fixture.ss" import-build-script!)
        (only-in :gerbil/expander expander-context-id)
        (only-in :tao3k/yuanxu/module-system/building/source-closure package-library-spec))
(export package-library-spec-test)
(def (write-source root name text)
  (call-with-output-file (path-expand name root) (lambda (port) (display text port))))
(def package-library-spec-test
  (test-suite "Selected package source projection"
    (test-case "Core installation leaves Funflow and JsonSchema to the consumer"
      (def root (path-expand ".." (path-directory (this-source-file))))
      (def main (import-build-script! (path-expand "build.ss" root) #t))
      (def spec
        (call-with-input-string
          (call-with-output-string
            (lambda (out) (parameterize ((current-output-port out)) (main "spec")))) read))
      (def targets (map (lambda (target) (if (string? target) target (cadr target))) spec))
      (check-equal? (filter (lambda (target)
                             (or (string-prefix? "modules/funflow/" target)
                                 (string-prefix? "modules/json-schema/" target))) targets) '())
      (check-equal? (member "init" core-spec) #f))
    (test-case "explicit Core init export retains the public Funflow targets"
      (def targets
        (map (lambda (target) (if (string? target) target (cadr target)))
             (.get tao3k/yuanxu.init.exports std-make-spec)))
      (for-each
        (lambda (target) (check-equal? (and (member target targets) #t) #t))
        '("modules/funflow/func" "modules/funflow/control-plane/api"
          "modules/funflow/control-plane/runtime-command-descriptor"
          "modules/funflow/workload" "modules/funflow/bundle-v1")))
    (test-case "shared imports are projected once in dependency order; unused sources stay lazy"
      (call-with-temporary-directory "package-library-"
        (lambda (root)
          (write-source root "gerbil.pkg" "(package: selected-package-fixture)\n")
          (write-source root "shared.ss" "(export value)\n(def value 1)\n")
          (write-source root "first.ss" "(import \"shared.ss\")\n(export first)\n(def first value)\n")
          (write-source root "second.ss" "(import \"shared.ss\")\n(export second)\n(def second value)\n")
          (write-source root "unused.ss" "(invalid unread syntax\n")
          (def selected '())
          (def (observe context)
            (let (id (expander-context-id context))
              (when (and (symbol? id)
                         (string-prefix? "selected-package-fixture/" (symbol->string id)))
                (set! selected (cons id selected)))))
          (check-equal?
            (package-library-spec root 'selected-package-fixture '("first.ss" "second.ss")
              admit-context: observe)
            '("shared" "first" "second"))
          (check-equal? (reverse selected)
            '(selected-package-fixture/shared selected-package-fixture/first
              selected-package-fixture/second))
          (check-equal?
            (package-library-spec root 'selected-package-fixture '("first.ss" "second.ss")
              exclude: '("shared"))
            '("first" "second"))
          (check-exception
            (package-library-spec root 'selected-package-fixture '("first.ss")
              exclude: '("shared")
              admit-context: (lambda (context)
                (when (eq? (expander-context-id context) 'selected-package-fixture/shared)
                  (error "selected dependency refused"))))
            error?))))))
