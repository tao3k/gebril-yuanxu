-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! An admitted Module Core closure feeds the same ordered vertices and reads
into POO Graph as the synthetic Feature selections. Graph's schedule and SCC
result are abstract here, including rejection of cycles. Runtime admission,
constructor identity and observer compatibility remain Scheme obligations. -/
namespace YuanxuProof.ModuleSystem.Selection.CoreRows

abbrev Row (ID : Type) := ID × List ID

def vertices {ID : Type} (rows : List (Row ID)) : List ID := rows.map Prod.fst

def graphInput {ID : Type} (rows : List (Row ID)) :=
  (vertices rows, rows.filter fun row => !row.2.isEmpty)

def throughFeature {ID : Type} [DecidableEq ID] (keys : List ID)
    (row : Row ID) : Row ID :=
  (row.1, row.2.filter (· ∈ keys) ++ [])

theorem projection_preserves_graph {ID : Type} [DecidableEq ID]
    (rows : List (Row ID))
    (closed : ∀ row ∈ rows, ∀ dep ∈ row.2, dep ∈ vertices rows) :
    graphInput (rows.map (throughFeature (vertices rows))) = graphInput rows := by
  have same : rows.map (throughFeature (vertices rows)) = rows := by
    calc
      rows.map (throughFeature (vertices rows)) = rows.map id := ?_
      _ = rows := List.map_id rows
    apply List.map_congr_left
    intro row member
    simp only [throughFeature, List.append_nil, id_eq]
    have all : row.2.filter (· ∈ vertices rows) = row.2 :=
      List.filter_eq_self.mpr (fun dep h => decide_eq_true (closed row member dep h))
    cases row
    simp_all
  rw [same]

/-- Closure visits each owner once and hidden Core IDs are injective, so the
Feature resolver's first-occurrence index preserves the vertex order. Core
has no optional dependencies or conflicts. -/
theorem schedule_and_scc_agree {ID Result : Type} [DecidableEq ID]
    (resolve : List ID × List (Row ID) → Result) (rows : List (Row ID))
    (closed : ∀ row ∈ rows, ∀ dep ∈ row.2, dep ∈ vertices rows) :
    resolve (graphInput (rows.map (throughFeature (vertices rows)))) =
      resolve (graphInput rows) := by
  rw [projection_preserves_graph rows closed]

def publish {State Result : Type} (current : State → Bool) (progress : State → State)
    (before : State) (value : Result) : Option Result :=
  if current (progress before) then some value else none

/-- Currentness after progress delivery is independent of structural projection. -/
theorem refused_after_progress {State Result : Type} (current : State → Bool)
    (progress : State → State) (before : State) (value : Result)
    (changed : current (progress before) = false) :
    publish current progress before value = none := by
  simp [publish, changed]

end YuanxuProof.ModuleSystem.Selection.CoreRows
