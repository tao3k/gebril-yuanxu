-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


namespace YuanxuProof.ProfileComposition.Syntax

/-! Structural model of `selection-syntax.ss` and `scope-declaration.ss`.
Identifier binding equality and source-location hygiene remain Gerbil expander
obligations, rather than caller-supplied propositions masquerading as Lean proofs. -/
inductive Token where
  | identifier (name : String)
  | compound (forms : List String)
  deriving DecidableEq, Repr

inductive ModuleUse where
  | profiles (moduleName : String) (instanceName : Option String) (names : List String)
  | bounded (moduleName alias : String) (body : List String)
  deriving DecidableEq, Repr

def identifiers : List Token → Option (List String)
  | [] => some []
  | .identifier name :: rest => (identifiers rest).map (name :: ·)
  | .compound _ :: _ => none

def parseModuleUse : List Token → Option ModuleUse
  | [.identifier name, .identifier "as", .identifier alias, .compound (first :: rest)] =>
      some (.bounded name alias (first :: rest))
  | .identifier name :: .identifier "as" :: .identifier instanceName :: first :: rest =>
      (identifiers (first :: rest)).map (.profiles name (some instanceName))
  | .identifier _ :: .identifier "as" :: _ => none
  | .identifier name :: first :: rest =>
      (identifiers (first :: rest)).map (.profiles name none)
  | _ => none

theorem compoundCannotBeProfile (forms : List String) (rest : List Token) :
    identifiers (.compound forms :: rest) = none := rfl

theorem boundBodyPreserved (name alias first : String) (rest : List String) :
    parseModuleUse [.identifier name, .identifier "as", .identifier alias,
      .compound (first :: rest)] = some (.bounded name alias (first :: rest)) := rfl

#guard parseModuleUse [.identifier "Module", .identifier "Profile"] ==
  some (.profiles "Module" none ["Profile"])
#guard parseModuleUse [.identifier "Module", .identifier "as", .identifier "instance",
  .identifier "Profile"] == some (.profiles "Module" (some "instance") ["Profile"])
#guard (parseModuleUse [.identifier "Module", .identifier "as"]).isNone
#guard (parseModuleUse [.identifier "Module"]).isNone
#guard (parseModuleUse [.identifier "Module", .identifier "as", .identifier "alias",
  .compound []]).isNone
#guard (parseModuleUse [.identifier "Module", .compound ["body"]]).isNone

end YuanxuProof.ProfileComposition.Syntax
