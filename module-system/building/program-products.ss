;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Pure projection of standard native target products; no compiler or loader.
(import (only-in :clan/poo/object .o .get .slot?)
        (only-in :std/list/list find filter-map delete-duplicates/hash))
(export make-target-kind make-target-spec program-targets
        program-path program-identity? projection-program-targets)

(def (make-target-kind entry)
  (if (.slot? entry 'make-kind) (.get entry make-kind) 'gxc:))

(def (make-target-spec entry name)
  (if (eq? (make-target-kind entry) 'exe:)
    `(exe: ,name bin: ,(.get entry bin-name) ,@(.get entry options))
    `(gxc: ,name ,@(.get entry options))))

(def (program-targets entries)
  (def programs
    (filter-map
    (lambda (entry)
      (and (eq? (make-target-kind entry) 'exe:)
           (.o compiler-identity: (.get entry compiler-identity)
               bin-name: (.get entry bin-name)))) entries))
  (def names (map (lambda (program) (.get program bin-name)) programs))
  (unless (= (length names) (length (delete-duplicates/hash names)))
    (error "programs share one binary output" names))
  programs)

(def (projection-program-targets projection)
  (if (.slot? projection 'program-targets) (.get projection program-targets) '()))

(def (program-identity? identity programs)
  (find (lambda (program) (eq? (.get program compiler-identity) identity)) programs))

(def (program-path program libdir)
  (path-expand (.get program bin-name) (path-expand "bin" libdir)))
