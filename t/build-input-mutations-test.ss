;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in "./qualification/build-input/mutations.ss" verify-build-input-mutations))
(export build-input-mutations-test)
(def build-input-mutations-test
  (test-suite "Build input order, restoration and admission faults"
    (test-case "all four faults fail for the original reason and controls recover"
      (def root (getenv "YUANXU_TEST_REPORT_DIR"
                  (getenv "RUNNER_TEMP" (path-expand ".cache" (current-directory)))))
      (create-directory* root)
      (verify-build-input-mutations root "-:max-heap=2G,debug=q"))))
