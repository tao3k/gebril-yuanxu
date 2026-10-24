;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .o .get .put! object? replay-slot-reads!)
        (only-in :clan/poo/slot-observation call-with-slot-read-observer
                 slot-read-receiver slot-read-key)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract yuanxu-validation-evidence-accepted?)
        :yuanxu/module-system/source/collection
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/source/admission
        :yuanxu/module-system/interface)
(export module-source-admission-test)
(def ScopeContract
  (yuanxu-predicate-contract 'test/source-scope object? (lambda (_v _c) '())))
(def (write-role root role text)
  (let (path (path-expand (string-append "modules/custom/example/" role ".ss") root))
    (create-directory* (path-directory path))
    (call-with-output-file (list path: path truncate: #t) (lambda (port) (display text port)))))
(def (remove-source path)
  (if (eq? (module-source-type path) 'directory)
    (begin (for-each (lambda (name) (remove-source (path-expand name path))) (directory-files path))
           (delete-directory path))
    (delete-file path)))
(def (with-module test)
  (let (root (make-temporary-file-name "module-source-admission-"))
    (dynamic-wind
     (lambda ()
       (write-role root "types" "(def PublicContract 'contract)")
       (write-role root "objects" "(import \"types.ss\") (def Defaults 'default)")
       (write-role root "config" "(import \"objects.ss\") (def Config 'configured)")
       ;; Publish one object, without importing/re-exporting every private role.
       (write-role root "interface" "(import \"config.ss\") (.def Published identity: 'custom/example) (export Published)"))
     (lambda () (test root))
     (lambda () (remove-source root)))))
(def (publication)
  (.o identity: 'custom/example features: (.o)
      core: (.o requires: (.o) scope-contract: ScopeContract
                link: (lambda (_dependencies) (.o ready: #t)))))
(def (collection-source root)
  (let (collection (make-yuanxu-module-source-collection
                   'fixture 'test root "modules/custom"))
    (yuanxu-module-source-collection-locate collection '(custom . example))))
(def (directory-scope root reader)
  (.get (yuanxu-load-modules (path-expand "modules" root) read-publication: reader)
        modules custom example))
(def (both-refuse root)
  (let (reads 0)
    (check-exception (collection-source root) error?)
    (check-exception (directory-scope root (lambda (_source) (set! reads (+ reads 1)) (publication))) error?)
    (check-equal? reads 0)))
(def module-source-admission-test
  (test-suite "One source-role admission for directory and collection"
    (yuanxu-test-case "collected replay starts fresh and shares only its own pure reads"
      (with-module
        (lambda (root)
          (def file (path-expand "modules/custom/example/types.ss" root))
          (def input (cons file (module-source-read file)))
          (def replay
            (call-with-collected-module-sources
              (lambda (current!)
                (module-source-admit-current! (list input)) current!)))
          (def stats 0)
          (def reads 0)
          (parameterize ((current-module-source-observer
                          (lambda (key amount)
                            (case key
                              ((stats) (set! stats (+ stats amount)))
                              ((reads) (set! reads (+ reads amount)))))))
            (replay)
            ;; The explicit regular-file check and byte read share one stat.
            (check-equal? stats 1)
            (check-equal? reads 1)
            (replay)
            ;; Independent replays always read again, not a retained approval.
            (check-equal? stats 2)
            (check-equal? reads 2)
            (call-with-module-source-read-cache
              (lambda ()
                (module-source-read file)
                ;; Deliberate authority-boundary negative: an outer pure view
                ;; must not conceal a source mutation from the fresh replay.
                (write-role root "types" "(def PublicContract 'changed)")
                (check-exception (replay) error?)))))))
    (yuanxu-test-case "file kind is shared while each collector retains its own evidence"
      (with-module
       (lambda (root)
         (def file (path-expand "modules/custom/example/types.ss" root))
         (def input (cons file (module-source-read file)))
         (def stats 0)
         (def first #f)
         (def second #f)
         (parameterize ((current-module-source-observer
                         (lambda (key amount)
                           (when (eq? key 'stats) (set! stats (+ stats amount))))))
           (call-with-module-source-read-cache
             (lambda ()
               (check-equal? (module-source-type file) 'regular)
               (call-with-collected-module-sources
                 (lambda (current!)
                   (check-equal? (module-source-type file) 'regular)
                   (module-source-admit-current! (list input))
                   (set! first current!)))
               (call-with-collected-module-sources
                 (lambda (current!)
                   (check-equal? (module-source-type file) 'regular)
                   (module-source-admit-current! (list input))
                   (set! second current!)))
               (check-equal? stats 1))))
         (write-role root "types" "(def PublicContract 'changed)")
         (check-exception (first) error?)
         (check-exception (second) error?)
         (delete-file file)
         (create-directory file)
         (call-with-module-source-read-cache
           (lambda () (check-equal? (module-source-type file) 'directory))))))
    (yuanxu-test-case "each policy invocation parses each role once and rechecks changed roles"
      (with-module
        (lambda (root)
          (def parses 0)
          (def template (.get yuanxu-default-module-style-policy %authoring-interface))
          (parameterize ((current-module-source-observer
                          (lambda (key amount)
                            (when (eq? key 'role-parses)
                              (set! parses (+ parses amount))))))
            (check-equal? (length (collection-source root)) 1)
            (check-equal? parses 4)
            (check-equal? (length (collection-source root)) 1)
            (check-equal? parses 8)
            (write-role root "config" "(stage provider runtime)")
            (check-exception (collection-source root) error?)
            (check-equal? parses 12))
          (check-equal? (eq? template
                         (.get yuanxu-default-module-style-policy %authoring-interface)) #t)
          ;; A derived receiver cannot borrow a parent's normalized Profile.
          (def invalid
            (.o (:: @ yuanxu-default-module-style-policy)
              authoring:
              (.o (:: @ (.get yuanxu-default-module-style-policy authoring)) config: #f)))
          (check-exception (.get invalid %authoring-interface) error?)
          (def local (.o (:: @ yuanxu-default-module-style-policy)))
          (def reads '())
          (def checked
            (call-with-slot-read-observer
              (lambda (read)
                (when (and (eq? (slot-read-receiver read) local)
                           (eq? (slot-read-key read) '%authoring-interface))
                  (set! reads (cons read reads))))
              (lambda () (.get local %authoring-interface))))
          (check-equal? (pair? reads) #t)
          (replay-slot-reads! reads (lambda (_owner _key) (void)))
          ;; Mutating a checked output must not borrow the constructor's input
          ;; support. This private receiver cannot poison the maintained policy.
          (.put! (.get checked authoring) 'config #f)
          (check-exception
            (replay-slot-reads! reads (lambda (_owner _key) (void))) error?)
          (check-equal? (eq? template
                         (.get yuanxu-default-module-style-policy %authoring-interface)) #t))))
    (yuanxu-test-case "source guards require exact Unicode content and EOF"
      (with-module
        (lambda (root)
          (def file (path-expand "modules/custom/example/types.ss" root))
          (def text "aλ\nb")
          (write-role root "types" text)
          (call-with-module-source-read-cache
            (lambda ()
              (module-source-admit-current! (list (cons file text)))
              (check-equal? (module-source-read file) text)))
          (for-each (lambda (expected)
                      (check-exception (module-source-admit-current! (list (cons file expected))) error?))
                    '("aλ" "aλ\nb!" "aλ\nc" ""))
          (write-role root "types" "")
          (check-exception (module-source-admit-current! (list (cons file text))) error?)
          (module-source-admit-current! (list (cons file ""))))))
    (yuanxu-test-case "nested pure guards reuse reads but independent validation observes changes"
      (with-module
       (lambda (root)
         (let ((file (path-expand "modules/custom/example/types.ss" root))
               (reads 0) (events (make-hash-table)))
           (parameterize ((current-module-source-observer
                           (lambda (kind amount)
                             (hash-update! events kind (cut + <> amount) 0)
                             (when (eq? kind 'reads) (set! reads (+ reads 1)))))
                          (current-module-source-phase 'nested-guard))
             (let (original
                   (call-with-module-source-read-cache
                     (lambda ()
                       (let (first (module-source-read file))
                         (module-source-admit-current! (list (cons file first)))
                         (call-with-module-source-read-cache
                           (lambda ()
                             (module-source-admit-current! (list (cons file first)))
                             ;; An equal copy is not the same expected revision
                             ;; object. It must take the checking path as well.
                             (module-source-admit-current! (list (cons file (string-copy first))))))
                         first))))
               (check-equal? reads 1)
               (check-equal? (hash-ref events 'checks) 2)
               (check-equal? (hash-ref events 'read-windows) 1)
               (check-equal? (hash-ref events (list 'file-read 'nested-guard file)) 1)
               (check-equal? (hash-ref events 'source-comparisons) 2)
               (check-equal? (hash-ref events 'source-comparison-hits) 1)
               (check-equal? (hash-ref events (list 'file-request 'nested-guard file)) 3)
               ;; Mutation is an effect BETWEEN validation scopes, never inside.
               (write-role root "types" "(def PublicContract 'updated)")
               (check-exception
                (call-with-module-source-read-cache
                  (lambda () (module-source-admit-current! (list (cons file original)))))
                error?)
               (check-equal? reads 2)
               (check-equal? (hash-ref events 'checks) 3)
               (check-equal? (hash-ref events 'read-windows) 2)))))))
    (yuanxu-test-case "file-kind observations expire before a later validation"
      (with-module
       (lambda (root)
         (def file (path-expand "modules/custom/example/types.ss" root))
         (def original
           (call-with-module-source-read-cache (lambda () (module-source-read file))))
         (delete-file file)
         (create-directory file)
         (check-exception
           (call-with-module-source-read-cache
             (lambda () (module-source-admit-current! (list (cons file original)))))
           error?)
         (delete-directory file)
         (create-symbolic-link (path-expand "modules/custom/example/objects.ss" root) file)
         (check-exception
           (call-with-module-source-read-cache (lambda () (module-source-read file))) error?))))
    (yuanxu-test-case "a memoized guard enrolls each new admission collector"
      (with-module
       (lambda (root)
         (def file (path-expand "modules/custom/example/types.ss" root))
         (def input (cons file (module-source-read file)))
         (def replay #f)
         (def calls 0)
         (def (guard)
           (set! calls (+ calls 1))
           (module-source-admit-current! (list input)))
         (call-with-module-source-read-cache
           (lambda ()
             (module-source-observe guard)
             (module-source-observe guard)
             (check-equal? calls 1)
             (call-with-collected-module-sources
               (lambda (current!)
                 (module-source-observe guard)
                 (module-source-observe guard)
                 (check-equal? calls 2)
                 (set! replay current!)))))
         ;; The new collector must retain the source even though the first
         ;; observation of these same bytes preceded that collector's scope.
         (write-role root "types" "(def PublicContract 'changed)")
         (check-exception (replay) error?))))
    (yuanxu-test-case "comparison hits still enroll new collectors and cannot hide conflicting expectations"
      (with-module
        (lambda (root)
          (def file (path-expand "modules/custom/example/types.ss" root))
          (def replay #f)
          (def original (module-source-read file))
          (def inputs (list (cons file original)))
          (call-with-module-source-read-cache
            (lambda ()
              (module-source-admit-current! inputs)
              (call-with-collected-module-sources
                (lambda (current!)
                  (module-source-admit-current! inputs)
                  (set! replay current!)))
              ;; A path-only memo would wrongly authorize this revision.
              (check-exception
                (module-source-admit-current! (list (cons file "different bytes"))) error?)))
          (write-role root "types" "(def PublicContract 'changed-after-window)")
          (check-exception (replay) error?))))
    (yuanxu-test-case "one public Module object needs no flat private re-exports"
      (with-module
       (lambda (root)
         (let (sources (collection-source root))
           (check-equal? (length sources) 1)
           (check-equal?
            (yuanxu-validation-evidence-accepted?
             (admit-module-publication! (car sources) 'custom/example (publication) (.o))) #t))
         (check-equal? (.get (directory-scope root (lambda (_source) (publication))) ready) #t))))
    (yuanxu-test-case "missing, empty, nonregular and symlinked required roles are refused"
      (for-each
       (lambda (damage)
         (with-module
          (lambda (root)
            (let (path (path-expand "modules/custom/example/types.ss" root))
              (delete-file path) (damage path root) (both-refuse root)))))
       (list (lambda (_path _root) (void))
             (lambda (path _root) (call-with-output-file path (lambda (_port) (void))))
             (lambda (path _root) (create-directory path))
             (lambda (path root) (create-symbolic-link (path-expand "modules/custom/example/objects.ss" root) path)))))
    (yuanxu-test-case "reversed role imports and forbidden config behavior fail before publication"
      (for-each
       (lambda (text)
         (with-module (lambda (root) (write-role root "config" text) (both-refuse root))))
       '("(import \"interface.ss\") (def Config 'invalid)" "(stage provider runtime)")))
    (yuanxu-test-case "objects may consume optional pure functions; func cannot import interface"
      (with-module
       (lambda (root)
         (write-role root "func" "(import \"types.ss\") (def (adjust value) value)")
         (write-role root "objects" "(import \"func.ss\") (def Defaults 'default)")
         (check-equal? (length (collection-source root)) 1)
         (check-equal? (.get (directory-scope root (lambda (_source) (publication))) ready) #t)
         (write-role root "func" "(import \"interface.ss\") (def (adjust value) value)")
         (both-refuse root))))
    (yuanxu-test-case "unselected broken siblings stay unread and optional func edits invalidate"
      (with-module
       (lambda (root)
         (write-role root "func" "(def (adjust value) value)")
         (create-directory (path-expand "modules/custom/unused" root))
         (check-equal? (length (collection-source root)) 1)
         (let (view (yuanxu-load-modules (path-expand "modules" root)
                      read-publication: (lambda (_source) (publication))))
           (check-equal? (.get view modules custom example ready) #t)
           ((.get view admit-current))
           (write-role root "func" "(def (adjust value) 'changed)")
           (check-exception ((.get view admit-current)) error?)))))
    (yuanxu-test-case "collection keys cannot escape their source and optional roles must be regular"
      (with-module
       (lambda (root)
         (let (collection (make-yuanxu-module-source-collection 'fixture 'test root "modules/custom"))
           (check-exception
            (yuanxu-module-source-collection-locate collection '(custom . ../example)) error?))
         (create-directory (path-expand "modules/custom/example/func.ss" root))
         (both-refuse root))))
    (yuanxu-test-case "explicit integration exclusions preserve strict admission of selected Modules"
      (with-module
       (lambda (root)
         (def collection (make-yuanxu-module-source-collection 'fixture 'test root "modules/custom"))
         (def (front-end name)
           (def directory (path-expand (string-append "modules/custom/" name) root))
           (create-directory directory)
           (call-with-output-file (path-expand "interface.ss" directory)
             (lambda (port) (display "(export)" port))))
         (front-end "helper")
         (check-exception (yuanxu-module-source-collection-interfaces collection) error?)
         (def selected (.o (:: @ collection) excluded-directories: '("helper")))
         (check-equal? (length (yuanxu-module-source-collection-interfaces selected)) 1)
         (check-equal? (yuanxu-module-source-collection-locate selected '(custom . helper)) '())
         (front-end "broken")
         (check-exception (yuanxu-module-source-collection-interfaces selected) error?))))
    (yuanxu-test-case "source owner and publication owner must agree before scope assembly"
      (let ((source (make-yuanxu-module-source-ref
                     'local "example/interface.ss" '((module-id . another/owner))))
            (value (publication)))
        (check-exception (admit-module-publication! source 'custom/example value (.o)) error?)
        (check-exception
         (admit-module-publication! (make-yuanxu-module-generated-source 'custom/example)
                                    'custom/example (.o identity: 'custom/example) (.o)) error?)))))
