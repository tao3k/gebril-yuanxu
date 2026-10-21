;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Explicit native std/test scope; the original complete suite is unchanged.
(import (only-in :std/test/base TestSuite TestObject-init! TestObject-info
                 TestObject-subtests TestObject-subtests-set! current-test-suite))
(export selected-publication-suite)
(def (selected-publication-suite source names)
  (TestSuite "Selected publication controls"
    (lambda ()
      ((TestObject-init! source))
      (let* ((suite (current-test-suite))
             (selected (filter (lambda (test) (member (TestObject-info test) names))
                         (TestObject-subtests suite))))
        (unless (= (length selected) (length names))
          (error "publication scope does not match exact existing cases" names))
        (TestObject-subtests-set! suite selected)))))
