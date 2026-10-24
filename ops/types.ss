;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)
        (only-in :clan/poo/mop Type. Function Any Bool element?)
        (only-in :clan/poo/type Record String List OrFalse Union Unit)
        (only-in :clan/poo/number Integer Real))
(export ProcessScriptContract ProcessResultContract OpsConfigContract OpsScopeContract OpsEnvironmentContract)
(def ProcessResultContract
  (Record status: (list Integer) wait-status: (list Integer) seconds: (list Real)
          output: (list (Union String Unit))
          log: (list (OrFalse String))))
(def (environment? value)
  (and (object? value)
       (every (lambda (key)
                (and (symbol? key) (not (string-empty? (symbol->string key)))
                     (not (string-index (symbol->string key) #\=))
                     (string? (.ref value key))))
              (.all-slots value))))
(def OpsEnvironmentContract
  (.cc Type. sexp: 'OpsEnvironment '.element? environment?))
(def PositiveDuration
  (.cc Type. sexp: 'PositiveFiniteDuration
    '.element? (lambda (value)
                 (and (real? value) (> value 0) (< value +inf.0)))))
;; The callback result is unconstrained, but its argument and the factory's
;; single returned callable are checked by upstream Function normalization.
(def ProgressFactory (Function (list (Function (list Any) (list String))) '()))
(def ConfigFields
  (Record directory: (list (OrFalse String))
          environment: (list OpsEnvironmentContract)
          timeout: (list (OrFalse PositiveDuration))
          log: (list (OrFalse String)) check-status: (list Bool)
          idle-timeout: (list (OrFalse PositiveDuration) optional: #t)
          progress: (list (OrFalse ProgressFactory) optional: #t)))
(def OpsConfigContract
  (.o inherit: (list ConfigFields)
    (.element? (inherited)
      (lambda (value)
        (and ((inherited) value)
             (or (not (.slot? value 'idle-timeout)) (not (.get value idle-timeout))
                 (and (.get value timeout) #t)))))))
(def (execution-options? value) (element? OpsConfigContract value))
(def ProcessScriptFields
  (.cc OpsConfigContract slots:
    (.cc (.get OpsConfigContract slots)
         command: (.get (Record command: (list (List String))) slots command))))
(def ProcessScriptContract
  (.o inherit: (list ProcessScriptFields)
    (.element? (inherited)
      (lambda (value)
        (and ((inherited) value) (pair? (.get value command))
             (not (string-empty? (car (.get value command)))))))))
(def (ops-scope? scope)
  (and (object? scope)
       (every (cut .slot? scope <>) '(config types prototypes validate prepare-command merge-environment preview run))
       (execution-options? (.get scope config))
       (object? (.get scope types))
       (every (cut .slot? (.get scope types) <>) '(ProcessScript Config Environment))
       (eq? (.get scope types ProcessScript) ProcessScriptContract)
       (eq? (.get scope types Config) OpsConfigContract)
       (eq? (.get scope types Environment) OpsEnvironmentContract)
       (every (lambda (name) (procedure? (.ref scope name)))
              '(validate prepare-command merge-environment preview run))
       (object? (.get scope prototypes))
       (every (lambda (name)
                (and (.slot? (.get scope prototypes) name)
                     (let (prototype (.ref (.get scope prototypes) name))
                       (and (object? prototype) (.slot? prototype '.run)
                            (procedure? (.get prototype .run))))))
              '(Script SelectedPackages))))
(def OpsScopeContract
  (yuanxu-predicate-contract 'ops/scope ops-scope? (lambda (_v _c) '())))
