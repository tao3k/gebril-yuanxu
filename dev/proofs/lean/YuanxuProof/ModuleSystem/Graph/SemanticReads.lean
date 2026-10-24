-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Logical completeness of a semantic-read projection, for arbitrary identities.
Quint checks finite mutation/publication schedules. These theorems do not certify
native read-token reconstruction, callback non-escape, or a byte/GC bound. -/
namespace YuanxuProof.ModuleSystem.Graph.SemanticReads

def Complete (required projected : α → Prop) : Prop :=
  ∀ node, required node → projected node

def Current (roots : α → Prop) (fresh : α → Prop) : Prop :=
  ∀ node, roots node → fresh node

theorem projected_current_implies_required_current
    {required projected fresh : α → Prop}
    (complete : Complete required projected) (current : Current projected fresh) :
    Current required fresh :=
  fun node needed => current node (complete node needed)

theorem relevant_change_refuses_publication
    {required projected fresh : α → Prop} {node : α}
    (complete : Complete required projected) (needed : required node)
    (changed : ¬ fresh node) : ¬ Current projected fresh := by
  intro current
  exact changed (projected_current_implies_required_current complete current node needed)

-- A class label cannot establish this premise. An escaped frame is required.
theorem escaping_frame_must_be_projected
    {required projected : α → Prop} {frame : α}
    (complete : Complete required projected) (escaped : required frame) :
    projected frame := complete frame escaped

-- Any missing identity admits an adversarial freshness assignment: every
-- projected node is current, yet that required identity has changed.
theorem omission_is_unsound [DecidableEq α]
    {required projected : α → Prop} {node : α}
    (needed : required node) (missing : ¬ projected node) :
    ∃ fresh : α → Prop, Current projected fresh ∧ ¬ Current required fresh := by
  refine ⟨fun other => other ≠ node, ?_, ?_⟩
  · intro other included equal
    subst other
    exact missing included
  · intro current
    exact current node needed rfl

theorem full_trace_fallback {required trace fresh : α → Prop}
    (covered : Complete required trace) (current : Current trace fresh) :
    Current required fresh :=
  projected_current_implies_required_current covered current

end YuanxuProof.ModuleSystem.Graph.SemanticReads
