;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Core architecture inputs; the host D2 Module owns every inference rule.
(import :clan/poo/object)
(export architecture-diagrams)

(def (architecture-diagrams d2)
  (def Diagram. (.get d2 prototypes Diagram))
  (def Node. (.get d2 prototypes Node))
  (def Relation. (.get d2 prototypes Relation))
  (list
    (.o (:: @ Diagram.) identity: 'publication-boundaries revision: 'source-window-design
      roots: '(guard)
      nodes:
      (list (.o (:: @ Node.) identity: 'guard kind: 'entry label: "Guard")
            (.o (:: @ Node.) identity: 'state kind: 'qualification label: "Origin")
            (.o (:: @ Node.) identity: 'checked kind: 'qualified label: "Guard DAG")
            (.o (:: @ Node.) identity: 'independent kind: 'fallback label: "Independent")
            (.o (:: @ Node.) identity: 'fresh kind: 'boundary label: "Fresh tail")
            (.o (:: @ Node.) identity: 'effects kind: 'effect label: "Effects"))
      relations:
      (list (.o (:: @ Relation.) from: 'guard to: 'state role: 'inspect)
            (.o (:: @ Relation.) from: 'state to: 'checked role: 'qualified)
            (.o (:: @ Relation.) from: 'state to: 'independent role: 'fallback)
            (.o (:: @ Relation.) from: 'checked to: 'fresh role: 'close)
            (.o (:: @ Relation.) from: 'independent to: 'fresh role: 'check)
            (.o (:: @ Relation.) from: 'fresh to: 'effects role: 'end)))
    (.o (:: @ Diagram.) identity: 'assurance-ownership revision: 'source-window-design
      roots: '(sysml)
      nodes:
      (list (.o (:: @ Node.) identity: 'sysml kind: 'design label: "SysML: ownership")
            (.o (:: @ Node.) identity: 'lean kind: 'proof label: "Lean: refinement")
            (.o (:: @ Node.) identity: 'quint kind: 'model-check label: "Quint: transitions")
            (.o (:: @ Node.) identity: 'scheme kind: 'implementation label: "Scheme: correspondence")
            (.o (:: @ Node.) identity: 'qualification kind: 'evidence label: "Build / std/test"))
      relations:
      (list (.o (:: @ Relation.) from: 'sysml to: 'lean role: 'laws)
            (.o (:: @ Relation.) from: 'sysml to: 'quint role: 'traces)
            (.o (:: @ Relation.) from: 'lean to: 'scheme role: 'premises)
            (.o (:: @ Relation.) from: 'quint to: 'scheme role: 'controls)
            (.o (:: @ Relation.) from: 'scheme to: 'qualification role: 'real-entrypoints)
            (.o (:: @ Relation.) from: 'qualification to: 'sysml role: 'gaps)))))
