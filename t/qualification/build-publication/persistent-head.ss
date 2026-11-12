;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Actual transactional selected-head effect, qualification adapter only.
;;; No arbitrary callback/Nix switch runs inside or after this transaction.
(import :clan/poo/object :std/db/sqlite :std/db/db :std/db/interface)
(export persistent-head)

(def (with-database path action)
  (def db (new-db (sqlite-open path)))
  (dynamic-wind void (cut action db) (cut DB-close db)))
(def (transaction db action)
  (DB-exec! db "BEGIN IMMEDIATE" '())
  (with-catch
    (lambda (failure)
      (with-catch
        (lambda (rollback) (error "head transaction and rollback failed" failure rollback))
        (cut DB-abort! db))
      (raise failure))
    (lambda () (begin0 (action) (DB-commit! db)))))
(def (persistent-head path)
  (def (initialize-head selection snapshot)
    (with-database path
      (lambda (db)
        (DB-exec! db "PRAGMA synchronous=FULL" '())
        (DB-exec! db "CREATE TABLE IF NOT EXISTS head (id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL, fence INTEGER NOT NULL, selection TEXT NOT NULL, snapshot TEXT NOT NULL)" '())
        (DB-exec! db "CREATE TABLE IF NOT EXISTS requests (token TEXT PRIMARY KEY, revision INTEGER NOT NULL, fence INTEGER NOT NULL, selection TEXT NOT NULL, snapshot TEXT NOT NULL)" '())
        (DB-exec! db "INSERT INTO head VALUES (1,0,0,?,?)" (list selection snapshot)))))
  (def (inspect-head)
    (with-database path
      (lambda (db)
        (car (DB-query db "SELECT revision,fence,selection,snapshot FROM head WHERE id=1" '())))))
  (def (issue-request selection snapshot expected-revision expected-fence)
    (with-database path
      (lambda (db)
        (transaction db
          (lambda ()
            (def token (car (DB-query db "SELECT lower(hex(randomblob(16)))" '())))
            ;; Capture-before-admission expectations cannot silently rebase.
            (DB-exec! db "INSERT INTO requests SELECT ?,revision,fence,selection,? FROM head WHERE id=1 AND selection=? AND revision=? AND fence=?"
              (list token snapshot selection expected-revision expected-fence))
            (unless (= 1 (car (DB-query db "SELECT changes()" '())))
              (error "selected head changed before issuance"))
            token)))))
  (def (apply-request token)
    (with-database path
      (lambda (db)
        (transaction db
          (lambda ()
            ;; Comparison and actual head/fence/snapshot effect are ONE SQL update.
            (DB-exec! db
              "UPDATE head SET revision=revision+1,fence=fence+1,snapshot=(SELECT snapshot FROM requests WHERE token=?) WHERE id=1 AND EXISTS (SELECT 1 FROM requests r WHERE r.token=? AND r.revision=head.revision AND r.fence=head.fence AND r.selection=head.selection)"
              (list token token))
            (unless (= 1 (car (DB-query db "SELECT changes()" '())))
              (error "stale or unknown selected-head request"))
            (car (DB-query db "SELECT revision,fence,selection,snapshot FROM head WHERE id=1" '())))))))
  (.o initialize: initialize-head issue: issue-request inspect: inspect-head commit: apply-request))
