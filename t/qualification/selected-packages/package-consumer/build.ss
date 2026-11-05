#!/usr/bin/env gxi
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .get)
        (only-in :std/source this-source-file)
        (only-in :yuanxu/module-system/building/source-closure package-library-spec)
        (only-in :yuanxu/module-system/building/script defbuild-script)
        (only-in "./init.ss" yuanxu-package-consumer.init.exports))
(def application-spec
  (package-library-spec (path-directory (this-source-file)) 'yuanxu-package-consumer '("main.ss")))
(defbuild-script ((.get yuanxu-package-consumer.init.exports std-make-spec) application-spec))
