;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Native compiler inputs keep original evidence and scoped write resources.
(import :std/test
        (only-in :gerbil/compiler add-compile-job!)
        (only-in :gerbil/expander make-module-context)
        (only-in :clan/poo/object .o .get)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/building/artifacts call-with-native-static-inputs)
        (only-in :yuanxu/module-system/source/static-inputs module-native-static-inputs)
        (only-in :yuanxu/module-system/source/admission
                 module-source-read module-source-admit-current!))
(export module-static-inputs-test)

(def (put path text)
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))

(def (projection source-path source-text)
  ;; This temporary snapshot is compiler Fixture data, not a public input DSL.
  (.o static-inputs:
    (list (.o path: source-path name: "borrowed.scm" contents: source-text
              admit-current:
              (lambda ()
                (module-source-admit-current! (list (cons source-path source-text))))))))

(def module-static-inputs-test
  (test-suite "Native static input ownership"
    (yuanxu-test-case "native compiler aliases retain their original followed input"
      (call-with-temporary-directory "native-static-alias"
        (lambda (root)
          (def library (path-expand "lib" root))
          (def directory (path-expand "static" library))
          (create-directory* directory)
          (def original (path-expand "original.scm" root))
          (def other (path-expand "other.scm" root))
          (def alias (path-expand "borrowed__value.scm" directory))
          (def text "(define original 42)\n")
          (put original text)
          (put other text)
          (create-symbolic-link original alias)
          (def context
            (make-module-context 'borrowed/value #f #f
              (path-expand "borrowed/value.ssi" library)))
          (def input (car (module-native-static-inputs (list context) '())))
          (def current! (.get input admit-current))
          (current!)
          (check-equal? (.get input path) (path-normalize original))
          ;; Compiler input admission never weakens ordinary source-role rules.
          (check-exception (module-source-read alias) error?)
          (def (retarget! target)
            (delete-file alias)
            (create-symbolic-link target alias))
          (dynamic-wind void
            (lambda ()
              (retarget! other)
              (check-exception (current!) error?)
              (retarget! root)
              (check-exception (current!) error?)
              (retarget! (path-expand "missing.scm" root))
              (check-exception (current!) error?))
            (lambda () (retarget! original)))
          (current!)
          (dynamic-wind void
            (lambda ()
              (put original "(define substituted 99)\n")
              (check-exception (current!) error?))
            (lambda () (put original text)))
          (current!))))
    (yuanxu-test-case "derived files live in a private extent and release on return"
      (call-with-temporary-directory "native-static-owner"
        (lambda (root)
          (def path (path-expand "original.scm" root))
          (def text "(define original 42)\n")
          (put path text)
          (def paths (load-path))
          (def extent
            (call-with-native-static-inputs (projection path text)
              (lambda ()
                (def directory (car (load-path)))
                (check-equal? (module-source-read (path-expand "static/borrowed.scm" directory)) text)
                (put (path-expand "static/borrowed.c" directory) "generated C\n")
                (check-equal? (module-source-read path) text)
                directory)))
          (check-equal? (load-path) paths)
          (check-equal? (file-exists? extent) #f)
          (check-equal? (module-source-read path) text))))
    (yuanxu-test-case "failed work preserves its cause and restores the loader resource"
      (call-with-temporary-directory "native-static-unwind"
        (lambda (root)
          (def path (path-expand "original.scm" root))
          (def text "(define original 42)\n")
          (put path text)
          (def paths (load-path))
          (def extent #f)
          (def cause (gensym 'compiler-failure))
          (check-equal?
            (with-catch values
              (lambda ()
                (call-with-native-static-inputs (projection path text)
                  (lambda () (set! extent (car (load-path))) (raise cause)))))
            cause)
          (check-equal? (load-path) paths)
          (check-equal? (file-exists? extent) #f))))
    (yuanxu-test-case "early refusal drains the real compiler executor before removing inputs"
      (call-with-temporary-directory "native-static-job-drain"
        (lambda (root)
          (def path (path-expand "original.scm" root))
          (def text "(define original 42)\n")
          (put path text)
          (def extent #f)
          (def drained? #f)
          (def cause (gensym 'early-compiler-refusal))
          (check-equal?
            (with-catch values
              (lambda ()
                (call-with-native-static-inputs (projection path text)
                  (lambda ()
                    (set! extent (car (load-path)))
                    (add-compile-job!
                      (lambda ()
                        (thread-sleep! 0.01)
                        (unless (equal? (module-source-read
                                        (path-expand "static/borrowed.scm" extent)) text)
                          (error "compiler input retired before its worker"))
                        (set! drained? #t))
                      'native-static-input-lifetime)
                    (raise cause)))))
            cause)
          (check-equal? drained? #t)
          (check-equal? (file-exists? extent) #f))))
    (yuanxu-test-case "changed originals and changed staged Scheme refuse successful work"
      (call-with-temporary-directory "native-static-refusal"
        (lambda (root)
          (def path (path-expand "original.scm" root))
          (def text "(define original 42)\n")
          (def paths (load-path))
          (for-each
            (lambda (target)
              (put path text)
              (def extent #f)
              (check-exception
                (call-with-native-static-inputs (projection path text)
                  (lambda ()
                    (set! extent (car (load-path)))
                    (put (if (eq? target 'original) path
                           (path-expand "static/borrowed.scm" extent))
                         "(define substituted 99)\n")))
                error?)
              (check-equal? (load-path) paths)
              (check-equal? (file-exists? extent) #f))
            '(original staged)))))))
