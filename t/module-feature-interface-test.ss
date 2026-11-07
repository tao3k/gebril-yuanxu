;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Real Interface declarations, not an application-owned Feature selector.
(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :std/list/list find)
        (only-in :clan/poo/object .o .get .call)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (rename-in
          (only-in "qualification/module-publication/fixtures.ss"
                   with-publication-source write-file exception-message publication-feature-view)
          (publication-feature-view feature-view)))
(export module-feature-interface-test)

;; Only fixture source preparation is shared. The declaration below is read by
;; the production role wrapper, resolver and publisher through normal imports.
(def (feature-interface-roles root)
  (.o
    interface:
    `((import (only-in :yuanxu/feature-system/model feature-descriptor))
      (.def Fixture
        identity: 'custom/example
        core:
        (.o requires: (.o) scope-contract: FixtureContract
            exports:
            (begin
              (call-with-output-file ,(path-expand "scope-entered" root)
                (lambda (port) (display "scope" port)))
              (.o (:: @ FixtureScope) greeting: Greeting)))
        features:
        (.o
          memory:
          (begin
            (call-with-output-file ,(path-expand "descriptor-entered" root)
              (lambda (port) (display "descriptor" port)))
            (feature-descriptor
              (.o feature-id: 'custom/example/memory
                  owner-module-id: 'custom/example
                  components:
                  (list
                    (.o .run:
                        (lambda ()
                          (call-with-output-file ,(path-expand "effect-entered" root)
                            (lambda (port) (display "effect" port)))
                          'started))))))
          persistent:
          (feature-descriptor
            (.o feature-id: 'custom/example/persistent
                owner-module-id: 'custom/example
                requires: '(custom/example/memory)))
          ephemeral:
          (feature-descriptor
            (.o feature-id: 'custom/example/ephemeral
                owner-module-id: 'custom/example
                conflicts: '(custom/example/memory)))
          left:
          (feature-descriptor
            (.o feature-id: 'custom/example/left
                owner-module-id: 'custom/example
                requires: '(custom/example/right)))
          right:
          (feature-descriptor
            (.o feature-id: 'custom/example/right
                owner-module-id: 'custom/example
                requires: '(custom/example/left)))
          cold: (error "unselected Interface Feature was evaluated"))))))

(def (with-feature-interface-source test)
  (with-publication-source
    (lambda (root module-root _source _view)
      (write-file (path-expand "interface.ss" module-root)
        (call-with-output-string
          (lambda (port)
            (for-each (lambda (form) (write form port) (newline port))
              (.get (feature-interface-roles root) interface)))))
      (test root module-root))))

(def module-feature-interface-test
  (test-suite "Module Interface owns Feature declarations and init only selects"
    (yuanxu-test-case "Interface Features stay cold when absent or explicitly disabled"
      (with-feature-interface-source
        (lambda (root _module-root)
          (for-each
            (lambda (flags)
              (def view (feature-view root "disabled.ss" flags))
              (check-equal? (.get view selected-graph feature-order) '())
              (check-equal? (.get view selected-graph feature-contributions components) '())
              (check-equal? (file-exists? (path-expand "descriptor-entered" root)) #f)
              (check-equal? (file-exists? (path-expand "scope-entered" root)) #f)
              (check-equal? (file-exists? (path-expand "effect-entered" root)) #f))
            '(() (-memory -cold))))))
    (yuanxu-test-case "selected Interface contributes inert values; explicit run owns effects"
      (with-feature-interface-source
        (lambda (root _module-root)
          (def view (feature-view root "enabled.ss" '(+persistent +memory -cold)))
          (check-equal? (file-exists? (path-expand "descriptor-entered" root)) #f)
          (def graph (.get view selected-graph))
          (check-equal? (.get graph feature-order)
            '(custom/example/memory custom/example/persistent))
          (def components (.get graph feature-contributions components))
          (check-equal? (length components) 1)
          (check-equal? (eq? (car components)
                            (car (.get graph feature-contributions components))) #t)
          (check-equal? (file-exists? (path-expand "scope-entered" root)) #f)
          (check-equal? (file-exists? (path-expand "effect-entered" root)) #f)
          (check-equal? (.get view modules custom example greeting) "hello")
          (check-equal? (file-exists? (path-expand "scope-entered" root)) #t)
          (check-equal? (file-exists? (path-expand "effect-entered" root)) #f)
          (check-equal? (.call (car components) .run) 'started)
          (check-equal? (file-exists? (path-expand "effect-entered" root)) #t))))
    (yuanxu-test-case "withdrawn selection cannot rewrite the cached parent selection"
      (with-feature-interface-source
        (lambda (root _module-root)
          ;; Establish both declarations before either reader takes its snapshot.
          (def parent (feature-view root "parent.ss" '(+memory)))
          (def child (feature-view root "child.ss" '(-memory -cold)))
          (def parent-graph (.get parent selected-graph))
          (def component (car (.get parent-graph feature-contributions components)))
          (check-equal? (.get child selected-graph feature-order) '())
          (check-equal? (.get child selected-graph feature-contributions components) '())
          (check-equal? (eq? (.get parent selected-graph) parent-graph) #t)
          (check-equal? (eq? (car (.get parent-graph feature-contributions components)) component) #t)
          (check-equal? (.get parent-graph feature-order) '(custom/example/memory))
          (check-equal? (file-exists? (path-expand "effect-entered" root)) #f))))
    (yuanxu-test-case "collection binds an optional facade to the selected Feature"
      (with-feature-interface-source
        (lambda (root module-root)
          (def facade (path-expand "features/memory/interface.ss" module-root))
          (create-directory* (path-directory facade))
          (def pending (feature-view root "pending.ss" '(+memory)))
          (def original (.get pending selected-graph))
          (check-equal? (.get (find (lambda (node) (eq? (.get node kind) 'feature))
                                   (.get original nodes)) interface) #f)
          (write-file (path-expand "value.ss" (path-directory facade)) "(def present? #t) (export present?)")
          (write-file facade "(import \"./value.ss\") (export (import: \"./value.ss\"))")
          (check-exception ((.get original admit-current)) error?)
          (def enabled (feature-view root "with-facade.ss" '(+memory)))
          (def withdrawn (feature-view root "without-facade.ss" '(-memory)))
          (def build (.get enabled build-graph))
          (def (facade-entry graph)
            (find (lambda (entry) (equal? (.get entry path) (path-normalize facade)))
                  (.get graph entries)))
          (def entry (facade-entry build))
          (check-equal? (.get entry owner) 'custom/example)
          (check-equal? (.get entry contributor) 'custom/example/memory)
          (check-equal? (facade-entry (.get withdrawn build-graph)) #f)
          (check-equal? (file-exists? (path-expand "scope-entered" root)) #f))))
    (yuanxu-test-case "Interface requirements, conflicts, cycles and unknown names refuse before scopes"
      (with-feature-interface-source
        (lambda (root _module-root)
          (for-each
            (lambda (row)
              (def view (feature-view root "refused.ss" (car row)))
              (def message (exception-message (lambda () (.get view selected-graph))))
              (for-each
                (lambda (text)
                  (check-equal? (and (string-contains message text) #t) #t))
                (cdr row))
              (check-exception ((.get view admit-current)) error?)
              (check-equal? (file-exists? (path-expand "scope-entered" root)) #f)
              (check-equal? (file-exists? (path-expand "effect-entered" root)) #f))
            '(((+persistent -memory) "selected Graph rejected" "missing-dependency"
               "custom/example/persistent" "custom/example/memory" "denied?")
              ((+memory +ephemeral) "selected Graph rejected" "conflict")
              ((+left +right) "selected Graph rejected" "cycle")
              ((+unknown) "unknown init feature" "unknown")
              ((-unknown) "unknown init feature" "unknown"))))))
    (yuanxu-test-case "lazy Interface contribution cannot return after changing a tracked source"
      (with-publication-source
        (lambda (root module-root _source _view)
          (def config (path-expand "config.ss" module-root))
          (write-file (path-expand "interface.ss" module-root)
            (call-with-output-string
              (lambda (port)
                (write
                  `(import (only-in :yuanxu/feature-system/model feature-descriptor)) port)
                (write
                  `(.def Fixture identity: 'custom/example
                    core: (.o requires: (.o) scope-contract: FixtureContract exports: FixtureScope)
                    features:
                    (.o memory:
                      (.o (:: @ (feature-descriptor
                                  (.o feature-id: 'custom/example/memory
                                      owner-module-id: 'custom/example)))
                          components:
                          (begin
                            (call-with-output-file (list path: ,config truncate: #t)
                              (lambda (output)
                                (display "(def Greeting \"changed\") (export Greeting)" output)))
                            '())))) port))))
          (def view (feature-view root "changed.ss" '(+memory)))
          (def graph (.get view selected-graph))
          (check-equal? (.get graph feature-order) '(custom/example/memory))
          (def message
            (exception-message (lambda () (.get graph feature-contributions))))
          (check-equal? (and (string-contains message "config.ss") #t) #t)
          (check-exception ((.get view admit-current)) error?))))))
