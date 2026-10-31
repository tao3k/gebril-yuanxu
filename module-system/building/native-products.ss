;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Pure projection of standard native target products; no compiler or loader.
(import (only-in :clan/poo/object .o .get .slot?)
        (only-in :std/list/list find filter-map delete-duplicates/hash))
(export native-target-kind native-target-spec native-program-targets
        native-program-path native-program-identity? projection-program-targets)

(def (native-target-kind entry)
  (if (.slot? entry 'native-kind) (.get entry native-kind) 'gxc:))

(def (native-target-spec entry name)
  (if (eq? (native-target-kind entry) 'exe:)
    `(exe: ,name bin: ,(.get entry bin-name) ,@(.get entry options))
    `(gxc: ,name ,@(.get entry options))))

(def (native-program-targets entries)
  (def programs
    (filter-map
    (lambda (entry)
      (and (eq? (native-target-kind entry) 'exe:)
           (.o compiler-identity: (.get entry compiler-identity)
               bin-name: (.get entry bin-name)))) entries))
  (def names (map (lambda (program) (.get program bin-name)) programs))
  (unless (= (length names) (length (delete-duplicates/hash names)))
    (error "native programs share one binary output" names))
  programs)

(def (projection-program-targets projection)
  (if (.slot? projection 'program-targets) (.get projection program-targets) '()))

(def (native-program-identity? identity programs)
  (find (lambda (program) (eq? (.get program compiler-identity) identity)) programs))

(def (native-program-path program libdir)
  (path-expand (.get program bin-name) (path-expand "bin" libdir)))
