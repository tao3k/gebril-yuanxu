-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Prototype.Generator

import PooFlowCoreProof.ProfileComposition.Revision

namespace PooFlowCoreProof.ProfileComposition.Prototype

inductive ProfileOperandKind where
  | nativeObject
  | nativePrototype
  | invalidShape
  deriving DecidableEq, Repr

def AdmitsOperandShape : ProfileOperandKind → Prop
  | .nativeObject => True
  | .nativePrototype => True
  | .invalidShape => False

inductive CompositionEntryPoint where
  | useComposition
  deriving DecidableEq, Repr

def AdmitsCompositionEntryPoint : CompositionEntryPoint → Prop
  | .useComposition => True

structure ProfilesStrategy where
  firstClassPooObject : Prop
  firstClassEstablished : firstClassPooObject
  usesKindToken : Prop
  noKindToken : ¬ usesKindToken
  readsHiddenRegistry : Prop
  noHiddenRegistry : ¬ readsHiddenRegistry
  createsSecondObjectRuntime : Prop
  noSecondObjectRuntime : ¬ createsSecondObjectRuntime

structure TwoStageAdmission where
  operandShape : ProfileOperandKind
  shapeAdmitted : AdmitsOperandShape operandShape
  instantiatedResultIsProfileObject : Prop
  semanticContractEstablished : instantiatedResultIsProfileObject

inductive CycleKind where
  | prototypeRecursion
  | inheritanceCycle
  deriving DecidableEq, Repr

def UsesNativeFixedPoint : CycleKind → Prop
  | .prototypeRecursion => True
  | .inheritanceCycle => False

def AdmitsC3Precedence : CycleKind → Prop
  | .prototypeRecursion => True
  | .inheritanceCycle => False

structure PriorityBoundary where
  slotLocalContributionPriority : Prop
  slotPriorityEstablished : slotLocalContributionPriority
  changesC3Precedence : Prop
  noC3PrecedenceChange : ¬ changesC3Precedence

structure PoofCorrespondence where
  usesPinnedGerbilPooConstruction : Prop
  pinnedConstructionEstablished : usesPinnedGerbilPooConstruction
  inventsLocalLiftingFormula : Prop
  noLocalLiftingFormula : ¬ inventsLocalLiftingFormula
  reducesAllCompositionToMix : Prop
  noUniversalMixReduction : ¬ reducesAllCompositionToMix

open LeanPoo.Prototype

/-- Profile refinements use the dependency's actual ordered prototype chain.
The head is the child; regrouping cannot reorder operands or change final self. -/
theorem profileHeadRefinesInheritedTail
    (head : Proto Self Profile Profile) (tail : List (Proto Self Profile Profile))
    (self : Self) (base : Profile) :
    composeAll (head :: tail) self base = head self (composeAll tail self base) := rfl

theorem profileRefinementsKeepFinalSelf
    (child : Proto Self Profile Profile) (parent : Proto Self Base Profile)
    (base : Base) :
    Generator.applyProto child (Generator.ofProto parent base) =
      Generator.ofProto (compose child parent) base :=
  Generator.applyProto_ofProto child parent base

-- Refinement order is observable; composition is not commutative.
#guard composeAll [fun (_ : Unit) (value : Nat) => value + 1,
    fun _ value => value * 2] () 3 == 7
#guard composeAll [fun (_ : Unit) (value : Nat) => value * 2,
    fun _ value => value + 1] () 3 == 8

theorem nativeObjectShapeIsAdmitted :
    AdmitsOperandShape .nativeObject := by
  simp [AdmitsOperandShape]

theorem nativePrototypeShapeIsAdmitted :
    AdmitsOperandShape .nativePrototype := by
  simp [AdmitsOperandShape]

theorem invalidOperandShapeFailsClosed :
    ¬ AdmitsOperandShape .invalidShape := by
  simp [AdmitsOperandShape]

theorem useCompositionIsCanonical :
    AdmitsCompositionEntryPoint .useComposition := by
  simp [AdmitsCompositionEntryPoint]

theorem prototypeRecursionUsesNativeFixedPoint :
    UsesNativeFixedPoint .prototypeRecursion := by
  simp [UsesNativeFixedPoint]

theorem inheritanceCycleFailsC3Admission :
    ¬ AdmitsC3Precedence .inheritanceCycle := by
  simp [AdmitsC3Precedence]


end PooFlowCoreProof.ProfileComposition.Prototype
