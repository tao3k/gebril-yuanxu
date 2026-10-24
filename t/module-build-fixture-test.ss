;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object "./qualification/module-bootstrap/fixtures.ss"
        (only-in :std/io/tempfile call-with-temporary-directory current-temporary-directory)
        (only-in :std/misc/ports read-all-as-string))
(export module-build-fixture-test)
(def (put root name text)
  (def path (path-expand name root))
  (create-directory* (path-directory path))
  (call-with-output-file path (cut display text <>)))
(def module-build-fixture-test
  (test-suite "Source build fixture is data preparation, not an executable script"
    (test-case "cold fixture keeps the real build entry and excludes Core binaries"
      (call-with-temporary-directory "build-fixture-test"
        (lambda (temporary)
          (def source (path-expand "source" temporary))
          (def installed (path-expand "installed" temporary))
          (put source "build.ss" "(defbuild-script ((.get yuanxu.init.exports std-make-spec) core-spec))\n")
          (put source "gerbil.pkg" "(package: yuanxu)\n")
          (put source "modules/json-schema/interface.ss" "; fixture role\n")
          (put installed "lib/yuanxu/cache.ssi" "excluded")
          (put installed "lib/static/yuanxu__cache.o" "excluded")
          (put installed "lib/clan/poo/object.ssi" "dependency")
          (put installed "lib/static/clan__poo__object.o" "dependency")
          (parameterize ((current-temporary-directory temporary))
            (def fixture (source-build-fixture source #f installed))
            (check-equal? (.get fixture cold) #t)
            (check-equal? (call-with-input-file (path-expand "build.ss" (.get fixture root)) read-all-as-string)
                          "(defbuild-script ((.get yuanxu.init.exports std-make-spec) core-spec))\n")
            (check-equal? (file-exists? (path-expand "lib/yuanxu" (.get fixture state))) #f)
            (check-equal? (file-exists? (path-expand "lib/static/yuanxu__cache.o" (.get fixture state))) #f)
            (check-equal? (file-exists? (path-expand "lib/clan/poo/object.ssi" (.get fixture state))) #t)
            (check-equal? (file-exists? (path-expand "lib/static/clan__poo__object.o" (.get fixture state))) #t)
            (check-equal? (file-exists? (path-expand "run.ss" (.get fixture root))) #f)))))
    (test-case "an existing fixture preserves the selected state without copying"
      (def fixture (source-build-fixture "unused" "existing-source" "existing-state"))
      (check-equal? (.get fixture cold) #f)
      (check-equal? (.get fixture root) "existing-source")
      (check-equal? (.get fixture state) "existing-state"))))
