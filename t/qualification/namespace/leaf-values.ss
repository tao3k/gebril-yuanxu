;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; User-facing standard POO expressions, exercised by the existing leaf suite.
(import (only-in :clan/poo/object .def .get .o))
(export Build Debug Explicit Inherited NamedSuper)

(.def Build
  executable: "gerbil"
  flags: '("build")
  argv: (cons executable flags))

(.def (Debug @ Build)
  (flags => append '("--debug")))

(.def (Explicit leaf Build)
  executable: "gxi"
  receiver: leaf
  argv: (cons (.get leaf executable) (.get leaf flags)))

(.def (Inherited @ Build)
  (flags (sup) (append (sup) '("--debug"))))

(def NamedSuper
  (.o inherit: (list Build) super: inherited
      flags: (append (inherited) '("--debug"))))
