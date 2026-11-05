-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Assembly

namespace YuanxuProof.Observability.TestingCase

/-! Factoring a Case's invocation does not memoize its method or result.
The state includes observable callback order; Except retains the original fault.
Scheme evaluation order and the POO lookup correspondence are executable gates.
This law does not assert a GC bound or authenticate arbitrary Scheme bodies. -/
def invoke [Monad m] (profile : P) (lookup : P → m F) (label : m L)
    (body : Unit → m A) (call : F → P → L → (Unit → m A) → m (A × R)) : m A := do
  let method ← lookup profile
  let description ← label
  let result ← call method profile description body
  pure result.1

def expanded [Monad m] (getProfile : m P) (lookup : P → m F) (label : m L)
    (body : Unit → m A) (call : F → P → L → (Unit → m A) → m (A × R)) : m A := do
  let profile ← getProfile
  let method ← lookup profile
  let description ← label
  let result ← call method profile description body
  pure result.1

theorem factoring_preserves_invocation [Monad m] (getProfile : m P)
    (lookup : P → m F) (label : m L) (body : Unit → m A)
    (call : F → P → L → (Unit → m A) → m (A × R)) :
    (do let profile ← getProfile; invoke profile lookup label body call) =
      expanded getProfile lookup label body call := rfl

end YuanxuProof.Observability.TestingCase
