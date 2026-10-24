// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
package YuanxuModuleLoading {
    private import ScalarValues::*;
    part def SourceCatalogue {
        attribute entryCount : Integer;
        doc /* Directory/package identity and inert SourceRefs. Discovery must
               not expand roles, run user macros or admit domain objects. */
    }
    part def SelectedDeclarations {
        attribute selectedCount : Integer;
        attribute sourceRevision : String;
        doc /* Native interface metadata: identity, requirements, feature
               decisions, role locations and source association. Dependency
               closure is not a list of linked business scopes. */
    }
    part def DemandedScope {
        attribute receiverIdentity : String;
        attribute sourceRevision : String;
        attribute featureDecision : String;
        attribute demandedCount : Integer;
        doc /* Native POO slots own role construction on actual access. Reuse
               requires exact receiver/source/feature/phase context. A parent
               cached scope is not a child's normalized configuration. */
    }
    part def NativeReadSupport {
        attribute originalRecordCount : Integer;
        attribute orderedEdgeCount : Integer;
        doc /* Once issued, every original dependency remains. No observer
               event, miss, second requirement or stale record is pruned. */
    }
    part def Admission {
        ref part scope : DemandedScope;
        ref part support : NativeReadSupport;
        doc /* Domain obligations, source association and plan identity must
               hold for the final receiver. No successful decision is cached
               across callbacks/effects; return-currentness remains fresh. */
    }
    part def Loading {
        part catalogue : SourceCatalogue;
        part declarations : SelectedDeclarations;
        part scope : DemandedScope;
        part admission : Admission;
        dependency sourceSelection from catalogue to declarations;
        dependency actualDemand from declarations to scope;
        dependency explicitAdmission from scope to admission;
    }
    requirement def NoEarlyRoleConstruction {
        attribute declarationOnly : Boolean;
        attribute roleConstructions : Integer;
        require constraint { not declarationOnly or roleConstructions == 0 }
        doc /* Proposed fast path only. A source/MOP-owned closed projection
               must establish this; an author's Boolean cannot authorize it.
               Unknown code/hooks take the existing full guarded path. */
    }
    requirement def SeparateCapacityWorkloads {
        attribute catalogueCount : Integer;
        attribute selectedCount : Integer;
        attribute demandedCount : Integer;
        require constraint { demandedCount <= selectedCount }
        require constraint { selectedCount <= catalogueCount }
        doc /* Keep the existing 10000-selected declaration gate at 2 GiB.
               Separately measure large catalogue/small selection and full
               business-scope activation. Never substitute one for another. */
    }
    requirement def BeforePublication {
        attribute published : Boolean;
        attribute finalReceiverAdmitted : Boolean;
        attribute sourcesCurrent : Boolean;
        attribute requiredModulesEnabled : Boolean;
        require constraint { not published or
          (finalReceiverAdmitted and sourcesCurrent and requiredModulesEnabled) }
    }
}
