;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :yuanxu/object-syntax/path-slots
        (only-in :clan/poo/object .get .call)
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :yuanxu/module-system/building/test-projection
                 module-test-file-source module-test-execution))
(export module-case-profile-test)
(def probe
  (path-expand "qualification/module-testing/case-profile-test.ss"
               (path-directory (this-source-file))))
(def (check-profile enabled? (trace? #f))
  ;; Exactly the factory used by init's executable test projection.
  (def execution (module-test-execution (module-test-file-source (list probe))))
  (.def (Request @ execution) profile.emit?: enabled? profile.trace-enabled?: trace?)
  (check-equal? (.get Request profile emit?) enabled?)
  (check-equal? (.get Request profile trace-enabled?) trace?)
  (check-equal?
    (and (member (if trace? "yuanxu-module-test-observation,yuanxu-module-test-trace"
                   "yuanxu-module-test-observation") (.get Request command)) #t)
    enabled?)
  (check-equal? (eq? (.get Request source) (.get execution source)) #t)
  (def result (.call Request .run))
  (check-equal? (.get result status) 0)
  (check-equal? (and (string-contains (.get result output) "child-probe . 1") #t)
                enabled?)
  (check-equal? (and (string-contains (.get result output) "child-trace . 1") #t)
                (and enabled? trace?)))
(def module-case-profile-test
  (test-suite "Init test projection to native child Case policy"
    (test-case "disabled observation does not load its adapter" (check-profile #f))
    (test-case "enabled observation binds automatically and fixtures unwind" (check-profile #t))
    (test-case "trace is transported as a native feature" (check-profile #t #t))
    (test-case "disabled observation keeps trace inert" (check-profile #f #t))
    (test-case "a changed test source rejects before starting Ops"
      (call-with-temporary-directory "case-profile-source-"
        (lambda (directory)
          (def file (path-expand "probe-test.ss" directory))
          (def (write-text text)
            (call-with-output-file (list path: file truncate: #t)
              (lambda (port) (display text port))))
          (write-text "original")
          (def execution (module-test-execution (module-test-file-source (list file))))
          (def started? #f)
          (.def (Request @ execution)
            command: (begin (set! started? #t) '("false")))
          (write-text "changed")
          (check-exception (.call Request .run) error?)
          (check-equal? started? #f))))))
