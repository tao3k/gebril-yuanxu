;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: graph facts are POO-native control-plane values.
;;; Invariant: graph objects describe topology; they never schedule or run it.

(import (only-in :clan/poo/object .ref .slot?)
        (only-in :yuanxu/module-system/schema/slot-contracts
                 yuanxu-contract-slot
                 yuanxu-contract-value-type
                 yuanxu-object-contract
                 yuanxu-object-contract->alist))

(import :yuanxu/graph/types-core)

(export #t)

(def YuanxuGraphIdType
  (yuanxu-contract-value-type
   'YuanxuGraphId yuanxu-graph-id? 'YuanxuGraphId))
(def YuanxuGraphAnyType
  (yuanxu-contract-value-type 'Object (lambda (_value) #t) 'Object))
(def YuanxuGraphMetadataType
  (yuanxu-contract-value-type
   'YuanxuGraphMetadata yuanxu-graph-metadata? 'Alist))

(def YuanxuGraphNodeIdSlot
  (yuanxu-contract-slot
   'graph.node/id 'id YuanxuGraphIdType #t
   '((scope . graph) (slot . id))))
(def YuanxuGraphNodePayloadSlot
  (yuanxu-contract-slot
   'graph.node/payload 'payload YuanxuGraphAnyType #f
   '((scope . graph) (slot . payload) (optional . #t))))
(def YuanxuGraphNodeMetadataSlot
  (yuanxu-contract-slot
   'graph.node/metadata 'metadata YuanxuGraphMetadataType #t
   '((scope . graph) (slot . metadata))))
(def YuanxuGraphNodeSlots
  (list YuanxuGraphNodeIdSlot
        YuanxuGraphNodePayloadSlot
        YuanxuGraphNodeMetadataSlot))
(def YuanxuGraphNodeContract
  (yuanxu-object-contract
   'graph/node 'graph 'YuanxuGraphNode yuanxu-graph-node?
   YuanxuGraphNodeSlots
   '((scope . graph) (projection . graph-node))))

(def (yuanxu-graph-node-type-contract->alist)
  (yuanxu-object-contract->alist YuanxuGraphNodeContract))

(def YuanxuGraphSymbolType
  (yuanxu-contract-value-type 'Symbol symbol? 'Symbol))
(def YuanxuGraphEdgeFromSlot
  (yuanxu-contract-slot
   'graph.edge/from 'from YuanxuGraphIdType #t
   '((scope . graph) (slot . from))))
(def YuanxuGraphEdgeToSlot
  (yuanxu-contract-slot
   'graph.edge/to 'to YuanxuGraphIdType #t
   '((scope . graph) (slot . to))))
(def YuanxuGraphEdgeKindSlot
  (yuanxu-contract-slot
   'graph.edge/edge-kind 'edge-kind YuanxuGraphSymbolType #t
   '((scope . graph) (slot . edge-kind))))
(def YuanxuGraphEdgeMetadataSlot
  (yuanxu-contract-slot
   'graph.edge/metadata 'metadata YuanxuGraphMetadataType #t
   '((scope . graph) (slot . metadata))))
(def YuanxuGraphEdgeSlots
  (list YuanxuGraphEdgeFromSlot
        YuanxuGraphEdgeToSlot
        YuanxuGraphEdgeKindSlot
        YuanxuGraphEdgeMetadataSlot))
(def YuanxuGraphEdgeContract
  (yuanxu-object-contract
   'graph/edge 'graph 'YuanxuGraphEdge yuanxu-graph-edge?
   YuanxuGraphEdgeSlots
   '((scope . graph) (projection . graph-edge))))

(def (yuanxu-graph-edge-type-contract->alist)
  (yuanxu-object-contract->alist YuanxuGraphEdgeContract))

(def YuanxuGraphNodeListType
  (yuanxu-contract-value-type
   '[YuanxuGraphNode] yuanxu-graph-node-list? '[YuanxuGraphNode]))
(def YuanxuGraphEdgeListType
  (yuanxu-contract-value-type
   '[YuanxuGraphEdge] yuanxu-graph-edge-list? '[YuanxuGraphEdge]))
(def YuanxuGraphIdSlot
  (yuanxu-contract-slot
   'graph/graph-id 'graph-id YuanxuGraphIdType #t
   '((scope . graph) (slot . graph-id))))
(def YuanxuGraphNodesSlot
  (yuanxu-contract-slot
   'graph/nodes 'nodes YuanxuGraphNodeListType #t
   '((scope . graph) (slot . nodes))))
(def YuanxuGraphEdgesSlot
  (yuanxu-contract-slot
   'graph/edges 'edges YuanxuGraphEdgeListType #t
   '((scope . graph) (slot . edges))))
(def YuanxuGraphMetadataSlot
  (yuanxu-contract-slot
   'graph/metadata 'metadata YuanxuGraphMetadataType #t
   '((scope . graph) (slot . metadata))))
(def YuanxuGraphSlots
  (list YuanxuGraphIdSlot
        YuanxuGraphNodesSlot
        YuanxuGraphEdgesSlot
        YuanxuGraphMetadataSlot))
(def YuanxuGraphContract
  (yuanxu-object-contract
   'graph 'graph 'YuanxuGraph yuanxu-graph?
   YuanxuGraphSlots
   '((scope . graph) (projection . graph))))

(def (yuanxu-graph-type-contract->alist)
  (yuanxu-object-contract->alist YuanxuGraphContract))

(def YuanxuGraphNumberType
  (yuanxu-contract-value-type 'Number number? 'Number))
(def YuanxuGraphIdListType
  (yuanxu-contract-value-type
   '[YuanxuGraphId] yuanxu-graph-analysis-id-list? '[YuanxuGraphId]))
(def YuanxuGraphMaybeListType
  (yuanxu-contract-value-type
   'MaybeList yuanxu-graph-analysis-maybe-list? 'MaybeList))

;; : (-> YuanxuGraphContractKey Symbol YuanxuContractValueType YuanxuSlotContract)
(def (yuanxu-graph-analysis-slot key slot value-type)
  (yuanxu-contract-slot
   key slot value-type #t
   (map cons '(scope slot) (list 'graph slot))))

(def YuanxuGraphAnalysisSlots
  (list
   (yuanxu-graph-analysis-slot
    'graph.analysis/graph-id 'graph-id YuanxuGraphIdType)
   (yuanxu-graph-analysis-slot
    'graph.analysis/node-count 'node-count YuanxuGraphNumberType)
   (yuanxu-graph-analysis-slot
    'graph.analysis/edge-count 'edge-count YuanxuGraphNumberType)
   (yuanxu-graph-analysis-slot
    'graph.analysis/root-ids 'root-ids YuanxuGraphIdListType)
   (yuanxu-graph-analysis-slot
    'graph.analysis/terminal-ids 'terminal-ids YuanxuGraphIdListType)
   (yuanxu-graph-analysis-slot
    'graph.analysis/reachable-ids 'reachable-ids YuanxuGraphIdListType)
   (yuanxu-graph-analysis-slot
    'graph.analysis/dependency-cone 'dependency-cone YuanxuGraphIdListType)
   (yuanxu-graph-analysis-slot
    'graph.analysis/topological-order 'topological-order YuanxuGraphMaybeListType)
   (yuanxu-graph-analysis-slot
    'graph.analysis/cycle-path 'cycle-path YuanxuGraphMaybeListType)
   (yuanxu-graph-analysis-slot
    'graph.analysis/diagnostics 'diagnostics YuanxuGraphMetadataType)
   (yuanxu-graph-analysis-slot
    'graph.analysis/metadata 'metadata YuanxuGraphMetadataType)))
(def YuanxuGraphAnalysisContract
  (yuanxu-object-contract
   'graph/analysis 'graph 'YuanxuGraphAnalysis yuanxu-graph-analysis?
   YuanxuGraphAnalysisSlots
   '((scope . graph) (projection . graph-analysis))))

(def (yuanxu-graph-analysis-type-contract->alist)
  (yuanxu-object-contract->alist YuanxuGraphAnalysisContract))

(def YuanxuGraphComponentListType
  (yuanxu-contract-value-type
   '[[YuanxuGraphId]] list? '[[YuanxuGraphId]]))
(def YuanxuGraphCondensationEdgeListType
  (yuanxu-contract-value-type
   '[[Number Number]] list? '[[Number Number]]))

;; : (-> YuanxuGraphContractKey Symbol YuanxuContractValueType YuanxuSlotContract)
(def (yuanxu-graph-loop-analysis-slot key slot value-type)
  (yuanxu-contract-slot
   key slot value-type #t
   (map cons '(scope slot) (list 'graph slot))))

(def YuanxuGraphLoopAnalysisSlots
  (list
   (yuanxu-graph-loop-analysis-slot
    'graph.loop-analysis/graph-id 'graph-id YuanxuGraphIdType)
   (yuanxu-graph-loop-analysis-slot
    'graph.loop-analysis/component-count 'component-count YuanxuGraphNumberType)
   (yuanxu-graph-loop-analysis-slot
    'graph.loop-analysis/cyclic-component-count
    'cyclic-component-count
    YuanxuGraphNumberType)
   (yuanxu-graph-loop-analysis-slot
    'graph.loop-analysis/components 'components YuanxuGraphComponentListType)
   (yuanxu-graph-loop-analysis-slot
    'graph.loop-analysis/cyclic-components
    'cyclic-components
    YuanxuGraphComponentListType)
   (yuanxu-graph-loop-analysis-slot
    'graph.loop-analysis/condensation-edges
    'condensation-edges
    YuanxuGraphCondensationEdgeListType)
   (yuanxu-graph-loop-analysis-slot
    'graph.loop-analysis/diagnostics 'diagnostics YuanxuGraphMetadataType)
   (yuanxu-graph-loop-analysis-slot
    'graph.loop-analysis/metadata 'metadata YuanxuGraphMetadataType)))
(def YuanxuGraphLoopAnalysisContract
  (yuanxu-object-contract
   'graph/loop-analysis 'graph 'YuanxuGraphLoopAnalysis
   yuanxu-graph-loop-analysis?
   YuanxuGraphLoopAnalysisSlots
   '((scope . graph) (projection . graph-loop-analysis))))

(def (yuanxu-graph-loop-analysis-type-contract->alist)
  (yuanxu-object-contract->alist YuanxuGraphLoopAnalysisContract))
