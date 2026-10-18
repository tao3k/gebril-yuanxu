# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Check Core-owned finite Quint models and matched counterexample controls."""
from pathlib import Path
from contextlib import nullcontext
import argparse
import hashlib
import json
import os
import re
import selectors
import shutil
import signal
import subprocess
import tempfile
import time

CASES = [
    ('MetadataAllocation', 'safety', False),
    ('MetadataAllocation_raw', 'RestoredImpliesCoherent', True),
    ('MetadataAllocation_exports', 'HiddenExportsStopReflection', True),
    ('MetadataAllocation_lastOwner', 'SupportedPreWrite', True),
    ('MetadataAllocation_dropB', 'BothRequirements', True),
    ('MetadataAllocation_parent', 'ChildPlan', True),
    ('MetadataAllocation_eager', 'LazyBranch', True),
    ('MetadataAllocation_acceptance', 'RejectAll', True),
    ('MetadataOwnership', 'safety', False),
    ('MetadataOwnership_noGuard', 'GatewayPreWrite', True),
    ('MetadataOwnership_allowUnknown', 'UnknownRefused', True),
    ('MetadataOwnership_omitBackend', 'Coverage', True),
    ('MetadataOwnership_dropB', 'BothRequirements', True),
    ('MetadataOwnership_parent', 'ChildPlan', True),
    ('MetadataOwnership_eager', 'LazyBranch', True),
    ('MetadataOwnership_raw', 'NoRawCallbacks', True),
    ('MetadataOwnership_acceptance', 'RejectAll', True),
    ('ReplayOwnership', 'safety', False),
    ('ReplayOwnership_noGuard', 'PreWriteRefusal', True),
    ('ReplayOwnership_dropOuter', 'PreWriteRefusal', True),
    ('ReplayOwnership_partialClear', 'NoPartialClear', True),
    ('ReplayOwnership_leak', 'Released', True),
    ('ReplayOwnership_dropB', 'BothRequirements', True),
    ('ReplayOwnership_parent', 'ChildPlan', True),
    ('ReplayOwnership_eager', 'LazyBranch', True),
    ('ReplayOwnership_raw', 'NoRawCallbacks', True),
    ('ReplayOwnership_acceptance', 'RejectAll', True),
    ('RouteMutation', 'safety', False),
    ('RouteMutation_endpoint', 'NoRouteWritesAtReturn', True),
    ('RouteMutation_untracked', 'NoRouteWritesAtReturn', True),
    ('RouteMutation_dropB', 'BothRequirements', True),
    ('RouteMutation_parent', 'ChildPlan', True),
    ('RouteMutation_eager', 'LazyBranch', True),
    ('RouteMutation_acceptance', 'RejectAll', True),
    ('IssuerProjection', 'safety', False),
    ('IssuerProjection_noRegistry', 'AuthenticAtReturn', True),
    ('IssuerProjection_noPayload', 'AuthenticAtReturn', True),
    ('IssuerProjection_cacheMiss', 'MissNotCached', True),
    ('IssuerProjection_noRoute', 'NoForeignKernelCalls', True),
    ('IssuerProjection_skipFinal', 'EndpointCurrent', True),
    ('IssuerProjection_dropB', 'BothRequirements', True),
    ('IssuerProjection_parent', 'ChildPlan', True),
    ('IssuerProjection_eager', 'LazyBranch', True),
    ('IssuerProjection_history', 'NoCallbackEffects', True),
    ('IssuerProjection_acceptance', 'RejectAll', True),
    ('IssuedRead', 'safety', False),
    ('IssuedRead_noBirth', 'NoForgery', True),
    ('IssuedRead_rootOnly', 'WholeClosureBeforeObserve', True),
    ('IssuedRead_noRoute', 'NoForeignCheckerCalls', True),
    ('IssuedRead_skipFinal', 'FinalAuthenticity', True),
    ('IssuedRead_registerMiss', 'MissNotCached', True),
    ('IssuedRead_rawBirth', 'NoForgery', True),
    ('IssuedRead_dropB', 'TwoRequirements', True),
    ('IssuedRead_parent', 'FinalPlan', True),
    ('IssuedRead_acceptance', 'RejectAll', True),
    ('MetadataRoute', 'safety', False),
    ('MetadataRoute_refOnly', 'NoForeignCalls', True),
    ('MetadataRoute_readsOnly', 'NoForeignCalls', True),
    ('MetadataRoute_entryOnly', 'NoForeignCalls', True),
    ('MetadataRoute_endpoint', 'NoForeignCalls', True),
    ('MetadataRoute_issuance', 'Issuance', True),
    ('MetadataRoute_dropB', 'TwoRequirements', True),
    ('MetadataRoute_parent', 'FinalPlan', True),
    ('MetadataRoute_acceptance', 'RejectAll', True),
    ('CheckerOrigin', 'safety', False),
    ('CheckerOrigin_identityOnly', 'OwnedAtAdmission', True),
    ('CheckerOrigin_invokeAny', 'NoForeignCheckerCalls', True),
    ('CheckerOrigin_rootOnly', 'NoForeignCheckerCalls', True),
    ('CheckerOrigin_rawTable', 'AuthenticIssuance', True),
    ('CheckerOrigin_metadataHook', 'NoForeignCalls', True),
    ('CheckerOrigin_dropB', 'BothRequirements', True),
    ('CheckerOrigin_parent', 'FinalPlan', True),
    ('CheckerOrigin_acceptance', 'RejectAll', True),
    ("NativeSemanticQuery", "safety", False),
    ("GraphOperations_none", "safety", False),
    ("GraphOperations_reverseOrder", "OrderedPayload", True),
    ("GraphOperations_wrongTarget", "PathIdentity", True),
    ("GraphOperations_orphanDelete", "StructuralClosure", True),
    ("GraphOperations_replay", "OrderedPayload", True),
    ("GraphOperations_fixedPoint", "HonestReceipt", True),
    ("TestSourceAdmission", "safety", False),
    ("TestSourceAdmission_eager", "NoUnrelatedExpansion", True),
    ("TestSourceAdmission_stale", "CurrentEvidence", True),
    ("TestSourceAdmission_cleanup", "FailureCleanup", True),
    ("TestSourceAdmission_secondGraph", "SameGraphIdentity", True),
    ("SourceWindows", "safety", False),
    ("SourceWindows_cross", "CurrentEvidence", True),
    ("SourceWindows_omit", "CompleteRequirements", True),
    ("SourceWindows_receiver", "FinalReceiver", True),
    ("SourceWindows_repeat", "OncePerWindow", True),
    ("SourceWindows_eager", "LazyBranch", True),
    ("SourceWindows_skipfinal", "CurrentEvidence", True),
    ("SourceWindows_acceptance", "RejectAll", True),
    ("RootChild", "safety", False),
    ("RootChild_analyticAuthority", "FinalSources", True),
    ("RootChild_crossEffect", "FinalSources", True),
    ("RootChild_omit", "TwoRequirements", True),
    ("RootChild_skipchild", "DomainChecks", True),
    ("RootChild_omitSource", "FinalSources", True),
    ("RootChild_parent", "ReceiverIsolation", True),
    ("RootChild_eager", "LazyBranch", True),
    ("RootChild_lateEffect", "FinalSources", True),
    ("RootChild_acceptance", "RejectAll", True),
    ("ReturnWindows", "safety", False),
    ("ReturnWindows_pure", "safety", False),
    ("ReturnWindows_skipBefore", "CallbackEntry", True),
    ("ReturnWindows_crossContribution", "PostContribution", True),
    ("ReturnWindows_trustReturn", "FinalSources", True),
    ("ReturnWindows_crossReplay", "FinalSources", True),
    ("ReturnWindows_omitLate", "CompleteProjection", True),
    ("ReturnWindows_dropParty", "TwoRequirements", True),
    ("ReturnWindows_repeat", "PureBudget", True),
    ("ReturnWindows_acceptance", "RejectAll", True),
    ("ReplayBoundary", "safety", False),
    ("ReplayBoundary_move", "OrderedDiagnostic", True),
    ("ReplayBoundary_reuse", "SourcesCurrent", True),
    ("ReplayBoundary_omit", "CompleteCoverage", True),
    ("ReplayBoundary_effects", "NoEffects", True),
    ("ReplayBoundary_acceptance", "RejectAll", True),
    ("IdentityDFS", "safety", False),
    ("IdentityDFS_lateMark", "TerminationBound", True),
    ("IdentityDFS_payload", "CompleteCoverage", True),
    ("IdentityDFS_noFinal", "RecheckedCurrent", True),
    ("IdentityDFS_dropFinal", "FinalCoverage", True),
    ("IdentityDFS_finalWrite", "RecheckedCurrent", True),
    ("IdentityDFS_sourceReuse", "SourcesCurrent", True),
    ("IdentityDFS_parent", "ReceiverIdentity", True),
    ("IdentityDFS_acceptance", "RejectAll", True),
    ('ReadOnlyEntry', 'safety', False),
    ('ReadOnlyEntry_sealed', 'NoOpaque', True),
    ('ReadOnlyEntry_revision', 'NoOpaque', True),
    ('ReadOnlyEntry_checker', 'NoOpaque', True),
    ('ReadOnlyEntry_observer', 'NoOpaque', True),
    ('ReadOnlyEntry_anchorExecute', 'NoOpaque', True),
    ('ReadOnlyEntry_scopeReuse', 'NoOpaque', True),
    ('ReadOnlyEntry_dropPrefix', 'OrderedDiagnostic', True),
    ('ReadOnlyEntry_parent', 'ReceiverIdentity', True),
    ('ReadOnlyEntry_sourceReuse', 'SourcesCurrent', True),
    ('ReadOnlyEntry_acceptance', 'RejectAll', True),
    ('SnapshotEntry', 'safety', False),
    ('SnapshotEntry_revision', 'ChangedRejected', True),
    ('SnapshotEntry_checker', 'ChangedRejected', True),
    ('SnapshotEntry_value', 'ChangedRejected', True),
    ('SnapshotEntry_observer', 'ChangedRejected', True),
    ('SnapshotEntry_ancestor', 'ChangedRejected', True),
    ('SnapshotEntry_source', 'SourcesCurrent', True),
    ('SnapshotEntry_prefix', 'OrderedDiagnostic', True),
    ('SnapshotEntry_parent', 'ReceiverIdentity', True),
    ('SnapshotEntry_aba', 'NoInterveningCallback', True),
    ('SnapshotEntry_acceptance', 'RejectAll', True),
    ('ClosedTail', 'safety', False),
    ('ClosedTail_foreign', 'NoForeignCalls', True),
    ('ClosedTail_returnOnly', 'ObjectsCurrent', True),
    ('ClosedTail_dropB', 'TwoRequirements', True),
    ('ClosedTail_parent', 'ChildIdentity', True),
    ('ClosedTail_prefix', 'OrderedDiagnostic', True),
    ('ClosedTail_external', 'SourcesCurrent', True),
    ('ClosedTail_acceptance', 'RejectAll', True),
    ('ReturnTail', 'recordedChecks', False),
    ('ReturnTail_skipReplay', 'ReplayWasCurrent', True),
    ('ReturnTail_skipFile', 'FilesMatchedWhenRead', True),
    ('ReturnTail_dropB', 'RequirementsWereChecked', True),
    ('ReturnTail_parent', 'ChildIdentity', True),
    ('ReturnTail_prefix', 'DiagnosticOrder', True),
    ('ReturnTail_objects', 'ObjectsCurrentAtReturn', True),
    ('ReturnTail_sources', 'SourcesCurrentAtReturn', True),
    ('ReturnTail_plan', 'PlanMatchesAtReturn', True),
    ('ReturnTail_acceptance', 'RejectAll', True),
    ('AdmissionBody', 'safety', False),
    ('AdmissionBody_acquisitionOnly', 'ObservedCurrent', True),
    ('AdmissionBody_skipReplay', 'ObservedCurrent', True),
    ('AdmissionBody_trustHot', 'HotBodies', True),
    ('AdmissionBody_skipChild', 'ChildOwnReject', True),
    ('AdmissionBody_dropB', 'TwoRequirements', True),
    ('AdmissionBody_parent', 'ChildIdentity', True),
    ('AdmissionBody_prefix', 'DiagnosticOrder', True),
    ('AdmissionBody_noWrites', 'NoWritesBeforeReject', True),
    ('AdmissionBody_acceptance', 'RejectAll', True),
    ('CallPhases', 'safety', False),
    ('CallPhases_acceptVeto', 'FailedBodyRejected', True),
    ('CallPhases_lookupOnly', 'CurrentPlan', True),
    ('CallPhases_leak', 'MethodUnwound', True),
    ('CallPhases_dropCaller', 'NestedProtected', True),
    ('CallPhases_dropB', 'TwoRequirements', True),
    ('CallPhases_parent', 'ReceiverIdentity', True),
    ('CallPhases_prefix', 'OrderedDiagnostic', True),
    ('CallPhases_protected', 'NoBodyMutation', True),
    ('CallPhases_acceptance', 'RejectAll', True),
    ('SerialUse', 'safety', False),
    ('SerialUse_noGuard', 'ActiveProtected', True),
    ('SerialUse_omitDemand', 'ReadCurrent', True),
    ('SerialUse_dropB', 'TwoRequirements', True),
    ('SerialUse_parent', 'ReceiverIdentity', True),
    ('SerialUse_prefix', 'OrderedDiagnostic', True),
    ('SerialUse_localOnly', 'ConditionalCommit', True),
    ('SerialUse_coldAll', 'ColdFreezesAll', True),
    ('SerialUse_acceptance', 'RejectAll', True),
    ('SnapshotLifetime', 'safety', False),
    ('SnapshotLifetime_valueOnly', 'CurrentPlan', True),
    ('SnapshotLifetime_receiverOnly', 'CurrentPlan', True),
    ('SnapshotLifetime_crossEffect', 'SourcesCurrent', True),
    ('SnapshotLifetime_skipClosure', 'ActiveBlocked', True),
    ('SnapshotLifetime_duplicate', 'OncePerOwner', True),
    ('SnapshotLifetime_parent', 'ReceiverIdentity', True),
    ('SnapshotLifetime_dropRequirement', 'TwoRequirements', True),
    ('SnapshotLifetime_prefix', 'OrderedDiagnostic', True),
    ('SnapshotLifetime_history', 'EndpointMeansNoEffect', True),
    ('SnapshotLifetime_fenced', 'NoStaleUse', True),
    ('SnapshotLifetime_acceptance', 'RejectAll', True),
]
COUNTS = re.compile(rb"([\d,]+) states generated, ([\d,]+) distinct states.*?([\d,]+) states left on queue")


def run(command, cwd):
    started = last_output = time.monotonic()
    output = bytearray()
    with subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, start_new_session=True) as process:
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                while selector.get_map():
                    now = time.monotonic()
                    if now - started > 45 or now - last_output > 5:
                        raise TimeoutError("Quint exceeded 45s case or 5s real-output deadline")
                    for key, _ in selector.select(0.1):
                        chunk = os.read(key.fileobj.fileno(), 65536)
                        if chunk:
                            output.extend(chunk)
                            last_output = time.monotonic()
                            print(chunk.decode(errors="replace"), end="", flush=True)
                        else:
                            selector.unregister(key.fileobj)
            status = process.wait(timeout=1)
        except BaseException:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise
    return status, bytes(output)


def scheme(value):
    if isinstance(value, bool):
        return "#t" if value else "#f"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, dict):
        return "(" + " ".join("(" + key + " . " + scheme(item) + ")" for key, item in value.items()) + ")"
    if isinstance(value, list):
        return "(" + " ".join(map(scheme, value)) + ")"
    return str(value)


def quint_executable():
    local = Path(__file__).resolve().parent / "node_modules/.bin/quint"
    return os.environ.get("QUINT_BIN", str(local) if local.exists() else shutil.which("quint"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quint", default=quint_executable())
    parser.add_argument("--server-endpoint", default=os.environ.get("QUINT_SERVER_ENDPOINT"))
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--case-prefix", help="Qualify an explicitly scoped subset; default is the complete catalog")
    parser.add_argument("--typecheck-scope", choices=("all", "selected"), default="all",
                        help="Keep all-source checking by default; selected checks each named case and its native imports")
    args = parser.parse_args()
    selected_cases = [case for case in CASES if not args.case_prefix or case[0].startswith(args.case_prefix)]
    if not selected_cases:
        parser.error("case prefix selects no catalogued models")
    if args.typecheck_scope == "selected" and not args.case_prefix:
        parser.error("selected typechecking requires an explicit --case-prefix")
    args.receipt.unlink(missing_ok=True)
    version = subprocess.check_output([args.quint, "--version"], text=True, timeout=5).strip()
    if version != "0.33.0":
        raise SystemExit(f"expected Quint 0.33.0, got {version}")
    models = Path(__file__).resolve().parent
    core = models.parents[1]
    bound = (sorted(models.glob("*.qnt")) + sorted((core / "graph").glob("*.ss"))
             + sorted((core / "module-system/schema/support").glob("*.ss"))
             + [core / "t/graph-operations-test.ss", core / "module-system/source/projection.ss"])
    def digests():
        return {str(p.relative_to(core)): hashlib.sha256(p.read_bytes()).hexdigest() for p in bound}
    window_lean = core / "proofs/lean/PooFlowCoreProof/Admission/SourceWindows.lean"
    window_digest = "sha256:" + hashlib.sha256((models / "SourceWindows.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{window_digest}"' not in window_lean.read_text():
        raise AssertionError("Lean retains a stale SourceWindows Quint source binding")
    bound.extend([window_lean, core / "admission/source.ss",
                  core / "admission/contributions.ss", core / "module-system/source/admission.ss",
                  core / "proofs/lean/PooFlowCoreProof/Admission/Source.lean",
                  core / "proofs/lean/lakefile.lean", core / "proofs/lean/lake-manifest.json",
                  core / "proofs/lean/lean-toolchain", core / "gerbil.pkg",
                  core / "t/source-admission-test.ss", core / "t/source-observation-test.ss",
                  core / "t/slot-read-cost-test.ss"])
    root_child_lean = core / "proofs/lean/PooFlowCoreProof/Admission/RootChild.lean"
    root_child_digest = "sha256:" + hashlib.sha256((models / "RootChild.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{root_child_digest}"' not in root_child_lean.read_text():
        raise AssertionError("Lean retains a stale RootChild Quint source binding")
    bound.extend([root_child_lean, core / "types.ss", core / "admission/publication.ss"])
    return_lean = core / "proofs/lean/PooFlowCoreProof/Admission/ReturnWindows.lean"
    return_digest = "sha256:" + hashlib.sha256((models / "ReturnWindows.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{return_digest}"' not in return_lean.read_text():
        raise AssertionError("Lean retains a stale ReturnWindows Quint source binding")
    bound.extend([return_lean, core / "configuration/slot-origin.ss",
                  core / "t/root-child-admission-test.ss", core / "t/root-child-effect-test.ss"])
    replay_lean = core / "proofs/lean/PooFlowCoreProof/Admission/ReplayBoundary.lean"
    replay_digest = "sha256:" + hashlib.sha256((models / "ReplayBoundary.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{replay_digest}"' not in replay_lean.read_text():
        raise AssertionError("Lean retains a stale ReplayBoundary Quint source binding")
    bound.append(replay_lean)
    identity_lean = core / "proofs/lean/PooFlowCoreProof/Admission/IdentityDFS.lean"
    identity_digest = "sha256:" + hashlib.sha256((models / "IdentityDFS.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{identity_digest}"' not in identity_lean.read_text():
        raise AssertionError("Lean retains a stale IdentityDFS Quint source binding")
    bound.append(identity_lean)
    frames_lean = core / "proofs/lean/PooFlowCoreProof/Admission/DFSFrames.lean"
    if 'def quintSourceDigest : String := IdentityDFS.quintSourceDigest' not in frames_lean.read_text():
        raise AssertionError("DFSFrames must retain the IdentityDFS projection binding")
    bound.append(frames_lean)
    entry_lean = core / "proofs/lean/PooFlowCoreProof/Admission/ReadOnlyEntry.lean"
    entry_digest = "sha256:" + hashlib.sha256((models / "ReadOnlyEntry.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{entry_digest}"' not in entry_lean.read_text():
        raise AssertionError("Lean retains a stale ReadOnlyEntry Quint source binding")
    bound.append(entry_lean)
    snapshot_lean = core / "proofs/lean/PooFlowCoreProof/Admission/SnapshotEntry.lean"
    snapshot_digest = "sha256:" + hashlib.sha256((models / "SnapshotEntry.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{snapshot_digest}"' not in snapshot_lean.read_text():
        raise AssertionError("Lean retains a stale SnapshotEntry Quint source binding")
    bound.extend([snapshot_lean, core / "t/mop-state-snapshot-test.ss",
                  core / "t/qualification/mop-state/snapshot.ss"])
    closed_lean = core / "proofs/lean/PooFlowCoreProof/Admission/ClosedTail.lean"
    closed_digest = "sha256:" + hashlib.sha256((models / "ClosedTail.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{closed_digest}"' not in closed_lean.read_text():
        raise AssertionError("Lean retains a stale ClosedTail Quint source binding")
    bound.extend([closed_lean, core / "t/source-admission-closed-tail-test.ss",
                  core / "t/source-admission-gateway-test.ss",
                  core / "t/qualification/mop-state/closed-tail.ss",
                  core / "t/qualification/mop-state/compile-tail-gateway.ss",
                  core / "t/qualification/mop-state/refine-tail-policy.ss"])
    checker_lean = core / "proofs/lean/PooFlowCoreProof/Admission/CheckerOrigin.lean"
    checker_digest = "sha256:" + hashlib.sha256((models / "CheckerOrigin.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{checker_digest}"' not in checker_lean.read_text():
        raise AssertionError("Lean retains a stale CheckerOrigin Quint source binding")
    bound.extend([checker_lean, core / "t/mop-checker-origin-test.ss",
                  core / "t/qualification/mop-state/checker-origin.ss"])
    route_lean = core / "proofs/lean/PooFlowCoreProof/Admission/MetadataRoute.lean"
    route_digest = "sha256:" + hashlib.sha256((models / "MetadataRoute.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{route_digest}"' not in route_lean.read_text():
        raise AssertionError("Lean retains a stale MetadataRoute Quint source binding")
    bound.extend([route_lean, core / "t/mop-metadata-route-test.ss",
                  core / "t/qualification/mop-state/metadata-route.ss"])
    projection_lean = core / "proofs/lean/PooFlowCoreProof/Admission/IssuerProjection.lean"
    mutation_lean = core / "proofs/lean/PooFlowCoreProof/Admission/RouteMutation.lean"
    ownership_lean = core / "proofs/lean/PooFlowCoreProof/Admission/ReplayOwnership.lean"
    metadata_lean = core / "proofs/lean/PooFlowCoreProof/Admission/MetadataOwnership.lean"
    allocation_lean = core / "proofs/lean/PooFlowCoreProof/Admission/MetadataAllocation.lean"
    allocation_digest = "sha256:" + hashlib.sha256((models / "MetadataAllocation.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{allocation_digest}"' not in allocation_lean.read_text():
        raise AssertionError("Lean retains a stale MetadataAllocation Quint source binding")
    bound.extend([allocation_lean, core / "proofs/lean/MetadataAllocationCheck.lean",
                  core / "t/mop-metadata-allocation-test.ss",
                  core / "t/qualification/mop-state/reflection-surface.ss"])
    metadata_digest = "sha256:" + hashlib.sha256((models / "MetadataOwnership.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{metadata_digest}"' not in metadata_lean.read_text():
        raise AssertionError("Lean retains a stale MetadataOwnership Quint source binding")
    bound.extend([metadata_lean, core / "t/mop-metadata-ownership-test.ss",
                  core / "t/qualification/mop-state/metadata-ownership.ss"])
    ownership_digest = "sha256:" + hashlib.sha256((models / "ReplayOwnership.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{ownership_digest}"' not in ownership_lean.read_text():
        raise AssertionError("Lean retains a stale ReplayOwnership Quint source binding")
    bound.extend([ownership_lean, core / "t/mop-replay-write-guard-test.ss"])
    mutation_digest = "sha256:" + hashlib.sha256((models / "RouteMutation.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{mutation_digest}"' not in mutation_lean.read_text():
        raise AssertionError("Lean retains a stale RouteMutation Quint source binding")
    bound.extend([mutation_lean, core / "t/mop-route-mutation-test.ss"])
    projection_digest = "sha256:" + hashlib.sha256((models / "IssuerProjection.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{projection_digest}"' not in projection_lean.read_text():
        raise AssertionError("Lean retains a stale IssuerProjection Quint source binding")
    bound.extend([projection_lean, core / "proofs/lean/IssuerProjectionCheck.lean",
                  core / "t/issuer-projection-test.ss"])
    issued_lean = core / "proofs/lean/PooFlowCoreProof/Admission/IssuedRead.lean"
    issued_digest = "sha256:" + hashlib.sha256((models / "IssuedRead.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{issued_digest}"' not in issued_lean.read_text():
        raise AssertionError("Lean retains a stale IssuedRead Quint source binding")
    bound.extend([issued_lean, core / "t/issued-read-admission-test.ss"])
    tail_lean = core / "proofs/lean/PooFlowCoreProof/Admission/ReturnTail.lean"
    tail_digest = "sha256:" + hashlib.sha256((models / "ReturnTail.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{tail_digest}"' not in tail_lean.read_text():
        raise AssertionError("Lean retains a stale ReturnTail Quint source binding")
    bound.extend([tail_lean, core / "t/source-admission-tail-test.ss"])
    body_lean = core / "proofs/lean/PooFlowCoreProof/Admission/AdmissionBody.lean"
    body_digest = "sha256:" + hashlib.sha256((models / "AdmissionBody.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{body_digest}"' not in body_lean.read_text():
        raise AssertionError("Lean retains a stale AdmissionBody Quint source binding")
    bound.extend([body_lean, core / "t/source-admission-body-test.ss"])
    call_lean = core / "proofs/lean/PooFlowCoreProof/Admission/CallPhases.lean"
    call_digest = "sha256:" + hashlib.sha256((models / "CallPhases.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{call_digest}"' not in call_lean.read_text():
        raise AssertionError("Lean retains a stale CallPhases Quint source binding")
    bound.extend([call_lean, core / "t/mop-call-phases-test.ss"])
    serial_lean = core / "proofs/lean/PooFlowCoreProof/Admission/SerialUse.lean"
    serial_digest = "sha256:" + hashlib.sha256((models / "SerialUse.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{serial_digest}"' not in serial_lean.read_text():
        raise AssertionError("Lean retains a stale SerialUse Quint source binding")
    bound.extend([serial_lean, core / "t/mop-serial-use-test.ss"])
    lifetime_lean = core / "proofs/lean/PooFlowCoreProof/Admission/SnapshotLifetime.lean"
    lifetime_digest = "sha256:" + hashlib.sha256((models / "SnapshotLifetime.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{lifetime_digest}"' not in lifetime_lean.read_text():
        raise AssertionError("Lean retains a stale SnapshotLifetime Quint source binding")
    bound.extend([lifetime_lean, core / "t/mop-snapshot-lifetime-test.ss"])
    sources = digests()
    lean = core / "proofs/lean/PooFlowCoreProof/Graph/Operations.lean"
    digest = "sha256:" + hashlib.sha256((models / "GraphOperations.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{digest}"' not in lean.read_text():
        raise AssertionError("Lean retains a stale GraphOperations Quint source binding")
    bound.append(lean)
    admission_lean = core / "proofs/lean/PooFlowCoreProof/ModuleSystem/Graph/TestAdmission.lean"
    admission_digest = "sha256:" + hashlib.sha256((models / "TestSourceAdmission.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{admission_digest}"' not in " ".join(admission_lean.read_text().split()):
        raise AssertionError("Lean retains a stale TestSourceAdmission Quint source binding")
    bound.extend([admission_lean, core / "module-system/building/test-projection.ss",
                  core / "module-system/building/interface.ss",
                  core / "t/module-testing-source-admission-test.ss",
                  core / "module-system/source/reader.ss",
                  core / "module-system/source/link.ss",
                  core / "module-system/source/publication.ss",
                  core / "module-system/building/configuration-source.ss",
                  core / "module-system/authoring/admission.ss",
                  core / "poo-clos/method-bundle-syntax.ss",
                  core / "poo-clos/syntax.ss",
                  core / "t/poo-clos-method-bundle-test.ss",
                  core / "t/module-scope-link-test.ss",
                  core / "modules/opentofu/build.ss",
                  core / "module-system/building/source-closure.ss",
                  core / "proofs/lean/PooFlowCoreProof/ModuleSystem/Graph/ImportCorrespondence.lean",
                  core / "ops/func.ss", core / "ops/process-script.ss",
                  core / "ops/tests/atomic-test.ss", core / "t/module-publication-test.ss"])
    bound.extend([Path(__file__).resolve(), Path(__file__).with_name("backend.py").resolve()])
    sources = digests()
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    # Input identities are not a passing qualification receipt. Retain them even
    # if a concurrently edited owner makes the final source-cut gate fail.
    args.receipt.with_suffix(".inputs.json").write_text(json.dumps({
        "status": "unqualified-input-cut", "sources-sha256": sources}, indent=2) + "\n")
    typecheck_sources = (sorted(models.glob("*.qnt")) if args.typecheck_scope == "all" else
                         [models / (model + ".qnt") for model, _, _ in selected_cases])
    # Quint itself resolves and typechecks transitive imports for each entry;
    # do not implement another parser or substitute a prior successful decision.
    for source in typecheck_sources:
        subprocess.run([args.quint, "typecheck", str(source)], check=True, timeout=5)
    print("QUINT-TYPECHECK-OK", flush=True)
    print(f"QUINT-TYPECHECK-SCOPE {args.typecheck_scope} {len(typecheck_sources)} entries (including native imports)", flush=True)
    results = []
    if __package__:
        from .backend import backend_session
    else:
        from backend import backend_session
    session = (nullcontext(args.server_endpoint) if args.server_endpoint else
               backend_session(lambda chunk: print(chunk.decode(errors="replace"), end="", flush=True)))
    with tempfile.TemporaryDirectory(prefix="core-quint-") as directory, session as endpoint:
        work = Path(directory)
        for source in models.glob("*.qnt"):
            shutil.copyfile(source, work / source.name)
        config = work / "backend.json"
        config.write_text('{"workers":"1","maxHeap":"-Xmx1G"}\n')
        for model, invariant, negative in selected_cases:
            print(f"QUINT-CHECK {model} {invariant}", flush=True)
            status, output = run([args.quint, "verify", str(work / (model + ".qnt")),
                "--main", model, "--backend", "tlc", "--apalache-version", "0.62.1",
                "--invariant", invariant, "--tlc-config", str(config), "--verbosity", "3"] +
                ["--server-endpoint", endpoint], work)
            counts = COUNTS.search(output)
            accepted = ((status == 1 and b"Error: Invariant q_inv is violated." in output
                         and b"[violation] Found an issue" in output
                         and b"error: found a counterexample" in output) if negative else
                        (status == 0 and b"[ok] No violation found" in output and counts is not None
                         and counts[3].replace(b",", b"") == b"0"))
            if not accepted or counts is None:
                raise AssertionError(f"unexpected verifier result: {model}/{invariant}, exit={status}")
            results.append({"model": model, "invariant": invariant, "negative": negative,
                "exit": status, "generated-states": int(counts[1].replace(b",", b"")),
                "distinct-states": int(counts[2].replace(b",", b"")),
                "output-sha256": hashlib.sha256(output).hexdigest()})
            print(f"QUINT-OK {model}", flush=True)
    current_sources = digests()
    if sources != current_sources:
        changed = {name: {"before": digest, "after": current_sources.get(name)}
                   for name, digest in sources.items() if current_sources.get(name) != digest}
        args.receipt.with_suffix(".drift.json").write_text(
            json.dumps({"status": "rejected-source-cut", "changed": changed}, indent=2) + "\n")
        raise AssertionError("bound sources changed during qualification: " + ", ".join(changed))
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(scheme({"schema": "poo-flow.quint-proof.v1", "quint-version": version,
        "backend": "tlc", "apalache-version": "0.62.1", "sources-sha256": sources,
        "case-prefix": args.case_prefix or "all", "catalogue-size": len(CASES),
        "typecheck-scope": args.typecheck_scope,
        "typecheck-entries": [source.stem for source in typecheck_sources],
        "cases": results}) + "\n")
    print(f"QUINT-QUALIFICATION-OK {len(results)} cases", flush=True)


if __name__ == "__main__":
    main()
