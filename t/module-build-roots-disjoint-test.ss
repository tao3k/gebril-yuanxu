;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :tao3k/yuanxu/module-system/source/role-forms parse-module-init))

(export module-build-roots-disjoint-test)

(def module-build-roots-disjoint-test
  (test-suite "build-roots disjointness from :load-modules windows"
    (test-case "rejects :build-roots entry inside a :load-modules window"
      (check-exception
        (parse-module-init
          '((yuanxu!
              :build-roots ("modules/module-authoring/interface")
              :load-modules "./modules" mode: auto))
          "/tmp/pkg/init.ss")
        error?))
    (test-case "rejects :build-roots entry inside a single-window source directory"
      (check-exception
        (parse-module-init
          '((yuanxu!
              :build-roots ("modules/module-authoring/interface")
              source: "./modules" mode: auto))
          "/tmp/pkg/init.ss")
        error?))
    (test-case "admits standalone :build-roots outside :load-modules windows and ignores lexical prefix"
      (let-values (((windows mounted?)
                    (parse-module-init
                      '((yuanxu!
                          :build-roots ("main" "modules-extra/facade")
                          :load-modules "./modules" mode: auto))
                      "/tmp/pkg/init.ss")))
        (check-equal? mounted? #t)
        (check-equal? (length windows) 1)))))
