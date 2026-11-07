;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .def .o))
(export ReleaseProfile)

(.def BaseProfile
  executable: "gerbil"
  flags: '("build")
  argv: (cons executable flags))

(def ReleaseProfile
  (.o self: profile inherit: (list BaseProfile)
      executable: "gxi"
      (flags (sup) (append (sup) '("--debug")))
      receiver: profile
      engine: #f))
