;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; CI metadata only: no process execution, Harness or verdict interpretation.
(import (only-in :std/encoding/json json->string)
        (only-in :clan/poo/object .get)
        (only-in "../init.ss" tao3k/yuanxu.init.exports))
(export main)

(def test-groups
  '("dense-declarations" "dense-selection" "dense-values" "sparse-business" "build-inputs"
    "scale-declarations" "scale-runtime" "scale-packages"
    "store-callbacks" "artifact-authority" "source-loader" "source-gateway"
    "building" "sources" "features" "module-authoring" "module-loading" "module-tests"
    "compiled-module-tests" "modules" "mop" "workflow" "contracts" "providers" "ops" "runtime" "bootstrap"))
(def (group-owner file)
  (case (string->symbol file)
    ((module-declaration-10000-test.ss) "dense-declarations")
    ((module-runtime-selection-10000-test.ss) "dense-selection")
    ((module-runtime-values-10000-test.ss) "dense-values")
    ((module-business-sparse-10000-test.ss) "sparse-business")
    ((module-testing-compiled-test.ss) "compiled-module-tests")
    ((artifact-closure-test.ss mop-store-boundary-test.ss) "store-callbacks")
    ((artifact-authority-test.ss) "artifact-authority")
    ((source-loader-authority-test.ss) "source-loader")
    ((source-admission-gateway-test.ss) "source-gateway")
    ((build-input-mutations-test.ss) "build-inputs")
    ((module-declaration-1000-test.ss module-declaration-retention-test.ss
      module-loading-scale-test.ss) "scale-declarations")
    ((module-runtime-values-1000-test.ss module-runtime-attribution-1000-test.ss
      module-business-eval-once-1000-test.ss module-eval-once-1000-test.ss) "scale-runtime")
    ((thousand-package-downstream-test.ss package-install-test.ss) "scale-packages")
    (else
     (cond ((ormap (cut string-prefix? <> file)
                   '("core-build-" "module-build-" "build-" "artifact-")) "building")
           ((ormap (cut string-prefix? <> file)
                   '("module-source-" "module-reader-" "module-candidate-" "module-publication-"
                     "source-" "reader-")) "sources")
           ((string-prefix? "feature-" file) "features")
           ((ormap (cut string-prefix? <> file) '("json-schema-" "aws-" "gitea-" "nix-")) "providers")
           ((ormap (cut string-prefix? <> file) '("ops-" "testing-")) "ops")
           ((ormap (cut string-prefix? <> file)
                   '("package-" "prelude-" "module-bootstrap-"
                     "runtime-publication-identity-")) "bootstrap")
           ((ormap (cut string-prefix? <> file)
                   '("module-authoring-" "module-schema-" "module-config-" "module-configuration-")) "module-authoring")
           ((ormap (cut string-prefix? <> file)
                   '("module-context-" "module-compiler-" "module-load-" "module-loader-"
                     "module-init-" "module-deferred-" "module-public-dependency-"
                     "module-retained-" "module-role-")) "module-loading")
           ((ormap (cut string-prefix? <> file)
                   '("module-test-" "module-testing-" "module-case-profile-")) "module-tests")
           ((ormap (cut string-prefix? <> file) '("module-" "feature-")) "modules")
           ((string-prefix? "mop-" file) "mop")
           ((ormap (cut string-prefix? <> file)
                   '("functional-flow-" "funflow-" "domain-case-" "composition-")) "workflow")
           ((ormap (cut string-prefix? <> file)
                   '("contract-" "admission-" "contribution-" "configuration-"
                     "poo-" "object-" "issued-" "path-" "evidence-" "issuer-")) "contracts")
           (else "runtime")))))

(def (discovered-files group)
  (unless (or (equal? group "all") (member group test-groups))
    (error "unknown test group" group))
  (filter-map (lambda (file)
                (and (string-suffix? "-test.ss" file)
                     (or (equal? group "all") (equal? group (group-owner file)))
                     (string-append "t/" file)))
              (list-sort string<? (directory-files "t"))))

(def (test-partition)
  (def groups (map discovered-files test-groups))
  (unless (and (andmap pair? groups)
               (equal? (discovered-files "all")
                       (list-sort string<? (apply append groups))))
    (error "missing or duplicated test group coverage"))
  groups)
(def (check-partition)
  (def groups (test-partition))
  (for-each (lambda (group files) (displayln "TEST-GROUP " group " files=" (length files)))
            test-groups groups)
  (displayln "TEST-GROUPS-OK"))


(def (matrix-row group)
  (def files (discovered-files group))
  (def large (filter (cut string-suffix? "-10000-test.ss" <>) files))
  (unless (or (null? large) (= (length files) (length large)))
    (error "a CI group cannot widen another file's heap policy" group))
  (list->hash-table
    (list (cons "group" group) (cons "files" (string-join
            (map (lambda (file)
                   (if (equal? file "t/mop-store-boundary-test.ss")
                     "t/qualification/mop-state/store-boundary-driver.ss" file)) files) "\n"))
          (cons "heap" (if (null? large) "2G" "4G"))
          (cons "batch" (and (member group '("ops" "workflow")) #t))
          (cons "deadline" (if (member group '("dense-declarations" "dense-selection"))
                             "680s" "600s")))))

(def (published-files)
  (def tests (.get tao3k/yuanxu.init.exports tests))
  ((.get tests admit-current))
  (def files (.get tests spec))
  (unless (and (pair? files) (andmap string? files))
    (error "published Module tests must be explicit and nonempty"))
  files)

(def (main action . arguments)
  (cond ((string=? action "--matrix")
         (test-partition)
         (displayln (json->string
           (list->hash-table
             (list (cons "include" (list->vector (map matrix-row test-groups))))))))
        ((string=? action "--list") (for-each displayln (apply discovered-files arguments)))
        ((string=? action "--check") (check-partition))
        ((string=? action "--published") (for-each displayln (published-files)))
        (else (error "unknown CI inventory operation" action)))
  (force-output))
