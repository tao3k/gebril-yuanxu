;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Native Gerbil instances are capabilities; matching names and paths are not.
(import :std/test :clan/poo/object
        (only-in :gerbil/expander core-import-module current-expander-module-import
                 make-module-context expander-context-id module-context-path
                 core-context-prelude syntax-e)
        (only-in :yuanxu/module-system/source/reader module-publication-reader)
        (only-in :yuanxu/module-system/building/source-closure yuanxu-bootstrap-contexts)
        (only-in "./qualification/module-publication/fixtures.ss" with-publication-source))
(export module-compiler-context-test)

(def module-compiler-context-test
  (test-suite "Exact captured native context membership"
    (test-case "captured source resolution does not delegate to a same-name replacement"
      (with-publication-source
        (lambda (_root _module-root source _view)
          (def target ':yuanxu/object-types/contracts)
          (def canonical (core-import-module target))
          (def forged
            (make-module-context (expander-context-id canonical)
              (core-context-prelude canonical) #f (module-context-path canonical)))
          (def native-import (current-expander-module-import))
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
              (native-import path reload?)))
          (parameterize ((current-expander-module-import intercept))
            ;; Capture the real Gerbil closure before introducing the impostor.
            (def reader (module-publication-reader))
            (set! active? #t)
            ;; Known exact paths return their captured instance before asking
            ;; an ambient importer. The impostor is never used or initialized.
            (def publication (.call reader read source))
            (check-equal? (.get publication identity) 'custom/example)
            (check-equal? injected? #f)
            (.call reader admit-current)))))))
