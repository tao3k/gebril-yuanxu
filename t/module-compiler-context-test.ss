;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Runtime SDK instances are capabilities; matching names and paths are not.
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :gerbil/expander core-import-module current-expander-module-import
                 make-module-context expander-context-id module-context-path
                 core-context-prelude syntax-e)
        (only-in :yuanxu/module-system/source/reader module-publication-reader)
        (only-in :yuanxu/module-system/building/source-closure
                 yuanxu-bootstrap-contexts yuanxu-reader-contexts for-each-build-module)
        (only-in "./qualification/module-publication/fixtures.ss" with-publication-source))
(export module-compiler-context-test)

(def module-compiler-context-test
  (test-suite "Exact captured runtime context membership"
    (test-case "native expansion finds a macro-introduced input without initializing the role"
      (call-with-temporary-directory "module-target-context"
        (lambda (root)
          (def (write-source name content)
            (call-with-output-file (path-expand name root)
              (lambda (port) (display content port))))
          (write-source "gerbil.pkg" "(package: target-context prelude: :gerbil/core)\n")
          (write-source "helper.ss" "(export value)\n(def value 42)\n")
          (write-source "emit.ss"
            "(export add-input)\n(defrule (add-input) (import \"./helper.ss\"))\n")
          (write-source "plain.ss"
            "(import \"./emit.ss\")\n(error \"runtime role initializer ran\")\n")
          (write-source "generated.ss"
            "(import \"./emit.ss\")\n(add-input)\n(error \"runtime role initializer ran\")\n")
          (def (imports name)
            (def ids '())
            (for-each-build-module (core-import-module (path-expand name root))
              (lambda (context) (set! ids (cons (expander-context-id context) ids))))
            ids)
          (check-equal? (member 'target-context/helper (imports "plain.ss")) #f)
          (check-equal? (and (member 'target-context/helper (imports "generated.ss")) #t) #t))))
    (test-case "the reader captures its own Context without admitting build entry roots"
      (def contexts (yuanxu-reader-contexts void))
      (check-equal?
        (eq? (hash-get contexts 'yuanxu/module-system/source/reader)
             (core-import-module ':yuanxu/module-system/source/reader)) #t)
      (check-equal? (hash-get contexts 'yuanxu/module-system/building/build-projection) #f)
      (check-equal? (hash-get contexts 'yuanxu/module-system/building/script) #f))
    (test-case "captured source resolution does not delegate to a same-name replacement"
      (with-publication-source
        (lambda (_root _module-root source _view)
          (def target ':yuanxu/object-types/contracts)
          (def canonical (core-import-module target))
          (def forged
            (make-module-context (expander-context-id canonical)
              (core-context-prelude canonical) #f (module-context-path canonical)))
          (def gerbil-import (current-expander-module-import))
          (def observed (make-hash-table-eq))
          (yuanxu-bootstrap-contexts (lambda (context) (hash-put! observed context #t)))
          (check-equal? (hash-key? observed canonical) #t)
          (check-equal? (hash-key? observed forged) #f)
          (def active? #f)
          (def injected? #f)
          (def (intercept path reload?)
            (def requested (syntax-e path))
            (if (and active?
                     (or (eq? requested target)
                         (equal? requested (module-context-path canonical))))
              (begin (set! injected? #t) forged)
              (gerbil-import path reload?)))
          (parameterize ((current-expander-module-import intercept))
            ;; Capture the real SDK closure before introducing the impostor.
            (def reader (module-publication-reader))
            (set! active? #t)
            ;; Known exact paths return their captured instance before asking
            ;; an ambient importer. The impostor is never used or initialized.
            (def publication (.call reader read source))
            (check-equal? (.get publication identity) 'custom/example)
            (check-equal? injected? #f)
            (.call reader admit-current)))))))
