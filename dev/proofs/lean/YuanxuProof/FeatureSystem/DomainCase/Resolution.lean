-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

namespace YuanxuProof.FeatureSystem.DomainCase.Resolution

universe u v

/-- A projected winner entry can be retired without shifting the remaining
    source-order entries. -/
structure ResolutionEntry (Value : Type u) where
  value : Value
  active : Bool
deriving Repr, DecidableEq

def activeValues : List (ResolutionEntry Value) -> List Value
  | [] => []
  | entry :: rest =>
      if entry.active then entry.value :: activeValues rest
      else activeValues rest

def retireBy
    [DecidableEq Key]
    (keyOf : Value -> Key)
    (key : Key) :
    List (ResolutionEntry Value) -> List (ResolutionEntry Value)
  | [] => []
  | entry :: rest =>
      { entry with
          active := entry.active && decide (keyOf entry.value != key) } ::
        retireBy keyOf key rest

def referenceReplace
    [DecidableEq Key]
    (keyOf : Value -> Key)
    (candidate : Value)
    (entries : List (ResolutionEntry Value)) : List Value :=
  (activeValues entries).filter
      (fun value => decide (keyOf value != keyOf candidate)) ++
    [candidate]

def indexedReplace
    [DecidableEq Key]
    (keyOf : Value -> Key)
    (candidate : Value)
    (entries : List (ResolutionEntry Value)) : List (ResolutionEntry Value) :=
  retireBy keyOf (keyOf candidate) entries ++
    [{ value := candidate, active := true }]

theorem activeValues_append
    (left right : List (ResolutionEntry Value)) :
    activeValues (left ++ right) = activeValues left ++ activeValues right := by
  induction left with
  | nil => rfl
  | cons entry rest inductionHypothesis =>
      cases active : entry.active <;>
        simp [activeValues, active, inductionHypothesis]

theorem activeValues_retireBy
    [DecidableEq Key]
    (keyOf : Value -> Key)
    (key : Key)
    (entries : List (ResolutionEntry Value)) :
    activeValues (retireBy keyOf key entries) =
      (activeValues entries).filter
        (fun value => decide (keyOf value != key)) := by
  induction entries with
  | nil => rfl
  | cons entry rest inductionHypothesis =>
      cases active : entry.active
      · simp [retireBy, activeValues, active, inductionHypothesis]
      · by_cases sameKey : keyOf entry.value = key
        · simp [retireBy, activeValues, active, sameKey,
                inductionHypothesis]
        · simp [retireBy, activeValues, active, sameKey,
                inductionHypothesis]

/-- Tombstone replacement has the same ordered projection as the former
    repeated filter-and-append reference algorithm. -/
theorem indexedReplace_preserves_reference_order
    [DecidableEq Key]
    (keyOf : Value -> Key)
    (candidate : Value)
    (entries : List (ResolutionEntry Value)) :
    activeValues (indexedReplace keyOf candidate entries) =
      referenceReplace keyOf candidate entries := by
  rw [indexedReplace, activeValues_append, activeValues_retireBy]
  simp [referenceReplace, activeValues]

/-- This is the pure projection of the native winner-index/tombstone loop.
The native hash index provides lookup; no O(1) cost follows from this list model. -/
def resolveCandidates [DecidableEq Key] (keyOf : Value → Key) (candidates : List Value) :=
  candidates.foldl (fun entries candidate => indexedReplace keyOf candidate entries) []

theorem replacement_unique_keys [DecidableEq Key] (keyOf : Value → Key) (candidate : Value)
    (entries : List (ResolutionEntry Value))
    (unique : ((activeValues entries).map keyOf).Nodup) :
    ((activeValues (indexedReplace keyOf candidate entries)).map keyOf).Nodup := by
  rw [indexedReplace_preserves_reference_order]
  simp only [referenceReplace, List.map_append, List.map_cons, List.map_nil]
  apply List.nodup_append.mpr
  refine ⟨?_, by simp, ?_⟩
  · have equal : ((activeValues entries).filter (fun value => decide (keyOf value != keyOf candidate))).map keyOf =
        ((activeValues entries).map keyOf).filter (fun key => decide (key != keyOf candidate)) := by
      simp [List.filter_map, Function.comp_def]
    rw [equal]
    exact unique.filter _
  · intro key present other last same
    have lastKey : other = keyOf candidate := by simpa using last
    obtain ⟨value, member, equal⟩ := List.mem_map.mp present
    have different : keyOf value ≠ keyOf candidate := by simpa using (List.mem_filter.mp member).2
    exact different (equal.trans (same.trans lastKey))

theorem constructed_winners_unique [DecidableEq Key] (keyOf : Value → Key) (candidates : List Value) :
    ((activeValues (resolveCandidates keyOf candidates)).map keyOf).Nodup := by
  have maintained : ∀ (entries : List (ResolutionEntry Value)),
      ((activeValues entries).map keyOf).Nodup →
      ((activeValues (candidates.foldl (fun current candidate => indexedReplace keyOf candidate current) entries)).map keyOf).Nodup := by
    induction candidates with
    | nil => intro entries unique; exact unique
    | cons candidate rest ih =>
      intro entries unique
      exact ih _ (replacement_unique_keys keyOf candidate entries unique)
  exact maintained [] (by simp [activeValues])
end YuanxuProof.FeatureSystem.DomainCase.Resolution
