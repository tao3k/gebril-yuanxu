;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

prelude: :gerbil/core

(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .o .cc .get .ref .slot? .call .put!)
        (only-in :clan/poo/mop validate)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/admission call-with-module-source-operation-measurement)
        (only-in "qualification/module-publication/fixtures.ss"
                 with-publication-source write-file exception-message publication-feature-view))
(export module-feature-scope-test)

;; Types and behavior are ordinary module roles. Only Interface selects which
;; standard function/Contract pair contributes to its owner's final receiver.
(def (scope-roles root)
  (.o
    types:
    '((import (only-in :clan/poo/mop Bool)
              (only-in :clan/poo/type Record Exactly True)
              (only-in :clan/poo/number Integer))
      (def FixtureContract (.cc (Record port: [Integer] memory: [Bool]) identity: 'feature/base))
      (def MemoryContract (.cc (Record memory: [True]) identity: 'feature/memory))
      (def FirstPort (.cc (Record port: [(Exactly 5432)]) identity: 'feature/first-port))
      (def SecondPort (.cc (Record port: [(Exactly 5433)]) identity: 'feature/second-port))
      (export FixtureContract MemoryContract FirstPort SecondPort))
    objects:
    `((import (only-in :clan/poo/object .o .get .put!))
      (def FixtureScope (.o memory: #f))
      (def (EnableMemory inherited)
        (.o (:: self inherited)
          memory: #t observed-port: (.get self port)
          .run: (lambda ()
                  (call-with-output-file ,(path-expand "started" root)
                    (lambda (port) (display "started" port)))
                  (.get self port))))
      (def (ChangePort inherited) (.o (:: self inherited) port: 5433))
      (def (WriteParent inherited) (.put! inherited 'port 5440) inherited)
      (export FixtureScope EnableMemory ChangePort WriteParent))
    config: '((def Config (.o port: 5432)))
    interface:
    `((.def Fixture identity: 'custom/example
        core: (.o requires: (.o) scope-contract: FixtureContract
                  exports: (.o (:: self FixtureScope) port: (.get Config port)))
        features:
        (.o
          memory:
          (.o refine: EnableMemory contract: MemoryContract)
          move:
          (.o requires: '(custom/example/memory) refine: ChangePort)
          first:
          (.o contract: FirstPort)
          second:
          (.o refine: ChangePort contract: SecondPort)
          write:
          (.o refine: WriteParent)
          malformed:
          (.o refine: 42)
          primitive:
          (.o refine: (lambda (_scope) "not a POO scope"))
          wrong-port:
          (.o refine: (lambda (scope) (.o (:: self scope) port: "invalid")))
          changed:
          (.o refine:
            (lambda (scope)
              (call-with-output-file
                (list path: ,(path-expand "modules/custom/example/config.ss" root) truncate: #t)
                (lambda (port) (display "(def Config (.o port: 5440))" port)))
              scope))
          cold: (error "disabled Feature implementation was demanded"))))))

(def (with-feature-scopes test)
  (with-publication-source
    (lambda (root module-root _source _view)
      (def roles (scope-roles root))
      (for-each
        (lambda (role)
          (write-file (path-expand (string-append (symbol->string role) ".ss") module-root)
            (call-with-output-string
              (lambda (port)
                (for-each (lambda (form) (write form port) (newline port)) (.ref roles role))))))
        '(types objects config interface))
      (test root module-root))))

(def module-feature-scope-test
  (test-suite "Selected Interface Features extend and admit the final Module scope"
    (yuanxu-test-case "standard refinement and Contract run once per demanded scope; effects stay explicit"
      (with-feature-scopes
        (lambda (root _module-root)
          (def view (publication-feature-view root "enabled.ss" '(+memory -cold)))
          (def independent (publication-feature-view root "independent.ss" '(+memory -cold)))
          (check-equal? (file-exists? (path-expand "started" root)) #f)
          (defvalues (scope counts)
            (call-with-module-source-operation-measurement
              (lambda ()
                (def scope (.get view modules custom example))
                (check-equal? (eq? scope (.get view modules custom example)) #t)
                scope)))
          (check-equal? (.get scope memory) #t)
          (check-equal? (.get scope observed-port) 5432)
          (check-equal? (hash-get counts '(calls (feature-refinement custom/example custom/example/memory))) 1)
          (check-equal? (hash-get counts '(calls (feature-admission custom/example custom/example/memory))) 1)
          (defvalues (_other independent-counts)
            (call-with-module-source-operation-measurement
              (lambda () (.get independent modules custom example))))
          (check-equal?
            (hash-get independent-counts '(calls (feature-refinement custom/example custom/example/memory))) 1)
          (check-equal?
            (hash-get independent-counts '(calls (feature-admission custom/example custom/example/memory))) 1)
          (check-equal? (file-exists? (path-expand "started" root)) #f)
          (check-equal? (.call scope .run) 5432)
          (check-equal? (file-exists? (path-expand "started" root)) #t))))
    (yuanxu-test-case "later refinements read final self; withdrawal rebuilds from base and isolates parent caches"
      (with-feature-scopes
        (lambda (root _module-root)
          (def parent (publication-feature-view root "parent.ss" '(+memory)))
          (def child (publication-feature-view root "child.ss" '(+move +memory)))
          (def withdrawn (publication-feature-view root "withdrawn.ss" '(-memory -cold)))
          (def original (.get parent modules custom example))
          (check-equal? (.get original observed-port) 5432)
          (def changed (.get child modules custom example))
          (check-equal? (.get changed port) 5433)
          (check-equal? (.get changed observed-port) 5433)
          (check-equal? (eq? original (.get parent modules custom example)) #t)
          (check-equal? (.get original port) 5432)
          (check-equal? (.get original observed-port) 5432)
          (def base (.get withdrawn modules custom example))
          (check-equal? (.get base memory) #f)
          (check-equal? (.get base port) 5432)
          (check-equal? (.slot? base '.run) #f)
          (check-equal? (file-exists? (path-expand "started" root)) #f))))
    (yuanxu-test-case "both independent port obligations check the final scope, never intermediate winners"
      (with-feature-scopes
        (lambda (root _module-root)
          (def first (publication-feature-view root "first.ss" '(+first)))
          (def second (publication-feature-view root "second.ss" '(+second)))
          (def both (publication-feature-view root "both.ss" '(+first +second)))
          (check-equal? (.get first modules custom example port) 5432)
          (check-equal? (.get second modules custom example port) 5433)
          (def message (exception-message (lambda () (.get both modules custom example))))
          (check-equal? (and (string-contains message "feature/first-port") #t) #t)
          (check-equal? (and (string-contains message "port") #t) #t)
          (check-exception ((.get both admit-current)) error?))))
    (yuanxu-test-case "the published standard Type retains Feature obligations without borrowing child reads"
      (with-feature-scopes
        (lambda (root _module-root)
          (def view (publication-feature-view root "provider.ss" '(+memory)))
          (def record (.call view .selected-record 'custom/example))
          (def scope (.get record scope))
          (def contract (.get record scope-contract))
          (check-equal? (.get scope observed-port) 5432)
          (def child (.o (:: self scope) port: 5433))
          (check-equal? (.get (validate contract child) observed-port) 5433)
          (.put! child 'port 5440)
          ((.get record admit-construction-current))
          (check-equal? (.get scope observed-port) 5432)
          (check-exception (validate contract (.o (:: self scope) memory: #f)) error?))))
    (yuanxu-test-case "refinement cannot write its parent or return a primitive; malformed functions refuse"
      (with-feature-scopes
        (lambda (root _module-root)
          (def parent (publication-feature-view root "original.ss" '()))
          (def original (.get parent modules custom example))
          (for-each
            (lambda (row)
              (def view (publication-feature-view root "refused.ss" (list (car row))))
              (def message (exception-message (lambda () (.get view modules custom example))))
              (check-equal? (and (string-contains message (cadr row)) #t) #t)
              (check-exception ((.get view admit-current)) error?)
              (check-equal? (.get original port) 5432))
            '((+write "object mutation during computation")
              (+malformed "invalid Module Feature refinement")
              (+primitive "must return a POO scope")
              (+wrong-port "feature/base"))))))
    (yuanxu-test-case "cross-owner Feature selection composes only demanded scopes and preserves provider Contracts"
      (with-feature-scopes
        (lambda (root _module-root)
          (for-each
            (lambda (entry)
              (def name (car entry))
              (def module-root (path-expand (string-append "modules/custom/" (symbol->string name)) root))
              (def roles
                (.o types: '((import (only-in :clan/poo/type Record True))
                             (def ReviewContract
                               (.cc (Record observed: [True]) identity: 'feature/review))
                             (export ReviewContract))
                    objects: '((def ReviewBase (.o)) (export ReviewBase))
                    config: '((def Config (.o)))
                    interface:
                    `((.def Review identity: ',(string->symbol (string-append "custom/" (symbol->string name)))
                        core:
                        (.o requires:
                            (.o Source:
                              (.o module-id: 'custom/example
                                  refine: (lambda (scope)
                                            ,(if (cadr entry) 'scope
                                               '(.o (:: self scope) memory: #f)))))
                            scope-contract: ReviewContract
                            exports: (.o observed: (.get Source memory)))
                        features: ',(if (eq? name 'review) '(audit exclusive) '())))))
              (for-each
                (lambda (role)
                  (write-file (path-expand (string-append (symbol->string role) ".ss") module-root)
                    (call-with-output-string
                      (lambda (port)
                        (for-each (lambda (form) (write form port) (newline port)) (.ref roles role))))))
                '(types objects config interface)))
            '((review #t) (override #f)))
          (def review-feature (path-expand "modules/custom/review/features/audit" root))
          (create-directory* review-feature)
          (write-file (path-expand "interface.ss" review-feature)
            "(import (only-in :yuanxu/module-system/source/declaration .def))
             (.def Feature requires: '(custom/example/memory)
                           refine: enable-audit contract: AuditContract)")
          (write-file (path-expand "objects.ss" review-feature)
            "(import (only-in :clan/poo/object .o))
             (def (enable-audit scope) (.o (:: self scope) audited: #t))
             (export enable-audit)")
          (write-file (path-expand "types.ss" review-feature)
            "(import (only-in :clan/poo/object .cc)
                     (only-in :clan/poo/type Record True))
             (def AuditContract (.cc (Record audited: [True]) identity: 'feature/audit))
             (export AuditContract)")
          (write-file (path-expand "modules/custom/review/features/exclusive/interface.ss" root)
            "(import (only-in :yuanxu/module-system/source/declaration .def))
             (.def Feature conflicts: '(custom/example/memory))")
          (write-file (path-expand "review.ss" root)
            "(yuanxu! mode: explicit :custom (example +memory) (review +audit))")
          (write-file (path-expand "conflict.ss" root)
            "(yuanxu! mode: explicit :custom (example +memory) (review +exclusive))")
          (write-file (path-expand "withdrawn.ss" root)
            "(yuanxu! mode: explicit :custom (example -memory) (review +audit))")
          (write-file (path-expand "override.ss" root)
            "(yuanxu! mode: explicit :custom (example +memory) (override))")
          (def good (yuanxu-load-modules (path-expand "review.ss" root)))
          (def bad (yuanxu-load-modules (path-expand "override.ss" root)))
          (defvalues (provider provider-counts)
            (call-with-module-source-operation-measurement
              (lambda () (.get good modules custom example))))
          (check-equal? (.get provider memory) #t)
          (check-equal? (hash-get provider-counts '(calls (scope-factory custom/example))) 1)
          (check-equal? (hash-get provider-counts '(calls (scope-factory custom/review))) #f)
          (check-equal?
            (hash-get provider-counts '(calls (feature-refinement custom/review custom/review/audit))) #f)
          (defvalues (review review-counts)
            (call-with-module-source-operation-measurement
              (lambda () (.get good modules custom review))))
          (check-equal? (.get review observed) #t)
          (check-equal? (.get review audited) #t)
          (check-equal? (hash-get review-counts '(calls (scope-factory custom/example))) #f)
          (check-equal? (hash-get review-counts '(calls (scope-factory custom/review))) 1)
          (check-equal?
            (hash-get review-counts '(calls (feature-admission custom/review custom/review/audit))) 1)
          (def message (exception-message (lambda () (.get bad modules custom override))))
          (check-equal? (and (string-contains message "feature/memory") #t) #t)
          (check-exception ((.get bad admit-current)) error?)
          (for-each
            (lambda (entry)
              (def rejected (yuanxu-load-modules (path-expand (car entry) root)))
              (defvalues (refusal counts)
                (call-with-module-source-operation-measurement
                  (lambda ()
                    (exception-message (lambda () (.get rejected modules custom example))))))
              (for-each
                (lambda (part) (check-equal? (and (string-contains refusal part) #t) #t))
                (cdr entry))
              (check-equal? (hash-get counts '(calls (scope-factory custom/example))) #f)
              (check-equal? (hash-get counts '(calls (scope-factory custom/review))) #f)
              (check-exception ((.get rejected admit-current)) error?))
            '(("conflict.ss" "selected Graph rejected" "conflict" "custom/review/exclusive")
              ("withdrawn.ss" "selected Graph rejected" "missing-dependency" "custom/review/audit")))
          (check-equal? (eq? review (.get good modules custom review)) #t)
          (delete-file (path-expand "types.ss" review-feature))
          (check-exception ((.get good admit-current)) error?))))
    (yuanxu-test-case "source mutation inside a Feature refuses before returning its scope"
      (with-feature-scopes
        (lambda (root module-root)
          (def view (publication-feature-view root "changed.ss" '(+changed)))
          (def message (exception-message (lambda () (.get view modules custom example))))
          ;; Keep the standard first diagnostic (publication owner), rather than
          ;; reorder guards to force a leaf-file diagnostic. Prove the callback
          ;; actually changed Config before this refusal, not during setup.
          (check-equal? (call-with-input-file (path-expand "config.ss" module-root) read)
            '(def Config (.o port: 5440)))
          (for-each
            (lambda (text) (check-equal? (and (string-contains message text) #t) #t))
            '("stale prepared Module publication" "custom/example" "interface.ss"))
          (check-exception ((.get view admit-current)) error?))))))
