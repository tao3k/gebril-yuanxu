-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.Modules.Funflow.Continuation

namespace PooFlowCoreProof.PooClos.Runtime

inductive RuntimeControlRole where
  | captureLocalContinuation
  | continuableSignal
  | noncontinuableSignal
  | catcherTransfer
  | dynamicExtentProtection
  | diagnosticCapture
  deriving DecidableEq, Repr

inductive ControlOutcome where
  | continueAfterSignal
  | transferToBoundary
  | diagnosticEvidenceOnly
  deriving DecidableEq, Repr

def ExpectedOutcome : RuntimeControlRole → ControlOutcome
  | .continuableSignal => .continueAfterSignal
  | .noncontinuableSignal => .transferToBoundary
  | .catcherTransfer => .transferToBoundary
  | .diagnosticCapture => .diagnosticEvidenceOnly
  | .captureLocalContinuation => .continueAfterSignal
  | .dynamicExtentProtection => .continueAfterSignal

structure ContinuableSignalCorrespondence where
  returningHandlerContinuesAfterSignal : Prop
  continuationEstablished : returningHandlerContinuesAfterSignal
  grantsResumptionAuthority : Prop
  handlerReturnGrantsNoAuthority : ¬ grantsResumptionAuthority

structure NoncontinuableSignalCorrespondence where
  resumesOriginalSignalPoint : Prop
  noSignalPointResumption : ¬ resumesOriginalSignalPoint
  transfersToTerminalBoundary : Prop
  terminalTransferEstablished : transfersToTerminalBoundary

structure CatcherCorrespondence where
  resumesInPlace : Prop
  noInPlaceResumption : ¬ resumesInPlace
  transfersToCatcherBoundary : Prop
  catcherTransferEstablished : transfersToCatcherBoundary
  actsAsPortableSafePoint : Prop
  catcherIsNotPortableSafePoint : ¬ actsAsPortableSafePoint

structure RawContinuationFence where
  processLocal : Prop
  processLocalEstablished : processLocal
  oneShotAuthority : Prop
  oneShotEstablished : oneShotAuthority
  crossThreadAllowed : Prop
  noCrossThreadInvocation : ¬ crossThreadAllowed
  crossProcessAllowed : Prop
  noCrossProcessInvocation : ¬ crossProcessAllowed
  staleRootAllowed : Prop
  noStaleRootInvocation : ¬ staleRootAllowed
  repeatedInvocationAllowed : Prop
  noRepeatedInvocation : ¬ repeatedInvocationAllowed

structure DynamicWindDiscipline where
  beforeAfterMayRepeat : Prop
  repetitionAcknowledged : beforeAfterMayRepeat
  winderActionsIdempotentOrPure : Prop
  safeWindersEstablished : winderActionsIdempotentOrPure
  commitsExternalDomainEffect : Prop
  noExternalEffectCommit : ¬ commitsExternalDomainEffect
  evidenceEmissionIdempotent : Prop
  evidenceIdempotenceEstablished : evidenceEmissionIdempotent
  cleanupControlsCapabilityConsumption : Prop
  consumptionIndependentOfCleanup : ¬ cleanupControlsCapabilityConsumption

structure HandlerReentryDiscipline where
  returnsValidatedDecision : Prop
  abortsNoncontinuably : Prop
  delegatesToOuterHandler : Prop
  usesReentryFence : Prop
  explicitExitPath :
    returnsValidatedDecision ∨
      abortsNoncontinuably ∨
      delegatesToOuterHandler ∨
      usesReentryFence
  synthesizesProfileValue : Prop
  noProfileValueSynthesis : ¬ synthesizesProfileValue

structure DiagnosticSeparation where
  stackTraceIsEvidence : Prop
  evidenceEstablished : stackTraceIsEvidence
  stackTraceIsResumptionCapability : Prop
  notResumptionCapability : ¬ stackTraceIsResumptionCapability
  diagnosticContinuationInvoked : Prop
  neverInvokedAsControl : ¬ diagnosticContinuationInvoked
  admittedAsProfileOperand : Prop
  notProfileOperand : ¬ admittedAsProfileOperand

structure PublicRuntimeBoundary where
  exposesRawContinuation : Prop
  noRawContinuationExposure : ¬ exposesRawContinuation
  exposesHandlerInstallationClause : Prop
  noHandlerClauseExposure : ¬ exposesHandlerInstallationClause
  exposesCatcherToken : Prop
  noCatcherTokenExposure : ¬ exposesCatcherToken
  exposesRawRecordOrAlistProtocol : Prop
  noRawProtocol : ¬ exposesRawRecordOrAlistProtocol
  mirrorsGambitSyntaxAsMacroDsl : Prop
  noRuntimeMirrorDsl : ¬ mirrorsGambitSyntaxAsMacroDsl
  pooNativeObjectsOnly : Prop
  pooNativeBoundaryEstablished : pooNativeObjectsOnly

structure RuntimeProbeClosure where
  versionsRecorded : Prop
  importsResolved : Prop
  continuableTraceVerified : Prop
  noncontinuableTraceVerified : Prop
  catcherTraceVerified : Prop
  dynamicExtentVerified : Prop
  capabilityFencesVerified : Prop
  diagnosticSeparationVerified : Prop
  conservativeExtensionVerified : Prop

def ImplementationAdmitted (probes : RuntimeProbeClosure) : Prop :=
  probes.versionsRecorded ∧
    probes.importsResolved ∧
    probes.continuableTraceVerified ∧
    probes.noncontinuableTraceVerified ∧
    probes.catcherTraceVerified ∧
    probes.dynamicExtentVerified ∧
    probes.capabilityFencesVerified ∧
    probes.diagnosticSeparationVerified ∧
    probes.conservativeExtensionVerified

theorem continuableRaiseReturnsAfterSignal :
    ExpectedOutcome .continuableSignal = .continueAfterSignal := by
  rfl

theorem abortTransfersToBoundary :
    ExpectedOutcome .noncontinuableSignal = .transferToBoundary := by
  rfl

theorem catcherTransfersToBoundary :
    ExpectedOutcome .catcherTransfer = .transferToBoundary := by
  rfl

theorem stackTraceProducesEvidenceOnly :
    ExpectedOutcome .diagnosticCapture = .diagnosticEvidenceOnly := by
  rfl

theorem catcherIsNotPortableSafePoint
    (correspondence : CatcherCorrespondence) :
    ¬ correspondence.actsAsPortableSafePoint :=
  correspondence.catcherIsNotPortableSafePoint

theorem stackTraceIsEvidenceOnly
    (diagnostic : DiagnosticSeparation) :
    diagnostic.stackTraceIsEvidence ∧
      ¬ diagnostic.stackTraceIsResumptionCapability ∧
      ¬ diagnostic.diagnosticContinuationInvoked ∧
      ¬ diagnostic.admittedAsProfileOperand :=
  ⟨diagnostic.evidenceEstablished, diagnostic.notResumptionCapability,
    diagnostic.neverInvokedAsControl, diagnostic.notProfileOperand⟩

theorem missingVersionsBlocksImplementation
    (probes : RuntimeProbeClosure)
    (missing : ¬ probes.versionsRecorded) :
    ¬ ImplementationAdmitted probes := by
  intro admitted
  exact missing admitted.1

theorem missingImportsBlocksImplementation
    (probes : RuntimeProbeClosure)
    (missing : ¬ probes.importsResolved) :
    ¬ ImplementationAdmitted probes := by
  intro admitted
  exact missing admitted.2.1

theorem missingContinuableTraceBlocksImplementation
    (probes : RuntimeProbeClosure)
    (missing : ¬ probes.continuableTraceVerified) :
    ¬ ImplementationAdmitted probes := by
  intro admitted
  exact missing admitted.2.2.1

theorem missingDynamicExtentProbeBlocksImplementation
    (probes : RuntimeProbeClosure)
    (missing : ¬ probes.dynamicExtentVerified) :
    ¬ ImplementationAdmitted probes := by
  intro admitted
  exact missing admitted.2.2.2.2.2.1

theorem missingCapabilityFenceProbeBlocksImplementation
    (probes : RuntimeProbeClosure)
    (missing : ¬ probes.capabilityFencesVerified) :
    ¬ ImplementationAdmitted probes := by
  intro admitted
  exact missing admitted.2.2.2.2.2.2.1

theorem missingDiagnosticSeparationBlocksImplementation
    (probes : RuntimeProbeClosure)
    (missing : ¬ probes.diagnosticSeparationVerified) :
    ¬ ImplementationAdmitted probes := by
  intro admitted
  exact missing admitted.2.2.2.2.2.2.2.1

theorem missingConservativeExtensionBlocksImplementation
    (probes : RuntimeProbeClosure)
    (missing : ¬ probes.conservativeExtensionVerified) :
    ¬ ImplementationAdmitted probes := by
  intro admitted
  exact missing admitted.2.2.2.2.2.2.2.2

end PooFlowCoreProof.PooClos.Runtime
