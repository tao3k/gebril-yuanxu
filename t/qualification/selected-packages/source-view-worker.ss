;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object
        (only-in :std/make make)
        (only-in :yuanxu/module-system/building/source-package call-with-build-input-path)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax)
        (only-in :yuanxu/module-system/source/preparation
                 yuanxu-prepare-module-retained-source call-with-module-compiler-inputs)
        (only-in :yuanxu/module-system/building/products
                 current-build-output-directory current-build-source-directory
                 repair-build-products! require-build-products!))

(def (main root lib operation selection)
  (add-load-path! lib)
  (if (equal? operation "use")
    (parameterize ((current-expander-context (make-top-context)))
      (eval-syntax '(import :gerbil/core :selected-view-consumer/main))
      (displayln "SOURCE-VIEW-VALUE " (eval-syntax 'answer)))
    (let* ((paths (if (equal? selection "base") '("producer/value.ss")
                   '("consumer/main.ss" "producer/value.ss" "producer/independent.ss")))
           (entries
             (map (lambda (relative)
                    (def source-path (path-expand relative root))
                    (def prepared-input (yuanxu-prepare-module-retained-source source-path void))
                    (.o path: source-path input: prepared-input
                        compiler-identity: (.ref prepared-input 'compiler-identity) options: '())) paths))
           (identities (map (lambda (entry) (.ref entry 'compiler-identity)) entries))
           (spec (map (lambda (entry)
                        `(gxc: ,(symbol->string (.ref entry 'compiler-identity))
                               (extra-inputs: ,(map car (.ref (.ref entry 'input) 'source-inputs))))) entries)))
      (parameterize ((current-build-output-directory lib))
        (if (equal? operation "interrupt")
          ;; The exception is injected at the existing callback boundary, not
          ;; through a production fault hook. Catch only our exact sentinel.
          (let (sentinel (gensym 'before-native))
            (with-catch
              (lambda (failure)
                (if (eq? failure sentinel) (displayln "SOURCE-VIEW-INTERRUPTED") (raise failure)))
              (lambda ()
                (call-with-module-compiler-inputs entries (lambda () (raise sentinel)) unified?: #t))))
          (call-with-module-compiler-inputs entries
            (lambda ()
              (repair-build-products! identities lib)
              (def make-source (current-build-source-directory))
              (call-with-build-input-path lib
                (lambda ()
                  (make spec srcdir: make-source prefix: #f
                        libdir: lib bindir: (path-expand "bin" root) parallelize: 1 optimize: #f))
                make-source: make-source)
              (require-build-products! identities lib)) unified?: #t))))))
