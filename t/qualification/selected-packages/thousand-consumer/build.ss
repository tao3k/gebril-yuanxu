;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .get)
        (only-in :std/source this-source-file)
        (only-in :yuanxu/module-system/building/source-closure package-library-spec)
        (only-in :std/build-script defbuild-script)
        (only-in "./init.ss" yuanxu-thousand-consumer.init.exports))
(def application-spec
  (package-library-spec (path-directory (this-source-file)) 'yuanxu-thousand-consumer '("main.ss")))
(defbuild-script
  (append (.get yuanxu-thousand-consumer.init.exports std-make-spec) application-spec))
