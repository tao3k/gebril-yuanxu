-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PooFlowCoreProof.ProfileComposition.Composition
import PooFlowCoreProof.Modules.Funflow.Policy
import PooFlowCoreProof.Admission.Publication
import PooFlowCoreProof.PooClos.MethodCombination
import PooFlowCoreProof.ModuleSystem.Source.Ownership
import PooFlowCoreProof.ModuleSystem.Source.Collections
import PooFlowCoreProof.ModuleSystem.Building.Inputs
import PooFlowCoreProof.ModuleSystem.Workflow
import PooFlowCoreProof.ModuleSystem.Graph.ImportCorrespondence
import PooFlowCoreProof.ModuleSystem.Graph.TestAdmission
import PooFlowCoreProof.ModuleSystem.Graph.SourceClosureWork
import PooFlowCoreProof.ModuleSystem.Graph.SemanticReads
import PooFlowCoreProof.ModuleSystem.Graph.OwnedReads
import PooFlowCoreProof.ModuleSystem.Graph.PublicationReads
import PooFlowCoreProof.Composition.Overlay
import PooFlowCoreProof.Composition.Identity
import PooFlowCoreProof.PooClos.Outcomes
import PooFlowCoreProof.Modules.Funflow.Continuation
import PooFlowCoreProof.Contribution.Qualification
import PooFlowCoreProof.Admission.Federation
import PooFlowCoreProof.Admission.Source
import PooFlowCoreProof.Admission.SourceWindows
import PooFlowCoreProof.Admission.RootChild
import PooFlowCoreProof.Admission.ReturnWindows
import PooFlowCoreProof.Admission.BoundaryComposition
import PooFlowCoreProof.Admission.ReplayBoundary
import PooFlowCoreProof.Admission.IdentityDFS
import PooFlowCoreProof.Admission.DFSFrames
import PooFlowCoreProof.Admission.ReadOnlyEntry
import PooFlowCoreProof.Admission.SnapshotEntry
import PooFlowCoreProof.Admission.SnapshotLifetime
import PooFlowCoreProof.Admission.SerialUse
import PooFlowCoreProof.Admission.IssuedRootForwarding
import PooFlowCoreProof.Admission.ReadRetention
import PooFlowCoreProof.Admission.CallPhases
import PooFlowCoreProof.Admission.AdmissionBody
import PooFlowCoreProof.Admission.ReturnTail
import PooFlowCoreProof.Admission.ClosedTail
import PooFlowCoreProof.Admission.CheckerOrigin
import PooFlowCoreProof.Admission.MetadataRoute
import PooFlowCoreProof.Admission.IssuedRead
import PooFlowCoreProof.Admission.IssuerProjection
import PooFlowCoreProof.Admission.RouteMutation
import PooFlowCoreProof.Admission.ReplayOwnership
import PooFlowCoreProof.Admission.MetadataOwnership
import PooFlowCoreProof.Admission.MetadataAllocation
import PooFlowCoreProof.Admission.StoreLowering
import PooFlowCoreProof.Admission.ArtifactClosure
import PooFlowCoreProof.Admission.IssuedLoading
import PooFlowCoreProof.Admission.SourceLoader
import PooFlowCoreProof.Admission.CoreStoreRecovery
import PooFlowCoreProof.Admission.CoreApprovedRecovery
import PooFlowCoreProof.Admission.CoreBuildHandoff
import PooFlowCoreProof.Admission.CoreBuildPublication
import PooFlowCoreProof.FeatureSystem.DomainCase.Resolution
import PooFlowCoreProof.Modules.Funflow.Context
import PooFlowCoreProof.Modules.Funflow.CausalCut
import PooFlowCoreProof.ModuleSystem.Selection.Requirements
import PooFlowCoreProof.PooClos.NextMethod
import PooFlowCoreProof.PooClos.InstanceStorage
import PooFlowCoreProof.PooClos.Dispatch
import PooFlowCoreProof.PooClos.CarrierCapture
import PooFlowCoreProof.Admission.Decision
import PooFlowCoreProof.Graph.Payload
import PooFlowCoreProof.Ops.ProcessScript
import PooFlowCoreProof.ModuleSystem.Authoring.Queries
import PooFlowCoreProof.Graph.Operations
import PooFlowCoreProof.ModuleSystem.Graph.Cache
import PooFlowCoreProof.Modules.Funflow.ConclusionRevision
import PooFlowCoreProof.ModuleSystem.Imports
import PooFlowCoreProof.ModuleSystem.Schema.Query
import PooFlowCoreProof.ModuleSystem.Schema.Resolution
import PooFlowCoreProof.Modules.Funflow.Control
import PooFlowCoreProof.ProfileComposition.BundleIdentity
import PooFlowCoreProof.ProfileComposition.Prototype
import PooFlowCoreProof.ProfileComposition.Revision
import PooFlowCoreProof.Admission.Contributions
import PooFlowCoreProof.Admission.Realization
import PooFlowCoreProof.ModuleSystem.Schema.Contracts
import PooFlowCoreProof.ModuleSystem.Graph.Aggregation
import PooFlowCoreProof.ModuleSystem.Schema.Demand
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
      `PooFlowCoreProof.Admission.IssuedRootForwarding.preserves_issuance,
      `PooFlowCoreProof.Admission.ReadRetention.closure_coverage,
      `PooFlowCoreProof.Admission.ReadRetention.omitted_dependency_refused,
      `PooFlowCoreProof.Admission.ReadRetention.child_context_keeps_joint_claim,
      `PooFlowCoreProof.Admission.ReadRetention.changed_child_context_misses,
      `PooFlowCoreProof.Admission.IssuedRootForwarding.cannot_hide_unissued,
      `PooFlowCoreProof.Admission.IssuedRootForwarding.forward_keeps_dependency_closure,
      `PooFlowCoreProof.FeatureSystem.DomainCase.Resolution.constructed_winners_unique,
      `PooFlowCoreProof.PooClos.InstanceStorage.migration_reads_own_class,
      `PooFlowCoreProof.PooClos.InstanceStorage.subclass_metadata_retains_class_storage,
      `PooFlowCoreProof.Modules.Funflow.Context.demand_certificate_exact,
      `PooFlowCoreProof.ModuleSystem.Source.Ownership.located_owner_is_declared,
      `PooFlowCoreProof.ModuleSystem.Building.Inputs.contradictory_snapshot_rejected,
      `PooFlowCoreProof.ModuleSystem.Building.Inputs.tool_source_accepted_iff,
      `PooFlowCoreProof.ModuleSystem.Building.Inputs.publication_role_not_a_tool,
      `PooFlowCoreProof.Admission.RootChild.Routing.callback_reentry_is_independent,
      `PooFlowCoreProof.Admission.RootChild.Routing.owned_responsibility_uses_child_analysis,
      `PooFlowCoreProof.PooClos.Dispatch.selected_methods_reference,
      `PooFlowCoreProof.PooClos.Dispatch.cache_refines_reference,
      `PooFlowCoreProof.PooClos.NextMethod.changed_before_rejected,
      `PooFlowCoreProof.PooClos.InstanceStorage.surviving_cell_retained,
      `PooFlowCoreProof.Admission.Realization.validator_package_drift_preserves_previous,
      `PooFlowCoreProof.Admission.Contributions.accepted_row_exact,
      `PooFlowCoreProof.Composition.Overlay.indexed_overlay_matches_first_owner,
      `PooFlowCoreProof.ModuleSystem.Authoring.Queries.raw_claimed_query_refused,
      `PooFlowCoreProof.Graph.Payload.adjacent_appends_coalesce,
      `PooFlowCoreProof.Ops.ProcessScript.arguments_preserved,
      `PooFlowCoreProof.Modules.Funflow.Policy.validated_has_capability,
      `PooFlowCoreProof.Modules.Funflow.Policy.plan_error_has_rejected_node,
      `PooFlowCoreProof.Admission.Publication.check_certifies,
      `PooFlowCoreProof.Admission.Publication.stale_return_keeps_previous,
      `PooFlowCoreProof.ProfileComposition.Composition.composition_retains_existing,
      `PooFlowCoreProof.Admission.Publication.changed_source_rejected,
      `PooFlowCoreProof.ProfileComposition.Composition.conflicting_prefix_aborts,
      `PooFlowCoreProof.PooClos.MethodCombination.accepted_group_valid,
      `PooFlowCoreProof.PooClos.MethodCombination.applicable_reference,
      `PooFlowCoreProof.Contribution.Qualification.missingFacetEvidenceBlocksUse,
      `PooFlowCoreProof.Modules.Funflow.CausalCut.missingParentRejected,
      `PooFlowCoreProof.ProfileComposition.BundleIdentity.conflictingRevisionRejected,
      `PooFlowCoreProof.Admission.Source.changedSourceCannotBeCertified,
      `PooFlowCoreProof.Admission.Source.returnCheck_certifies,
      `PooFlowCoreProof.Admission.RootChild.child_sources,
      `PooFlowCoreProof.Admission.RootChild.stale_return_keeps_previous,
      `PooFlowCoreProof.Admission.RootChild.batching_equivalent,
      `PooFlowCoreProof.Admission.ReturnWindows.check_append,
      `PooFlowCoreProof.Admission.ReturnWindows.defer_covered_check,
      `PooFlowCoreProof.Admission.ReturnWindows.covered_suffix_zero_reads,
      `PooFlowCoreProof.Admission.ReturnWindows.joint_requirements_retained,
      `PooFlowCoreProof.Admission.ReturnWindows.cached_parent_rejected,
      `PooFlowCoreProof.Admission.ReturnWindows.fresh_after_callback_rejects_change,
      `PooFlowCoreProof.Admission.ReturnWindows.pure_tail_fixture_cost,
      `PooFlowCoreProof.Admission.BoundaryComposition.composition_equivalent,
      `PooFlowCoreProof.Admission.BoundaryComposition.changed_after_action_rejected,
      `PooFlowCoreProof.ModuleSystem.Graph.TestAdmission.discovery_visit_bound,
      `PooFlowCoreProof.Admission.ReplayBoundary.ordered_diagnostic_exact,
      `PooFlowCoreProof.Admission.ReplayBoundary.successful_coverage,
      `PooFlowCoreProof.Admission.ReplayBoundary.both_branches_retained,
      `PooFlowCoreProof.Admission.ReplayBoundary.enroll_complete,
      `PooFlowCoreProof.Admission.ReplayBoundary.enroll_retains_earlier,
      `PooFlowCoreProof.Admission.ReplayBoundary.failing_prefix_preserved,
      `PooFlowCoreProof.Admission.ReplayBoundary.moving_check_changes_diagnostic,
      `PooFlowCoreProof.Admission.ReplayBoundary.parent_token_rejected,
      `PooFlowCoreProof.Admission.ReplayBoundary.conflicting_source_requirement_retained,
      `PooFlowCoreProof.Admission.ReplayBoundary.changing_first_origin_changes_diagnostic,
      `PooFlowCoreProof.Admission.IdentityDFS.measure_decreases,
      `PooFlowCoreProof.Admission.IdentityDFS.walk_drains,
      `PooFlowCoreProof.Admission.IdentityDFS.discover_drained,
      `PooFlowCoreProof.Admission.IdentityDFS.discover_nodup,
      `PooFlowCoreProof.Admission.IdentityDFS.discover_exact,
      `PooFlowCoreProof.Admission.IdentityDFS.final_check_exact,
      `PooFlowCoreProof.Admission.IdentityDFS.final_covers_reachable,
      `PooFlowCoreProof.Admission.IdentityDFS.final_rejects_changed_record,
      `PooFlowCoreProof.Admission.IdentityDFS.accepted_reachable_source,
      `PooFlowCoreProof.Admission.IdentityDFS.graph_ordered_diagnostic,
      `PooFlowCoreProof.Admission.IdentityDFS.diamond_cycle_discovery,
      `PooFlowCoreProof.Admission.IdentityDFS.same_revision_does_not_imply_prepared,
      `PooFlowCoreProof.Admission.DFSFrames.return_stutters,
      `PooFlowCoreProof.Admission.DFSFrames.enter_refines,
      `PooFlowCoreProof.Admission.DFSFrames.frame_decreases,
      `PooFlowCoreProof.Admission.DFSFrames.frames_drain,
      `PooFlowCoreProof.Admission.DFSFrames.replay_nodup,
      `PooFlowCoreProof.Admission.DFSFrames.replay_exact,
      `PooFlowCoreProof.Admission.DFSFrames.final_covers_frames,
      `PooFlowCoreProof.Admission.ReadOnlyEntry.cold_order_has_no_protocol,
      `PooFlowCoreProof.Admission.ReadOnlyEntry.warm_state_closes,
      `PooFlowCoreProof.Admission.ReadOnlyEntry.cold_default_closes,
      `PooFlowCoreProof.Admission.ReadOnlyEntry.self_protocol_not_default,
      `PooFlowCoreProof.Admission.ReadOnlyEntry.successful_lowering_no_callbacks,
      `PooFlowCoreProof.Admission.ReadOnlyEntry.lowering_independent,
      `PooFlowCoreProof.Admission.ReadOnlyEntry.execute_preserves_protected,
      `PooFlowCoreProof.Admission.ReadOnlyEntry.ordered_failure_exact,
      `PooFlowCoreProof.Admission.ReadOnlyEntry.bootstrap_anchor_read,
      `PooFlowCoreProof.Admission.ReadOnlyEntry.bootstrap_still_current_after_clear,
      `PooFlowCoreProof.Admission.ReadOnlyEntry.ordinary_record_rejects_clear,
      `PooFlowCoreProof.Admission.ReadOnlyEntry.bootstrap_validity_not_readiness,
      `PooFlowCoreProof.Admission.ReadOnlyEntry.seal_does_not_change_inspection,
      `PooFlowCoreProof.Admission.ReadOnlyEntry.cold_dispatch_remains_open,
      `PooFlowCoreProof.Admission.SnapshotEntry.guard_accepts_exactly,
      `PooFlowCoreProof.Admission.SnapshotEntry.guard_rejects_changed,
      `PooFlowCoreProof.Admission.SnapshotEntry.guarded_projection,
      `PooFlowCoreProof.Admission.SnapshotEntry.guarded_no_callbacks,
      `PooFlowCoreProof.Admission.SnapshotEntry.ordered_first_failure,
      `PooFlowCoreProof.Admission.SnapshotEntry.clear_rejected_without_revision_change,
      `PooFlowCoreProof.Admission.SnapshotEntry.checker_change_rejected,
      `PooFlowCoreProof.Admission.SnapshotEntry.cached_value_change_rejected,
      `PooFlowCoreProof.Admission.SnapshotEntry.observer_change_rejected,
      `PooFlowCoreProof.Admission.SnapshotEntry.ancestor_change_rejected,
      `PooFlowCoreProof.Admission.SnapshotEntry.observer_aba_not_history,
      `PooFlowCoreProof.Admission.SnapshotEntry.equal_cut_not_source_authority,
      `PooFlowCoreProof.Admission.ClosedTail.opaque_refused_before_invocation,
      `PooFlowCoreProof.Admission.ClosedTail.closed_tail_preserves_state,
      `PooFlowCoreProof.Admission.ClosedTail.no_foreign_call,
      `PooFlowCoreProof.Admission.ClosedTail.accepted_retains_requirements,
      `PooFlowCoreProof.Admission.ClosedTail.accepted_replay_stays_current,
      `PooFlowCoreProof.Admission.ClosedTail.external_writer_still_requires_snapshot,
      `PooFlowCoreProof.Admission.ClosedTail.return_only_misses_cleanup,
      `PooFlowCoreProof.Admission.ClosedTail.earlier_source_failure_keeps_order,
      `PooFlowCoreProof.Admission.CheckerOrigin.accepted_record_has_native_identity_and_owner,
      `PooFlowCoreProof.Admission.CheckerOrigin.closure_covers_every_dependency,
      `PooFlowCoreProof.Admission.CheckerOrigin.copied_identity_does_not_copy_ownership,
      `PooFlowCoreProof.Admission.CheckerOrigin.raw_table_write_defeats_issuance_claim,
      `PooFlowCoreProof.Admission.CheckerOrigin.bootstrap_currentness_does_not_imply_ownership,
      `PooFlowCoreProof.Admission.CheckerOrigin.cache_miss_currentness_does_not_imply_ownership,
      `PooFlowCoreProof.Admission.CheckerOrigin.fixed_kernel_preserves_state,
      `PooFlowCoreProof.Admission.CheckerOrigin.fixed_identity_does_not_close_metadata_dispatch,
      `PooFlowCoreProof.Admission.CheckerOrigin.accepted_retains_two_requirements_and_child,
      `PooFlowCoreProof.Admission.CheckerOrigin.source_failure_precedes_gate_and_checker,
      `PooFlowCoreProof.Admission.MetadataRoute.full_gate_covers_nested_lookup,
      `PooFlowCoreProof.Admission.MetadataRoute.outer_ref_does_not_close_hash,
      `PooFlowCoreProof.Admission.MetadataRoute.reads_table_does_not_close_instance_table,
      `PooFlowCoreProof.Admission.MetadataRoute.closed_direct_call_preserves_state,
      `PooFlowCoreProof.Admission.MetadataRoute.entry_only_can_become_stale,
      `PooFlowCoreProof.Admission.MetadataRoute.equal_endpoints_do_not_erase_history,
      `PooFlowCoreProof.Admission.MetadataRoute.equal_miss_projection_gets_same_decision,
      `PooFlowCoreProof.Admission.MetadataRoute.no_projection_only_issuer,
      `PooFlowCoreProof.Admission.MetadataRoute.accepted_retains_requirements_and_child,
      `PooFlowCoreProof.Admission.MetadataRoute.earlier_source_diagnosis_preserved,
      `PooFlowCoreProof.Admission.IssuedRead.native_mint_authenticates,
      `PooFlowCoreProof.Admission.IssuedRead.public_constructor_is_not_issuance,
      `PooFlowCoreProof.Admission.IssuedRead.borrowed_birth_rejects_another_token,
      `PooFlowCoreProof.Admission.IssuedRead.changed_payload_rejected,
      `PooFlowCoreProof.Admission.IssuedRead.whole_closure_authenticates_every_selected_dependency,
      `PooFlowCoreProof.Admission.IssuedRead.transient_mint_needs_no_registration,
      `PooFlowCoreProof.Admission.IssuedRead.invalid_closure_observes_nothing,
      `PooFlowCoreProof.Admission.IssuedRead.final_accept_retains_birth_route_requirements_and_child,
      `PooFlowCoreProof.Admission.IssuedRead.raw_private_birth_rewrite_can_forge,
      `PooFlowCoreProof.Admission.IssuedRead.source_diagnosis_keeps_priority,
      `PooFlowCoreProof.Admission.IssuerProjection.projection_agrees_with_verifier,
      `PooFlowCoreProof.Admission.RouteMutation.equal_projection_same_decision,
      `PooFlowCoreProof.Admission.ReplayOwnership.selected_write_refused,
      `PooFlowCoreProof.Admission.ReplayOwnership.nested_frame_keeps_outer,
      `PooFlowCoreProof.Admission.ReplayOwnership.delivery_write_refused,
      `PooFlowCoreProof.Admission.ReplayOwnership.rejected_edit_has_no_partial_clear,
      `PooFlowCoreProof.Admission.ReplayOwnership.independent_edit_allowed,
      `PooFlowCoreProof.Admission.ReplayOwnership.unaffected_parent_unchanged,
      `PooFlowCoreProof.Admission.ReplayOwnership.exceptional_return_restores_outer,
      `PooFlowCoreProof.Admission.ReplayOwnership.exceptional_return_preserves_error,
      `PooFlowCoreProof.Admission.ReplayOwnership.raw_bypass_still_has_history,
      `PooFlowCoreProof.Admission.MetadataOwnership.unknown_refused,
      `PooFlowCoreProof.Admission.MetadataOwnership.associated_selected_refused,
      `PooFlowCoreProof.Admission.MetadataOwnership.nested_keeps_outer,
      `PooFlowCoreProof.Admission.MetadataOwnership.restored_raw_route_keeps_effect,
      `PooFlowCoreProof.Admission.MetadataAllocation.allocation_keeps_existing,
      `PooFlowCoreProof.Admission.MetadataAllocation.allocation_registers_receiver,
      `PooFlowCoreProof.Admission.MetadataAllocation.restoration_keeps_parent_and_revision,
      `PooFlowCoreProof.Admission.MetadataAllocation.restoration_retains_poisoned_cold_cache,
      `PooFlowCoreProof.Admission.MetadataAllocation.restoration_is_not_invalidation,
      `PooFlowCoreProof.Admission.StoreLowering.mediated_prewrite_refusal,
      `PooFlowCoreProof.Admission.StoreLowering.mediated_no_cold_poison,
      `PooFlowCoreProof.Admission.StoreLowering.unlowered_retains_counterexample,
      `PooFlowCoreProof.Admission.StoreLowering.precompiled_callees_refuse,
      `PooFlowCoreProof.Admission.StoreLowering.precompiled_callees_preserve_cold,
      `PooFlowCoreProof.Admission.StoreLowering.fixture_owners_derived,
      `PooFlowCoreProof.Admission.StoreLowering.direct_copies_are_required,
      `PooFlowCoreProof.Admission.StoreLowering.missing_carrier_retains_counterexample,
      `PooFlowCoreProof.Admission.ArtifactClosure.changed_closure_refuses,
      `PooFlowCoreProof.Admission.ArtifactClosure.raw_store_refuses,
      `PooFlowCoreProof.Admission.ArtifactClosure.stale_inputs_refuse,
      `PooFlowCoreProof.Admission.ArtifactClosure.prior_loading_refuses,
      `PooFlowCoreProof.Admission.ArtifactClosure.unchanged_mediated_admits,
      `PooFlowCoreProof.Admission.ArtifactClosure.both_requirements_preserved,
      `PooFlowCoreProof.Admission.IssuedLoading.changed_record_refuses,
      `PooFlowCoreProof.Admission.IssuedLoading.changed_artifact_refuses,
      `PooFlowCoreProof.Admission.IssuedLoading.changed_snapshot_refuses,
      `PooFlowCoreProof.Admission.IssuedLoading.allowed_checks_match,
      `PooFlowCoreProof.Admission.IssuedLoading.public_replace_preserves_consumed_bytes,
      `PooFlowCoreProof.Admission.IssuedLoading.latest_path_not_implied,
      `PooFlowCoreProof.Admission.IssuedLoading.private_writer_breaks_consumption,
      `PooFlowCoreProof.Admission.SourceLoader.changed_cache_refused,
      `PooFlowCoreProof.Admission.SourceLoader.stable_cache_allowed,
      `PooFlowCoreProof.Admission.SourceLoader.saved_edge_independent_of_rebinding,
      `PooFlowCoreProof.Admission.SourceLoader.both_requirements,
      `PooFlowCoreProof.Admission.SourceLoader.old_edge_counterexample,
      `PooFlowCoreProof.Admission.CoreStoreRecovery.valid_other_store_refused,
      `PooFlowCoreProof.Admission.CoreStoreRecovery.stable_restart,
      `PooFlowCoreProof.Admission.CoreStoreRecovery.joint_replacement_refused,
      `PooFlowCoreProof.Admission.CoreStoreRecovery.changed_source_refused,
      `PooFlowCoreProof.Admission.CoreStoreRecovery.nonregular_issuance_refused,
      `PooFlowCoreProof.Admission.CoreStoreRecovery.recovery_requires_registered_contents,
      `PooFlowCoreProof.Admission.CoreStoreRecovery.integrity_without_selection_counterexample,
      `PooFlowCoreProof.Admission.CoreApprovedRecovery.changed_approval_refused,
      `PooFlowCoreProof.Admission.CoreApprovedRecovery.noop_cannot_restore,
      `PooFlowCoreProof.Admission.CoreApprovedRecovery.coverage_requires_each_selected,
      `PooFlowCoreProof.Admission.CoreApprovedRecovery.omission_refused,
      `PooFlowCoreProof.Admission.CoreApprovedRecovery.replacement_refused,
      `PooFlowCoreProof.Admission.CoreApprovedRecovery.changed_source_refused,
      `PooFlowCoreProof.Admission.CoreApprovedRecovery.joint_replacement_refused,
      `PooFlowCoreProof.Admission.CoreApprovedRecovery.accepted_preserves_boundaries,
      `PooFlowCoreProof.Admission.CoreApprovedRecovery.restart_has_accepting_path,
      `PooFlowCoreProof.Admission.CoreApprovedRecovery.dropping_approval_is_unsound,
      `PooFlowCoreProof.Admission.CoreBuildHandoff.accept_requires_exact_projection,
      `PooFlowCoreProof.Admission.CoreBuildHandoff.joint_disk_replacement_refused,
      `PooFlowCoreProof.Admission.CoreBuildHandoff.warm_handoff,
      `PooFlowCoreProof.Admission.CoreBuildHandoff.final_and_both_requirements,
      `PooFlowCoreProof.Admission.CoreBuildHandoff.parent_receiver_isolation,
      `PooFlowCoreProof.Admission.CoreBuildPublication.joint_replacement_refused,
      `PooFlowCoreProof.Admission.CoreBuildPublication.publication_requires_final_check,
      `PooFlowCoreProof.Admission.CoreBuildPublication.both_requirements,
      `PooFlowCoreProof.Admission.CoreBuildPublication.native_cache_grants_no_authority,
      `PooFlowCoreProof.Admission.CoreBuildPublication.saved_entry_uses_same_check,
      `PooFlowCoreProof.Admission.CoreBuildPublication.first_build_cannot_adopt_cache,
      `PooFlowCoreProof.Admission.CoreBuildPublication.unchecked_adoption_counterexample,
      `PooFlowCoreProof.Admission.RouteMutation.raw_restore_keeps_observation,
      `PooFlowCoreProof.Admission.RouteMutation.raw_restore_keeps_generation,
      `PooFlowCoreProof.Admission.RouteMutation.raw_restore_retains_history,
      `PooFlowCoreProof.Admission.RouteMutation.restored_route_same_decision,
      `PooFlowCoreProof.Admission.RouteMutation.tracked_write_rejected,
      `PooFlowCoreProof.Admission.RouteMutation.restoring_route_cannot_restore_generation,
      `PooFlowCoreProof.Admission.RouteMutation.untracked_write_defeats_generation,
      `PooFlowCoreProof.Admission.RouteMutation.active_edit_refused_before_write,
      `PooFlowCoreProof.Admission.RouteMutation.accepted_keeps_both,
      `PooFlowCoreProof.Admission.IssuerProjection.empty_frontier,
      `PooFlowCoreProof.Admission.IssuerProjection.mint_preserves_frontier,
      `PooFlowCoreProof.Admission.IssuerProjection.raw_allocation_preserves_frontier,
      `PooFlowCoreProof.Admission.IssuerProjection.raw_allocation_has_no_authority,
      `PooFlowCoreProof.Admission.IssuerProjection.later_mint_does_not_sign_public_copy,
      `PooFlowCoreProof.Admission.IssuerProjection.native_mint_constructs_association,
      `PooFlowCoreProof.Admission.IssuerProjection.mint_projects_without_birth_premise,
      `PooFlowCoreProof.Admission.IssuerProjection.transient_cache_unchanged,
      `PooFlowCoreProof.Admission.IssuerProjection.raw_new_record_cannot_borrow_authority,
      `PooFlowCoreProof.Admission.IssuerProjection.mint_keeps_parent_authentication,
      `PooFlowCoreProof.Admission.IssuerProjection.replacement_rejected,
      `PooFlowCoreProof.Admission.IssuerProjection.restore_has_same_endpoint,
      `PooFlowCoreProof.Admission.IssuerProjection.restored_endpoint_can_have_effect,
      `PooFlowCoreProof.Admission.IssuerProjection.final_admission_keeps_both_requirements_and_child,
      `PooFlowCoreProof.Admission.IssuedRead.absent_private_association_rejects,
      `PooFlowCoreProof.Admission.IssuedRead.displaced_closure_rejects,
      `PooFlowCoreProof.Admission.IssuedRead.authentic_closure_still_checks_payload,
      `PooFlowCoreProof.Admission.ReturnTail.object_tail_counterexample,
      `PooFlowCoreProof.Admission.ReturnTail.retained_requirements,
      `PooFlowCoreProof.Admission.ReturnTail.earlier_file_counterexample,
      `PooFlowCoreProof.Admission.ReturnTail.closed_inspection_trace,
      `PooFlowCoreProof.Admission.ReturnTail.quiet_tail_preserves_replay,
      `PooFlowCoreProof.Admission.ReturnTail.late_source_failure_first,
      `PooFlowCoreProof.Admission.AdmissionBody.nested_window_current,
      `PooFlowCoreProof.Admission.AdmissionBody.member_current,
      `PooFlowCoreProof.Admission.AdmissionBody.changed_nested_read_rejected,
      `PooFlowCoreProof.Admission.AdmissionBody.accepted_preserves_all,
      `PooFlowCoreProof.Admission.AdmissionBody.changed_child_prevents_root_return,
      `PooFlowCoreProof.Admission.AdmissionBody.completed_body_source_first,
      `PooFlowCoreProof.Admission.AdmissionBody.nested_adapter_failure_preserved,
      `PooFlowCoreProof.Admission.AdmissionBody.diagnostic_schedule,
      `PooFlowCoreProof.Admission.CallPhases.cold_lookup_pushes,
      `PooFlowCoreProof.Admission.CallPhases.warm_lookup_adds_no_frame,
      `PooFlowCoreProof.Admission.CallPhases.body_restores_ambient,
      `PooFlowCoreProof.Admission.CallPhases.top_level_receiver_edit_allowed,
      `PooFlowCoreProof.Admission.CallPhases.nested_receiver_edit_vetoed,
      `PooFlowCoreProof.Admission.CallPhases.rejected_edit_not_certified,
      `PooFlowCoreProof.Admission.CallPhases.unrelated_demand_edit_allowed,
      `PooFlowCoreProof.Admission.CallPhases.lookup_only_misses_body_change,
      `PooFlowCoreProof.Admission.CallPhases.both_requirements_and_identity,
      `PooFlowCoreProof.Admission.CallPhases.diagnostic_schedule,
      `PooFlowCoreProof.Admission.SerialUse.cold_step_preserves_root,
      `PooFlowCoreProof.Admission.SerialUse.serial_cold_trace_preserves_root,
      `PooFlowCoreProof.Admission.SerialUse.cold_does_not_freeze_demand,
      `PooFlowCoreProof.Admission.SerialUse.cold_does_not_freeze_source,
      `PooFlowCoreProof.Admission.SerialUse.checks_keep_requirements,
      `PooFlowCoreProof.Admission.SerialUse.changed_version_refuses_commit,
      `PooFlowCoreProof.Admission.SerialUse.version_aba_refuses_commit,
      `PooFlowCoreProof.Admission.SerialUse.local_success_not_commit,
      `PooFlowCoreProof.Admission.SerialUse.preserves_diagnostic_schedule,
      `PooFlowCoreProof.Admission.SnapshotLifetime.selected_owner_once,
      `PooFlowCoreProof.Admission.SnapshotLifetime.outside_closure_unchanged,
      `PooFlowCoreProof.Admission.SnapshotLifetime.receiver_revision_not_dependency_certificate,
      `PooFlowCoreProof.Admission.SnapshotLifetime.diamond_not_multiple,
      `PooFlowCoreProof.Admission.SnapshotLifetime.supported_aba_leaves_revision,
      `PooFlowCoreProof.Admission.SnapshotLifetime.active_closure_veto,
      `PooFlowCoreProof.Admission.SnapshotLifetime.different_revision_rejected,
      `PooFlowCoreProof.Admission.SnapshotLifetime.value_aba_rejected,
      `PooFlowCoreProof.Admission.SnapshotLifetime.scope_aba_passes_endpoints,
      `PooFlowCoreProof.Admission.SnapshotLifetime.initial_check_does_not_fence,
      `PooFlowCoreProof.Admission.SnapshotLifetime.late_rejection_not_rollback,
      `PooFlowCoreProof.Admission.SnapshotLifetime.ordered_diagnostics_retained,
      `PooFlowCoreProof.Admission.Federation.attenuationCannotAmplify,
      `PooFlowCoreProof.Admission.Decision.revokedCannotBeAdmitted,
      `PooFlowCoreProof.ProfileComposition.Syntax.boundBodyPreserved,
      `PooFlowCoreProof.ModuleSystem.Graph.Cache.cacheReadEstablishesCurrentGraphClosure,
      `PooFlowCoreProof.Modules.Funflow.ConclusionRevision.revisionRetainsHistoricalEvidence,
      `PooFlowCoreProof.ProfileComposition.Prototype.profileRefinementsKeepFinalSelf,
      `PooFlowCoreProof.ProfileComposition.Revision.profileRevisionInvalidatesCachedResult,
      `PooFlowCoreProof.ModuleSystem.Schema.Contracts.accumulatedResultPreservesValues,
      `PooFlowCoreProof.ModuleSystem.Schema.Resolution.deniedAuthorizationCannotDisclose,
      `PooFlowCoreProof.ModuleSystem.Selection.Requirements.resolvedCapabilitiesHaveDeclaredOrigin,
      `PooFlowCoreProof.ModuleSystem.Workflow.cached_checks_remain_current,
      `PooFlowCoreProof.ModuleSystem.Workflow.Revision.revision_requires_discharge,
      `PooFlowCoreProof.ModuleSystem.Workflow.Revision.stale_cannot_be_certified,
      `PooFlowCoreProof.ModuleSystem.Schema.Association.Projection.accepted_receipt_discharged] do
    unless environment.contains required do
      throwError "Required Core integration theorem was not loaded: {required}"
  let mut count : Nat := 0
  for (name, info) in environment.constants.toList do
    if owners.any (·.isPrefixOf name) then
      count := count + 1
      -- A proposition parameter is legitimate; a record that invents its own
      -- admission propositions as fields is not a model of checked data.
      if let .inductInfo inductiveInfo := info then
        if let some structureInfo := getStructureInfo? environment name then
          for field in structureInfo.fieldInfo do
            let some projection := environment.find? field.projFn
              | throwError "Missing structure projection {field.projFn}"
            let mut resultType := projection.type
            for _ in [:inductiveInfo.numParams + 1] do
              if let .forallE _ _ body _ := resultType then
                resultType := body
              else throwError "Malformed structure projection {field.projFn}"
            if resultType == .sort .zero then
              throwError "{field.projFn} stores an arbitrary Prop; define a predicate on concrete inputs instead"
      for axiomName in (← collectAxioms name) do
        unless allowed.contains axiomName do
          throwError "{name} depends on disallowed axiom {axiomName}"
  if count = 0 then throwError "No Core declarations were audited"
  logInfo "CORE-MODEL-SHAPE-AUDIT-OK: no arbitrary Prop-valued fields"
  logInfo m!"CORE-AXIOM-AUDIT-OK: {count} declarations; standard Lean axioms only"
