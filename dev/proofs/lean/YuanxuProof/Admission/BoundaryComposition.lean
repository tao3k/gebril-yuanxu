-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.SourceWindows

/-! Composition of structurally checked operations, without a result cache.
`checked` requires extraction of the actual paired procedure and exact guard;
it is not a user-supplied purity assertion. Matching Scheme metadata, passive
source guards and stable pure intervals remain correspondence premises. -/
namespace YuanxuProof.Admission.BoundaryComposition
open SourceWindows

abbrev Action := World → Option World

inductive Operation where
  | checked (action : Action) (tailAvailable : World → Bool)
  | opaque (action : Action)

def guarded (valid : World → Bool) (action : Action) (world : World) : Option World :=
  if valid world then
    (action world).bind (fun next => if valid next then some next else none)
  else none

-- Original wrapper composition: each checked call owns both boundaries,
-- and the enclosing caller also checks the final world.
def originalTail (valid : World → Bool) : List Operation → World → Option World
  | [], world => if valid world then some world else none
  | .checked action _ :: rest, world =>
      (guarded valid action world).bind (originalTail valid rest)
  | .opaque action :: rest, world =>
      (action world).bind (originalTail valid rest)

-- The local bit describes only the immediately preceding closed boundary.
-- Opaque code clears it. Metadata invalidation may conservatively clear it too.
def normalizedTail (valid : World → Bool) : List Operation → Bool → World → Option World
  | [], known, world => if known || valid world then some world else none
  | .checked action available :: rest, known, world =>
      if known || valid world then
        (action world).bind (fun next =>
          if valid next then normalizedTail valid rest (available next) next else none)
      else none
  | .opaque action :: rest, _, world =>
      (action world).bind (normalizedTail valid rest false)

theorem tail_equivalent (valid : World → Bool) (operations : List Operation)
    (known : Bool) (world : World) (sound : known = true → valid world = true) :
    normalizedTail valid operations known world = originalTail valid operations world := by
  induction operations generalizing known world with
  | nil =>
      cases h : known <;> simp_all [normalizedTail, originalTail]
  | cons operation rest ih =>
      cases operation with
      | «opaque» action =>
          simp only [normalizedTail, originalTail]
          cases h : action world with
          | none => simp
          | some next => simpa using ih false next (by simp)
      | checked action available =>
          have entry : (known || valid world) = valid world := by
            cases h : known <;> simp_all
          simp only [normalizedTail, originalTail, guarded, entry]
          cases before : valid world with
          | false => simp
          | true =>
              simp only [↓reduceIte]
              cases result : action world with
              | none => simp
              | some next =>
                  cases after : valid next with
                  | false => simp [after]
                  | true =>
                      simpa [result, after] using (ih (available next) next (by intro _; exact after))

def original (valid : World → Bool) (operations : List Operation) (world : World) :=
  if valid world then originalTail valid operations world else none

def normalized (valid : World → Bool) (operations : List Operation) (world : World) :=
  if valid world then normalizedTail valid operations true world else none

theorem composition_equivalent (valid : World → Bool) (operations : List Operation)
    (world : World) : normalized valid operations world = original valid operations world := by
  cases current : valid world with
  | false => simp [normalized, original, current]
  | true => simpa [normalized, original, current] using
      tail_equivalent valid operations true world (by intro _; exact current)

theorem changed_after_action_rejected (valid : World → Bool) (action : Action)
    (available : World → Bool) (rest : List Operation) (known : Bool) (world next : World)
    (changed : action world = some next) (stale : valid next = false) :
    normalizedTail valid (.checked action available :: rest) known world = none := by
  simp [normalizedTail, changed, stale]

-- Reuse the existing actual byte-check model; no epoch oracle or new cache.
def bytesValid (inputs : List (String × String)) (world : World) : Bool :=
  (check inputs world empty).accepted

private def old : World := fun _ => some "old"
private def changed : World := fun _ => some "changed"
private def valid := bytesValid [("config.ss", "old")]
private def repair : Operation := .checked (fun _ => some old) (fun _ => true)

-- An opaque callback may write AFTER its own check. Its successor must refuse
-- before executing even a "repair" action that would hide that source change.
#guard (normalized valid [.opaque (fun _ => some changed), repair] old).isNone
-- Unsound carry across that callback would wrongly allow repair/publication.
#guard (normalizedTail valid [repair] true changed).isSome

#print axioms composition_equivalent
#print axioms changed_after_action_rejected

end YuanxuProof.Admission.BoundaryComposition
