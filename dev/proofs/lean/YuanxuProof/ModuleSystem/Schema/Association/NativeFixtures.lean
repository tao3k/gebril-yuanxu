-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors

-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import YuanxuProof.ModuleSystem.Schema.Association.Correspondence

-- Generated only from the actual native transcript. Do not hand-edit observations.

-- Transcript SHA-256: c85f328ee6ccd77d5700906287c820399a51cb77c7a812235e90b19c745fda66

namespace YuanxuProof.ModuleSystem.Schema.Association.NativeFixtures

open Projection

def insertID (value : Nat) : List Nat → List Nat
  | [] => [value]
  | head :: tail => if value ≤ head then value :: head :: tail else head :: insertID value tail

def canonical : List Nat → List Nat
  | [] => []
  | head :: tail => insertID head (canonical tail)

def graph0 : Parents
  | 0 => [1]
  | 1 => []
  | _ => []


def roots0 : List Anchor := [⟨1, 2, 1, 1⟩, ⟨1, 3, 1, 1⟩, ⟨4, 5, 1, 1⟩, ⟨6, 7, 1, 1⟩]

#guard (match Traversal.visit graph0 4 0 [] [] with
  | .error _ => false
  | .ok done => canonical ((Traversal.dfsAssociations done roots0).map Anchor.contract) == canonical [2, 3])

example : ((match Traversal.visit graph0 4 0 [] [] with
  | .error _ => false
  | .ok done => canonical ((Traversal.dfsAssociations done roots0).map Anchor.contract) == canonical [2, 3])) = true := by decide

#guard finalValueGate (fun _ => [8, 9, 10, 11]) ⟨0, 0, 1, 1, 1⟩ [8, 9, 10, 11] == true

example : (finalValueGate (fun _ => [8, 9, 10, 11]) ⟨0, 0, 1, 1, 1⟩ [8, 9, 10, 11] == true) = true := by decide

def graph1 : Parents
  | 13 => [0, 4]
  | 0 => [1]
  | 1 => []
  | 4 => []
  | _ => []


def roots1 : List Anchor := [⟨1, 2, 1, 1⟩, ⟨1, 3, 1, 1⟩, ⟨4, 5, 1, 1⟩, ⟨6, 7, 1, 1⟩]

#guard (match Traversal.visit graph1 6 13 [] [] with
  | .error _ => false
  | .ok done => canonical ((Traversal.dfsAssociations done roots1).map Anchor.contract) == canonical [5, 2, 3])

example : ((match Traversal.visit graph1 6 13 [] [] with
  | .error _ => false
  | .ok done => canonical ((Traversal.dfsAssociations done roots1).map Anchor.contract) == canonical [5, 2, 3])) = true := by decide

#guard finalValueGate (fun _ => [14, 15, 16, 17]) ⟨13, 0, 1, 1, 1⟩ [14, 15, 16, 17] == true

example : (finalValueGate (fun _ => [14, 15, 16, 17]) ⟨13, 0, 1, 1, 1⟩ [14, 15, 16, 17] == true) = true := by decide

def graph2 : Parents
  | 19 => [20, 21]
  | 20 => [1]
  | 1 => []
  | 21 => [1]
  | _ => []


def roots2 : List Anchor := [⟨1, 2, 1, 1⟩, ⟨1, 3, 1, 1⟩, ⟨4, 5, 1, 1⟩, ⟨6, 7, 1, 1⟩]

#guard (match Traversal.visit graph2 6 19 [] [] with
  | .error _ => false
  | .ok done => canonical ((Traversal.dfsAssociations done roots2).map Anchor.contract) == canonical [2, 3])

example : ((match Traversal.visit graph2 6 19 [] [] with
  | .error _ => false
  | .ok done => canonical ((Traversal.dfsAssociations done roots2).map Anchor.contract) == canonical [2, 3])) = true := by decide

#guard finalValueGate (fun _ => [22, 23, 24]) ⟨19, 0, 1, 1, 1⟩ [22, 23, 24] == true

example : (finalValueGate (fun _ => [22, 23, 24]) ⟨19, 0, 1, 1, 1⟩ [22, 23, 24] == true) = true := by decide

def graph3 : Parents
  | 26 => [1]
  | 1 => []
  | _ => []


def roots3 : List Anchor := [⟨1, 2, 1, 1⟩, ⟨1, 3, 1, 1⟩, ⟨4, 5, 1, 1⟩, ⟨6, 7, 1, 1⟩]

#guard (match Traversal.visit graph3 4 26 [] [] with
  | .error _ => false
  | .ok done => canonical ((Traversal.dfsAssociations done roots3).map Anchor.contract) == canonical [2, 3])

example : ((match Traversal.visit graph3 4 26 [] [] with
  | .error _ => false
  | .ok done => canonical ((Traversal.dfsAssociations done roots3).map Anchor.contract) == canonical [2, 3])) = true := by decide

#guard finalValueGate (fun _ => [27, 28, 29]) ⟨26, 0, 1, 1, 1⟩ [27, 28, 29] == true

example : (finalValueGate (fun _ => [27, 28, 29]) ⟨26, 0, 1, 1, 1⟩ [27, 28, 29] == true) = true := by decide

def graph4 : Parents
  | 31 => [0]
  | 0 => [1]
  | 1 => []
  | _ => []


def roots4 : List Anchor := [⟨1, 2, 1, 1⟩, ⟨1, 3, 1, 1⟩, ⟨4, 5, 1, 1⟩, ⟨6, 7, 1, 1⟩]

#guard (match Traversal.visit graph4 5 31 [] [] with
  | .error _ => false
  | .ok done => canonical ((Traversal.dfsAssociations done roots4).map Anchor.contract) == canonical [2, 3])

example : ((match Traversal.visit graph4 5 31 [] [] with
  | .error _ => false
  | .ok done => canonical ((Traversal.dfsAssociations done roots4).map Anchor.contract) == canonical [2, 3])) = true := by decide

#guard finalValueGate (fun _ => [35, 36, 37, 38]) ⟨31, 0, 1, 1, 1⟩ [32, 33, 34] == false

example : (finalValueGate (fun _ => [35, 36, 37, 38]) ⟨31, 0, 1, 1, 1⟩ [32, 33, 34] == false) = true := by decide

def graph5 : Parents
  | 41 => [42]
  | 42 => [1]
  | 1 => []
  | _ => []


def roots5 : List Anchor := [⟨1, 2, 1, 1⟩, ⟨1, 3, 1, 1⟩, ⟨4, 5, 1, 1⟩, ⟨6, 7, 1, 1⟩]

#guard (match Traversal.visit graph5 5 41 [] [] with
  | .error _ => false
  | .ok done => canonical ((Traversal.dfsAssociations done roots5).map Anchor.contract) == canonical [2, 3])

example : ((match Traversal.visit graph5 5 41 [] [] with
  | .error _ => false
  | .ok done => canonical ((Traversal.dfsAssociations done roots5).map Anchor.contract) == canonical [2, 3])) = true := by decide

#guard finalValueGate (fun _ => [43, 44, 45]) ⟨41, 0, 1, 1, 1⟩ [32, 33, 34] == false

example : (finalValueGate (fun _ => [43, 44, 45]) ⟨41, 0, 1, 1, 1⟩ [32, 33, 34] == false) = true := by decide

def requirementResult0 : Nat → Bool
  | 2 => true
  | 7 => false
  | 3 => true
  | _ => false

#guard (match compositionGate [2, 7] [2, 3] requirementResult0 with
  | .ok _ => true | .error _ => false) == false

example : ((match compositionGate [2, 7] [2, 3] requirementResult0 with
  | .ok _ => true | .error _ => false) == false) = true := by decide

def requirementResult1 : Nat → Bool
  | 2 => true
  | 7 => false
  | 3 => true
  | _ => false

#guard (match compositionGate [2, 7] [2, 7] requirementResult1 with
  | .ok _ => true | .error _ => false) == false

example : ((match compositionGate [2, 7] [2, 7] requirementResult1 with
  | .ok _ => true | .error _ => false) == false) = true := by decide

def cycleGraph0 : Parents
  | 68 => [68]
  | _ => []


#guard (match Traversal.visit cycleGraph0 3 68 [] [] with
  | .error (.cycle node) => node == 68 | _ => false)

example : ((match Traversal.visit cycleGraph0 3 68 [] [] with
  | .error (.cycle node) => node == 68 | _ => false)) = true := by decide

def identityObservations : List (Nat × Nat × Bool) := [(1, 1, true), (1, 1, true), (1, 0, false), (1, 13, false), (1, 4, false), (1, 69, false), (1, 59, false), (1, 69, false), (1, 32, false), (1, 8, false), (1, 70, false), (1, 71, false), (1, 1, true), (1, 1, true), (1, 0, false), (1, 13, false), (1, 4, false), (1, 69, false), (1, 59, false), (1, 69, false), (1, 32, false), (1, 8, false), (1, 70, false), (1, 71, false), (0, 1, false), (0, 1, false), (0, 0, true), (0, 13, false), (0, 4, false), (0, 69, false), (0, 59, false), (0, 69, false), (0, 32, false), (0, 8, false), (0, 70, false), (0, 71, false), (13, 1, false), (13, 1, false), (13, 0, false), (13, 13, true), (13, 4, false), (13, 69, false), (13, 59, false), (13, 69, false), (13, 32, false), (13, 8, false), (13, 70, false), (13, 71, false), (4, 1, false), (4, 1, false), (4, 0, false), (4, 13, false), (4, 4, true), (4, 69, false), (4, 59, false), (4, 69, false), (4, 32, false), (4, 8, false), (4, 70, false), (4, 71, false), (69, 1, false), (69, 1, false), (69, 0, false), (69, 13, false), (69, 4, false), (69, 69, true), (69, 59, false), (69, 69, true), (69, 32, false), (69, 8, false), (69, 70, false), (69, 71, false), (59, 1, false), (59, 1, false), (59, 0, false), (59, 13, false), (59, 4, false), (59, 69, false), (59, 59, true), (59, 69, false), (59, 32, false), (59, 8, false), (59, 70, false), (59, 71, false), (69, 1, false), (69, 1, false), (69, 0, false), (69, 13, false), (69, 4, false), (69, 69, true), (69, 59, false), (69, 69, true), (69, 32, false), (69, 8, false), (69, 70, false), (69, 71, false), (32, 1, false), (32, 1, false), (32, 0, false), (32, 13, false), (32, 4, false), (32, 69, false), (32, 59, false), (32, 69, false), (32, 32, true), (32, 8, false), (32, 70, false), (32, 71, false), (8, 1, false), (8, 1, false), (8, 0, false), (8, 13, false), (8, 4, false), (8, 69, false), (8, 59, false), (8, 69, false), (8, 32, false), (8, 8, true), (8, 70, false), (8, 71, false), (70, 1, false), (70, 1, false), (70, 0, false), (70, 13, false), (70, 4, false), (70, 69, false), (70, 59, false), (70, 69, false), (70, 32, false), (70, 8, false), (70, 70, true), (70, 71, false), (71, 1, false), (71, 1, false), (71, 0, false), (71, 13, false), (71, 4, false), (71, 69, false), (71, 59, false), (71, 69, false), (71, 32, false), (71, 8, false), (71, 70, false), (71, 71, true)]

#guard identityObservations.all (fun pair => (pair.1 == pair.2.1) == pair.2.2)

example : (identityObservations.all (fun pair => (pair.1 == pair.2.1) == pair.2.2)) = true := by decide

def evidence0 : Receipt :=
  { typed := true, contract := 2, candidate := 0, context := 12,
    classificationType := 2, classificationCandidate := 0, classificationContext := 12,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence0)

example : (decide (CoreRule evidence0)) = true := by decide

#guard receiptGate 2 0 12 evidence0 == true

example : (receiptGate 2 0 12 evidence0 == true) = true := by decide

def evidence1 : Receipt :=
  { typed := true, contract := 2, candidate := 13, context := 18,
    classificationType := 2, classificationCandidate := 13, classificationContext := 18,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence1)

example : (decide (CoreRule evidence1)) = true := by decide

#guard receiptGate 2 13 18 evidence1 == true

example : (receiptGate 2 13 18 evidence1 == true) = true := by decide

def evidence2 : Receipt :=
  { typed := true, contract := 2, candidate := 19, context := 25,
    classificationType := 2, classificationCandidate := 19, classificationContext := 25,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence2)

example : (decide (CoreRule evidence2)) = true := by decide

#guard receiptGate 2 19 25 evidence2 == true

example : (receiptGate 2 19 25 evidence2 == true) = true := by decide

def evidence3 : Receipt :=
  { typed := true, contract := 2, candidate := 26, context := 30,
    classificationType := 2, classificationCandidate := 26, classificationContext := 30,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence3)

example : (decide (CoreRule evidence3)) = true := by decide

#guard receiptGate 2 26 30 evidence3 == true

example : (receiptGate 2 26 30 evidence3 == true) = true := by decide

def evidence4 : Receipt :=
  { typed := true, contract := 2, candidate := 31, context := 39,
    classificationType := 2, classificationCandidate := 31, classificationContext := 39,
    classified := true, obligations := [40], accepted := false }

#guard decide (CoreRule evidence4)

example : (decide (CoreRule evidence4)) = true := by decide

#guard receiptGate 2 31 39 evidence4 == false

example : (receiptGate 2 31 39 evidence4 == false) = true := by decide

def evidence5 : Receipt :=
  { typed := true, contract := 2, candidate := 41, context := 46,
    classificationType := 2, classificationCandidate := 41, classificationContext := 46,
    classified := true, obligations := [47], accepted := false }

#guard decide (CoreRule evidence5)

example : (decide (CoreRule evidence5)) = true := by decide

#guard receiptGate 2 41 46 evidence5 == false

example : (receiptGate 2 41 46 evidence5 == false) = true := by decide

def evidence6 : Receipt :=
  { typed := true, contract := 5, candidate := 13, context := 48,
    classificationType := 5, classificationCandidate := 13, classificationContext := 48,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence6)

example : (decide (CoreRule evidence6)) = true := by decide

#guard receiptGate 5 13 48 evidence6 == true

example : (receiptGate 5 13 48 evidence6 == true) = true := by decide

def evidence7 : Receipt :=
  { typed := true, contract := 3, candidate := 13, context := 48,
    classificationType := 3, classificationCandidate := 13, classificationContext := 48,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence7)

example : (decide (CoreRule evidence7)) = true := by decide

#guard receiptGate 3 13 48 evidence7 == true

example : (receiptGate 3 13 48 evidence7 == true) = true := by decide

def evidence8 : Receipt :=
  { typed := true, contract := 7, candidate := 26, context := 49,
    classificationType := 7, classificationCandidate := 26, classificationContext := 49,
    classified := true, obligations := [50], accepted := false }

#guard decide (CoreRule evidence8)

example : (decide (CoreRule evidence8)) = true := by decide

#guard receiptGate 7 26 49 evidence8 == false

example : (receiptGate 7 26 49 evidence8 == false) = true := by decide

def evidence9 : Receipt :=
  { typed := true, contract := 2, candidate := 0, context := 52,
    classificationType := 2, classificationCandidate := 0, classificationContext := 52,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence9)

example : (decide (CoreRule evidence9)) = true := by decide

#guard receiptGate 2 0 51 evidence9 == false

example : (receiptGate 2 0 51 evidence9 == false) = true := by decide

def evidence10 : Receipt :=
  { typed := true, contract := 2, candidate := 0, context := 52,
    classificationType := 2, classificationCandidate := 0, classificationContext := 52,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence10)

example : (decide (CoreRule evidence10)) = true := by decide

#guard receiptGate 2 1 52 evidence10 == false

example : (receiptGate 2 1 52 evidence10 == false) = true := by decide

def evidence11 : Receipt :=
  { typed := true, contract := 2, candidate := 53, context := 54,
    classificationType := 2, classificationCandidate := 53, classificationContext := 54,
    classified := false, obligations := [], accepted := false }

#guard decide (CoreRule evidence11)

example : (decide (CoreRule evidence11)) = true := by decide

#guard receiptGate 2 53 54 evidence11 == false

example : (receiptGate 2 53 54 evidence11 == false) = true := by decide

def evidence12 : Receipt :=
  { typed := true, contract := 55, candidate := 0, context := 56,
    classificationType := 55, classificationCandidate := 0, classificationContext := 56,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence12)

example : (decide (CoreRule evidence12)) = true := by decide

#guard receiptGate 55 0 56 evidence12 == true

example : (receiptGate 55 0 56 evidence12 == true) = true := by decide

def evidence13 : Receipt :=
  { typed := true, contract := 57, candidate := 8, context := 56,
    classificationType := 57, classificationCandidate := 8, classificationContext := 56,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence13)

example : (decide (CoreRule evidence13)) = true := by decide

#guard receiptGate 57 8 56 evidence13 == true

example : (receiptGate 57 8 56 evidence13 == true) = true := by decide

def evidence14 : Receipt :=
  { typed := true, contract := 58, candidate := 59, context := 56,
    classificationType := 58, classificationCandidate := 59, classificationContext := 56,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence14)

example : (decide (CoreRule evidence14)) = true := by decide

#guard receiptGate 58 59 56 evidence14 == true

example : (receiptGate 58 59 56 evidence14 == true) = true := by decide

def evidence15 : Receipt :=
  { typed := true, contract := 55, candidate := 60, context := 61,
    classificationType := 55, classificationCandidate := 60, classificationContext := 61,
    classified := true, obligations := [62], accepted := false }

#guard decide (CoreRule evidence15)

example : (decide (CoreRule evidence15)) = true := by decide

#guard receiptGate 55 60 61 evidence15 == false

example : (receiptGate 55 60 61 evidence15 == false) = true := by decide

def evidence16 : Receipt :=
  { typed := true, contract := 57, candidate := 53, context := 61,
    classificationType := 57, classificationCandidate := 53, classificationContext := 61,
    classified := false, obligations := [], accepted := false }

#guard decide (CoreRule evidence16)

example : (decide (CoreRule evidence16)) = true := by decide

#guard receiptGate 57 53 61 evidence16 == false

example : (receiptGate 57 53 61 evidence16 == false) = true := by decide

def evidence17 : Receipt :=
  { typed := true, contract := 58, candidate := 63, context := 61,
    classificationType := 58, classificationCandidate := 63, classificationContext := 61,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence17)

example : (decide (CoreRule evidence17)) = true := by decide

#guard receiptGate 58 63 61 evidence17 == true

example : (receiptGate 58 63 61 evidence17 == true) = true := by decide

def evidence18 : Receipt :=
  { typed := true, contract := 55, candidate := 64, context := 65,
    classificationType := 55, classificationCandidate := 64, classificationContext := 65,
    classified := false, obligations := [], accepted := false }

#guard decide (CoreRule evidence18)

example : (decide (CoreRule evidence18)) = true := by decide

#guard receiptGate 55 64 65 evidence18 == false

example : (receiptGate 55 64 65 evidence18 == false) = true := by decide

def evidence19 : Receipt :=
  { typed := true, contract := 2, candidate := 13, context := 48,
    classificationType := 2, classificationCandidate := 13, classificationContext := 48,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence19)

example : (decide (CoreRule evidence19)) = true := by decide

#guard receiptGate 2 13 48 evidence19 == true

example : (receiptGate 2 13 48 evidence19 == true) = true := by decide

def evidence20 : Receipt :=
  { typed := true, contract := 2, candidate := 26, context := 49,
    classificationType := 2, classificationCandidate := 26, classificationContext := 49,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence20)

example : (decide (CoreRule evidence20)) = true := by decide

#guard receiptGate 2 26 49 evidence20 == true

example : (receiptGate 2 26 49 evidence20 == true) = true := by decide

def evidence21 : Receipt :=
  { typed := true, contract := 3, candidate := 26, context := 49,
    classificationType := 3, classificationCandidate := 26, classificationContext := 49,
    classified := true, obligations := [], accepted := true }

#guard decide (CoreRule evidence21)

example : (decide (CoreRule evidence21)) = true := by decide

#guard receiptGate 3 26 49 evidence21 == true

example : (receiptGate 3 26 49 evidence21 == true) = true := by decide

def evidence22 : Receipt :=
  { typed := true, contract := 7, candidate := 26, context := 49,
    classificationType := 7, classificationCandidate := 26, classificationContext := 49,
    classified := true, obligations := [66], accepted := false }

#guard decide (CoreRule evidence22)

example : (decide (CoreRule evidence22)) = true := by decide

#guard receiptGate 7 26 49 evidence22 == false

example : (receiptGate 7 26 49 evidence22 == false) = true := by decide

def evidence23 : Receipt :=
  { typed := true, contract := 7, candidate := 26, context := 49,
    classificationType := 7, classificationCandidate := 26, classificationContext := 49,
    classified := true, obligations := [67], accepted := false }

#guard decide (CoreRule evidence23)

example : (decide (CoreRule evidence23)) = true := by decide

#guard receiptGate 7 26 49 evidence23 == false

example : (receiptGate 7 26 49 evidence23 == false) = true := by decide

#guard decide (ResponsibilityRule evidence12 [evidence13, evidence14] [])

example : (decide (ResponsibilityRule evidence12 [evidence13, evidence14] [])) = true := by decide

#guard decide (ResponsibilityRule evidence15 [evidence16, evidence17] [])

example : (decide (ResponsibilityRule evidence15 [evidence16, evidence17] [])) = true := by decide

#guard decide (ResponsibilityRule evidence18 [] [])

example : (decide (ResponsibilityRule evidence18 [] [])) = true := by decide

def boundaryGraph0 : Parents
  | 13 => [0, 4]
  | 0 => [1]
  | 1 => []
  | 4 => []
  | _ => []


def boundaryRoots0 : List Anchor := [⟨1, 2, 1, 1⟩, ⟨1, 3, 1, 1⟩, ⟨4, 5, 1, 1⟩, ⟨6, 7, 1, 1⟩]

def boundaryReceipts0 : Nat → Receipt
  | 5 => evidence6
  | 2 => evidence19
  | 3 => evidence7
  | _ => { typed := false, contract := 0, candidate := 0, context := 0, classificationType := 0, classificationCandidate := 0, classificationContext := 0, classified := false, obligations := [], accepted := false }

#guard (match Traversal.visit boundaryGraph0 6 13 [] [] with
  | .error _ => false
  | .ok done => match Correspondence.checkedBoundary done boundaryRoots0 [] [5, 2, 3] 13 48 boundaryReceipts0 with
    | .ok _ => true | .error _ => false) == true

example : ((match Traversal.visit boundaryGraph0 6 13 [] [] with
  | .error _ => false
  | .ok done => match Correspondence.checkedBoundary done boundaryRoots0 [] [5, 2, 3] 13 48 boundaryReceipts0 with
    | .ok _ => true | .error _ => false) == true) = true := by decide

def boundaryGraph1 : Parents
  | 26 => [1]
  | 1 => []
  | _ => []


def boundaryRoots1 : List Anchor := [⟨1, 2, 1, 1⟩, ⟨1, 3, 1, 1⟩, ⟨4, 5, 1, 1⟩, ⟨6, 7, 1, 1⟩]

def boundaryReceipts1 : Nat → Receipt
  | 2 => evidence20
  | 3 => evidence21
  | 7 => evidence22
  | _ => { typed := false, contract := 0, candidate := 0, context := 0, classificationType := 0, classificationCandidate := 0, classificationContext := 0, classified := false, obligations := [], accepted := false }

#guard (match Traversal.visit boundaryGraph1 4 26 [] [] with
  | .error _ => false
  | .ok done => match Correspondence.checkedBoundary done boundaryRoots1 [7] [2, 3] 26 49 boundaryReceipts1 with
    | .ok _ => true | .error _ => false) == false

example : ((match Traversal.visit boundaryGraph1 4 26 [] [] with
  | .error _ => false
  | .ok done => match Correspondence.checkedBoundary done boundaryRoots1 [7] [2, 3] 26 49 boundaryReceipts1 with
    | .ok _ => true | .error _ => false) == false) = true := by decide

def boundaryGraph2 : Parents
  | 26 => [1]
  | 1 => []
  | _ => []


def boundaryRoots2 : List Anchor := [⟨1, 2, 1, 1⟩, ⟨1, 3, 1, 1⟩, ⟨4, 5, 1, 1⟩, ⟨6, 7, 1, 1⟩]

def boundaryReceipts2 : Nat → Receipt
  | 2 => evidence20
  | 3 => evidence21
  | 7 => evidence23
  | _ => { typed := false, contract := 0, candidate := 0, context := 0, classificationType := 0, classificationCandidate := 0, classificationContext := 0, classified := false, obligations := [], accepted := false }

#guard (match Traversal.visit boundaryGraph2 4 26 [] [] with
  | .error _ => false
  | .ok done => match Correspondence.checkedBoundary done boundaryRoots2 [7] [2, 3, 7] 26 49 boundaryReceipts2 with
    | .ok _ => true | .error _ => false) == false

example : ((match Traversal.visit boundaryGraph2 4 26 [] [] with
  | .error _ => false
  | .ok done => match Correspondence.checkedBoundary done boundaryRoots2 [7] [2, 3, 7] 26 49 boundaryReceipts2 with
    | .ok _ => true | .error _ => false) == false) = true := by decide

end YuanxuProof.ModuleSystem.Schema.Association.NativeFixtures
