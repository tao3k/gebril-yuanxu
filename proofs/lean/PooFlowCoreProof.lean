-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PooFlowCoreProof.ModuleSystem.Workflow
import PooFlowCoreProof.Admission.Publication.ActiveHead
import PooFlowCoreProof.Admission.Isolation
import PooFlowCoreProof.Composition.Identity
import PooFlowCoreProof.Composition.Receipt
import PooFlowCoreProof.PooClos.ConservativeExtension
import PooFlowCoreProof.Modules.Funflow.Continuation
import PooFlowCoreProof.Contribution.Qualification
import PooFlowCoreProof.Modules.Funflow.ProfileProjection
import PooFlowCoreProof.Modules.Funflow.Policy
import PooFlowCoreProof.Admission.Federation
import PooFlowCoreProof.ModuleSystem.Source.Identity
import PooFlowCoreProof.Admission.Cache
import PooFlowCoreProof.Modules.Funflow.Delegation
import PooFlowCoreProof.FeatureSystem.DomainCase.Resolution
import PooFlowCoreProof.Modules.Funflow.Context
import PooFlowCoreProof.Modules.Funflow.CausalCut
import PooFlowCoreProof.Admission.Retention
import PooFlowCoreProof.Modules.Funflow.Entropy
import PooFlowCoreProof.ModuleSystem.Selection.Requirements
import PooFlowCoreProof.Modules.Funflow.Observation
import PooFlowCoreProof.Admission.Publication.Retirement
import PooFlowCoreProof.PooClos.Runtime
import PooFlowCoreProof.PooClos.Refinement
import PooFlowCoreProof.Admission.Decision
import PooFlowCoreProof.Admission.Publication.Rollout
import PooFlowCoreProof.Graph.Compatibility
import PooFlowCoreProof.Graph.Operations
import PooFlowCoreProof.Graph.Cache
import PooFlowCoreProof.Graph.ConclusionRevision
import PooFlowCoreProof.ProfileComposition.Composition
import PooFlowCoreProof.ModuleSystem.Imports
import PooFlowCoreProof.ModuleSystem.Graph.Roles
import PooFlowCoreProof.Admission.Publication.Atomicity
import PooFlowCoreProof.ModuleSystem.Source.Namespaces
import PooFlowCoreProof.ModuleSystem.Schema.Query
import PooFlowCoreProof.Admission.ObservationSet
import PooFlowCoreProof.ModuleSystem.Ownership
import PooFlowCoreProof.Admission.Publication.StateMigration
import PooFlowCoreProof.ModuleSystem.Schema.Resolution
import PooFlowCoreProof.Modules.Funflow.Control
import PooFlowCoreProof.PooClos.ProofBoundary
import PooFlowCoreProof.Admission.KeyLifecycle
import PooFlowCoreProof.ProfileComposition.BundleIdentity
import PooFlowCoreProof.ProfileComposition.Prototype
import PooFlowCoreProof.ProfileComposition.Revision
import PooFlowCoreProof.Admission.Publication.Activation
import PooFlowCoreProof.Admission.Realization
import PooFlowCoreProof.Modules.Funflow.Resources
import PooFlowCoreProof.ModuleSystem.Schema.Contracts
import PooFlowCoreProof.ModuleSystem.Graph.Aggregation
import PooFlowCoreProof.ModuleSystem.Schema.Demand
import PooFlowCoreProof.Modules.Funflow.Strategy
import PooFlowCoreProof.ProfileComposition.Syntax
import PooFlowCoreProof.ModuleSystem.Schema.Association.Semantics
import PooFlowCoreProof.ModuleSystem.Schema.Association.Traversal
import PooFlowCoreProof.ModuleSystem.Schema.Association.Projection
import PooFlowCoreProof.ModuleSystem.Schema.Association.Correspondence
import PooFlowCoreProof.ModuleSystem.Schema.Association.Requirements
import PooFlowCoreProof.ModuleSystem.Schema.Association.Construction
import PooFlowCoreProof.ModuleSystem.Schema.Association.Selection
import PooFlowCoreProof.ModuleSystem.Schema.Association.NativeFixtures
import PooFlowCoreProof.ModuleSystem.Schema.Association.Controls
import Lean.Util.CollectAxioms
import Lean.Elab.Command

/-! Build every Core owner and audit the complete imported Core closure together.
This checks trust dependencies, not whether domain premises describe the runtime. -/
open Lean Elab Command
run_cmd do
  let environment ← getEnv
  let allowed := #[`propext, `Classical.choice, `Quot.sound]
  let owners := #[`PooFlowCoreProof]
  for required in #[
      `PooFlowCoreProof.ModuleSystem.Workflow.cached_checks_remain_current,
      `PooFlowCoreProof.ModuleSystem.Workflow.Revision.revision_requires_discharge,
      `PooFlowCoreProof.ModuleSystem.Workflow.Revision.stale_cannot_be_certified,
      `PooFlowCoreProof.ModuleSystem.Schema.Association.Projection.accepted_receipt_discharged] do
    unless environment.contains required do
      throwError "Required Core integration theorem was not loaded: {required}"
  let mut count : Nat := 0
  for (name, _) in environment.constants.toList do
    if owners.any (·.isPrefixOf name) then
      count := count + 1
      for axiomName in (← collectAxioms name) do
        unless allowed.contains axiomName do
          throwError "{name} depends on disallowed axiom {axiomName}"
  if count = 0 then throwError "No Core declarations were audited"
  logInfo m!"CORE-AXIOM-AUDIT-OK: {count} declarations; standard Lean axioms only"
