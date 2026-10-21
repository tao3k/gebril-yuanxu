;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: graph facts are POO-native control-plane values.
;;; Invariant: graph objects describe topology; they never schedule or run it.

(import (only-in :clan/poo/object
                 .all-slots .cc .o .ref .slot? object? object<-alist)
        :yuanxu/utilities/final-projection-syntax)

(export #t)

;; : Symbol
(def +yuanxu-graph-node-prototype-kind+
  'yuanxu.graph.node.prototype)

;; : Symbol
(def +yuanxu-graph-edge-prototype-kind+
  'yuanxu.graph.edge.prototype)

;; : Symbol
(def +yuanxu-graph-prototype-kind+
  'yuanxu.graph.prototype)

;; : Symbol
(def +yuanxu-graph-analysis-prototype-kind+
  'yuanxu.graph.analysis.prototype)

;; : Symbol
(def +yuanxu-graph-loop-analysis-prototype-kind+
  'yuanxu.graph.loop-analysis.prototype)

(def (yuanxu-graph-alist? value)
  (and (list? value)
       (andmap pair? value)))

(def (yuanxu-graph-list-of? predicate values)
  (and (list? values)
       (andmap predicate values)))

;; : YuanxuGraphNodePrototype
(def graph-node
  (object<-alist
   (list
    (cons 'kind +yuanxu-graph-node-prototype-kind+)
    (cons 'schema 'yuanxu.graph.node.v1)
    (cons 'id #f)
    (cons 'payload #f)
    (cons 'metadata '())
    (cons 'runtime-executed #f))))

;; : YuanxuGraphEdgePrototype
(def graph-edge
  (object<-alist
   (list
    (cons 'kind +yuanxu-graph-edge-prototype-kind+)
    (cons 'schema 'yuanxu.graph.edge.v1)
    (cons 'from #f)
    (cons 'to #f)
    (cons 'edge-kind 'dependency)
    (cons 'metadata '())
    (cons 'runtime-executed #f))))

;; : YuanxuGraphPrototype
(def (yuanxu-graph-declaration-values declarations)
  (yuanxu-graph-require
   "graph declarations must be a POO object"
   (object? declarations)
   declarations)
  (map (lambda (slot) (.ref declarations slot))
       (.all-slots declarations)))

;; Noun-valued declaration slots carry named Graph values. Native slot algebra
;; owns replacement and refinement; `nodes` and `edges` are lazy projections
;; for the existing algorithm boundary.
(def graph
  (.o
      kind: +yuanxu-graph-prototype-kind+
      schema: 'yuanxu.graph.v1
      graph-id: #f
      (node-declarations ? (.o))
      (edge-declarations ? (.o))
      nodes: (yuanxu-graph-declaration-values node-declarations)
      edges: (yuanxu-graph-declaration-values edge-declarations)
      metadata: '()
      runtime-executed: #f))

;; : YuanxuGraphAnalysisPrototype
(def graph-analysis
  (object<-alist
   (list
    (cons 'kind +yuanxu-graph-analysis-prototype-kind+)
    (cons 'schema 'yuanxu.graph.analysis.v1)
    (cons 'graph-id #f)
    (cons 'node-count 0)
    (cons 'edge-count 0)
    (cons 'root-ids '())
    (cons 'terminal-ids '())
    (cons 'reachable-ids '())
    (cons 'dependency-cone '())
    (cons 'topological-order #f)
    (cons 'cycle-path #f)
    (cons 'acyclic? #t)
    (cons 'diagnostics '())
    (cons 'metadata '())
    (cons 'runtime-executed #f))))

;; : YuanxuGraphLoopAnalysisPrototype
(def graph-loop-analysis
  (object<-alist
   (list
    (cons 'kind +yuanxu-graph-loop-analysis-prototype-kind+)
    (cons 'schema 'yuanxu.graph.loop-analysis.v1)
    (cons 'graph-id #f)
    (cons 'component-count 0)
    (cons 'cyclic-component-count 0)
    (cons 'components '())
    (cons 'cyclic-components '())
    (cons 'condensation-edges '())
    (cons 'diagnostics '())
    (cons 'metadata '())
    (cons 'runtime-executed #f))))

;; : (-> Object Boolean)
(def (yuanxu-graph-id? value)
  (or (symbol? value)
      (string? value)
      (number? value)
      (pair? value)))

;; : (-> String Boolean Object Object)
(def (yuanxu-graph-require message ok? value)
  (if ok?
    value
    (error message value)))

;; : (-> (-> Object Boolean) List Boolean)
(def (yuanxu-graph-every? predicate values)
  (cond
   ((null? values) #t)
   ((predicate (car values))
    (yuanxu-graph-every? predicate (cdr values)))
   (else #f)))

;; : (-> Object Boolean)
(def (yuanxu-graph-metadata? value)
  (yuanxu-graph-alist? value))

;; : (-> Object [Object] [Alist] YuanxuGraphNode)
(def (yuanxu-graph-node id . maybe-payload+metadata)
  (yuanxu-graph-require "graph node id must be a stable id"
                          (yuanxu-graph-id? id)
                          id)
  (let* ((payload (if (null? maybe-payload+metadata)
                    #f
                    (car maybe-payload+metadata)))
         (metadata (if (or (null? maybe-payload+metadata)
                           (null? (cdr maybe-payload+metadata)))
                     '()
                     (cadr maybe-payload+metadata))))
    (object<-alist
     (list
      (cons 'kind +yuanxu-graph-node-prototype-kind+)
      (cons 'schema 'yuanxu.graph.node.v1)
      (cons 'id id)
      (cons 'payload payload)
      (cons 'metadata metadata)
      (cons 'runtime-executed #f)))))

;; : (-> Object Boolean)
(def (yuanxu-graph-node? value)
  (and (object? value)
       (.slot? value 'kind)
       (eq? (.ref value 'kind)
            +yuanxu-graph-node-prototype-kind+)))

;; : (-> Object Boolean)
(def (yuanxu-graph-node-list? value)
  (yuanxu-graph-list-of? yuanxu-graph-node? value))

;; : (-> YuanxuGraphNode Object)
(def (yuanxu-graph-node-id node)
  (.ref node 'id))

;; : (-> YuanxuGraphNode Object)
(def (yuanxu-graph-node-payload node)
  (.ref node 'payload))

;; : (-> YuanxuGraphNode [Alist])
(def (yuanxu-graph-node-metadata node)
  (.ref node 'metadata))

;; : (-> YuanxuGraphNode Alist)
(defpoo-final-projection
  yuanxu-graph-node->alist (node)
  (bindings ((checked-node
              (yuanxu-graph-require
               "graph node projection requires a graph node"
               (yuanxu-graph-node? node)
               node))))
  (fields ((kind (.ref checked-node 'kind))
           (schema (.ref checked-node 'schema))
           (id (.ref checked-node 'id))
           (payload (.ref checked-node 'payload))
           (metadata (.ref checked-node 'metadata))
           (runtime-executed (.ref checked-node 'runtime-executed)))))

;; : (-> [YuanxuGraphNode] [Alist])
(defpoo-final-projection-batch
  yuanxu-graph-nodes->alists (nodes)
  (projector yuanxu-graph-node->alist)
  (error-message "graph node projection requires a list"))

;; : (-> Object Object Symbol [Alist] YuanxuGraphEdge)
(def (yuanxu-graph-edge from to . maybe-kind+metadata)
  (yuanxu-graph-require "graph edge from must be a stable id"
                          (yuanxu-graph-id? from)
                          from)
  (yuanxu-graph-require "graph edge to must be a stable id"
                          (yuanxu-graph-id? to)
                          to)
  (let* ((edge-kind (if (null? maybe-kind+metadata)
                     'dependency
                     (car maybe-kind+metadata)))
         (metadata (if (or (null? maybe-kind+metadata)
                           (null? (cdr maybe-kind+metadata)))
                     '()
                     (cadr maybe-kind+metadata))))
    (yuanxu-graph-require "graph edge kind must be a symbol"
                            (symbol? edge-kind)
                            edge-kind)
    (object<-alist
     (list
      (cons 'kind +yuanxu-graph-edge-prototype-kind+)
      (cons 'schema 'yuanxu.graph.edge.v1)
      (cons 'from from)
      (cons 'to to)
      (cons 'edge-kind edge-kind)
      (cons 'metadata metadata)
      (cons 'runtime-executed #f)))))

;; : (-> Object Boolean)
(def (yuanxu-graph-edge? value)
  (and (object? value)
       (.slot? value 'kind)
       (eq? (.ref value 'kind)
            +yuanxu-graph-edge-prototype-kind+)))

;; : (-> Object Boolean)
(def (yuanxu-graph-edge-list? value)
  (yuanxu-graph-list-of? yuanxu-graph-edge? value))

;; : (-> YuanxuGraphEdge Object)
(def (yuanxu-graph-edge-from edge)
  (.ref edge 'from))

;; : (-> YuanxuGraphEdge Object)
(def (yuanxu-graph-edge-to edge)
  (.ref edge 'to))

;; : (-> YuanxuGraphEdge Symbol)
(def (yuanxu-graph-edge-kind edge)
  (.ref edge 'edge-kind))

;; : (-> YuanxuGraphEdge [Alist])
(def (yuanxu-graph-edge-metadata edge)
  (.ref edge 'metadata))

;; : (-> YuanxuGraphEdge Alist)
(defpoo-final-projection
  yuanxu-graph-edge->alist (edge)
  (bindings ((checked-edge
              (yuanxu-graph-require
               "graph edge projection requires a graph edge"
               (yuanxu-graph-edge? edge)
               edge))))
  (fields ((kind (.ref checked-edge 'kind))
           (schema (.ref checked-edge 'schema))
           (from (.ref checked-edge 'from))
           (to (.ref checked-edge 'to))
           (edge-kind (.ref checked-edge 'edge-kind))
           (metadata (.ref checked-edge 'metadata))
           (runtime-executed (.ref checked-edge 'runtime-executed)))))

;; : (-> [YuanxuGraphEdge] [Alist])
(defpoo-final-projection-batch
  yuanxu-graph-edges->alists (edges)
  (projector yuanxu-graph-edge->alist)
  (error-message "graph edge projection requires a list"))

;; : (-> Object [YuanxuGraphNode] [YuanxuGraphEdge] [Alist] YuanxuGraph)
(def (yuanxu-graph graph-id nodes edges . maybe-metadata)
  (yuanxu-graph-require "graph id must be a stable id"
                          (yuanxu-graph-id? graph-id)
                          graph-id)
  (yuanxu-graph-require "graph nodes must be graph nodes"
                          (yuanxu-graph-every? yuanxu-graph-node?
                                                 nodes)
                          nodes)
  (yuanxu-graph-require "graph edges must be graph edges"
                          (yuanxu-graph-every? yuanxu-graph-edge?
                                                 edges)
                          edges)
  (.cc graph
       graph-id: graph-id
       nodes: nodes
       edges: edges
       metadata: (if (null? maybe-metadata)
                   '()
                   (car maybe-metadata))))

;; : (-> Object Boolean)
(def (yuanxu-graph? value)
  (and (object? value)
       (.slot? value 'kind)
       (eq? (.ref value 'kind)
            +yuanxu-graph-prototype-kind+)))

;; : (-> YuanxuGraph Object)
(def (yuanxu-graph-id graph-value)
  (.ref graph-value 'graph-id))

;; : (-> YuanxuGraph [YuanxuGraphNode])
(def (yuanxu-graph-nodes graph-value)
  (.ref graph-value 'nodes))

;; : (-> YuanxuGraph [YuanxuGraphEdge])
(def (yuanxu-graph-edges graph-value)
  (.ref graph-value 'edges))

;; : (-> YuanxuGraph [Alist])
(def (yuanxu-graph-metadata graph-value)
  (.ref graph-value 'metadata))

;; : (-> YuanxuGraph Alist)
(defpoo-final-projection
  yuanxu-graph->alist (graph-value)
  (bindings ((checked-graph
              (yuanxu-graph-require
               "graph projection requires a graph"
               (yuanxu-graph? graph-value)
               graph-value))))
  (fields ((kind (.ref checked-graph 'kind))
           (schema (.ref checked-graph 'schema))
           (graph-id (.ref checked-graph 'graph-id))
           (nodes
            (yuanxu-graph-nodes->alists (.ref checked-graph 'nodes)))
           (edges
            (yuanxu-graph-edges->alists (.ref checked-graph 'edges)))
           (metadata (.ref checked-graph 'metadata))
           (runtime-executed (.ref checked-graph 'runtime-executed)))))

;; : (-> Object Nat Nat [Object] [Object] [Object] [Object] MaybeList MaybeList [Alist] [Alist] YuanxuGraphAnalysis)
(def (yuanxu-graph-analysis graph-id
                              node-count
                              edge-count
                              root-ids
                              terminal-ids
                              reachable-ids
                              dependency-cone
                              topological-order
                              cycle-path
                              diagnostics
                              . maybe-metadata)
  (yuanxu-graph-require "graph analysis id must be a stable id"
                          (yuanxu-graph-id? graph-id)
                          graph-id)
  (object<-alist
   (list
    (cons 'kind +yuanxu-graph-analysis-prototype-kind+)
    (cons 'schema 'yuanxu.graph.analysis.v1)
    (cons 'graph-id graph-id)
    (cons 'node-count node-count)
    (cons 'edge-count edge-count)
    (cons 'root-ids root-ids)
    (cons 'terminal-ids terminal-ids)
    (cons 'reachable-ids reachable-ids)
    (cons 'dependency-cone dependency-cone)
    (cons 'topological-order topological-order)
    (cons 'cycle-path cycle-path)
    (cons 'acyclic? (not cycle-path))
    (cons 'diagnostics diagnostics)
    (cons 'metadata (if (null? maybe-metadata)
                      '()
                      (car maybe-metadata)))
    (cons 'runtime-executed #f))))

;; : (-> Object Boolean)
(def (yuanxu-graph-analysis? value)
  (and (object? value)
       (.slot? value 'kind)
       (eq? (.ref value 'kind)
            +yuanxu-graph-analysis-prototype-kind+)))

;; : (-> Object [[Object]] [[Object]] [[Number Number]] [Alist]
;;       [Alist] YuanxuGraphLoopAnalysis)
(def (yuanxu-graph-loop-analysis
      graph-id components cyclic-components condensation-edges diagnostics
      . maybe-metadata)
  (yuanxu-graph-require
   "graph loop analysis id must be a stable id"
   (yuanxu-graph-id? graph-id)
   graph-id)
  (yuanxu-graph-require
   "graph loop analysis components must be a list"
   (list? components)
   components)
  (yuanxu-graph-require
   "graph loop analysis cyclic components must be a list"
   (list? cyclic-components)
   cyclic-components)
  (yuanxu-graph-require
   "graph loop analysis condensation edges must be a list"
   (list? condensation-edges)
   condensation-edges)
  (object<-alist
   (list
    (cons 'kind +yuanxu-graph-loop-analysis-prototype-kind+)
    (cons 'schema 'yuanxu.graph.loop-analysis.v1)
    (cons 'graph-id graph-id)
    (cons 'component-count (length components))
    (cons 'cyclic-component-count (length cyclic-components))
    (cons 'components components)
    (cons 'cyclic-components cyclic-components)
    (cons 'condensation-edges condensation-edges)
    (cons 'diagnostics diagnostics)
    (cons 'metadata (if (null? maybe-metadata) '() (car maybe-metadata)))
    (cons 'runtime-executed #f))))

;; : (-> Object Boolean)
(def (yuanxu-graph-loop-analysis? value)
  (and (object? value)
       (.slot? value 'kind)
       (eq? (.ref value 'kind)
            +yuanxu-graph-loop-analysis-prototype-kind+)))

;; : (-> YuanxuGraphLoopAnalysis Alist)
(defpoo-final-projection yuanxu-graph-loop-analysis->alist
  (analysis)
  (bindings
   ((checked-analysis
     (yuanxu-graph-require
      "graph loop analysis projection requires graph loop analysis"
      (yuanxu-graph-loop-analysis? analysis)
      analysis))))
  (fields
   ((kind (.ref checked-analysis 'kind))
    (schema (.ref checked-analysis 'schema))
    (graph-id (.ref checked-analysis 'graph-id))
    (component-count (.ref checked-analysis 'component-count))
    (cyclic-component-count
     (.ref checked-analysis 'cyclic-component-count))
    (components (.ref checked-analysis 'components))
    (cyclic-components (.ref checked-analysis 'cyclic-components))
    (condensation-edges (.ref checked-analysis 'condensation-edges))
    (diagnostics (.ref checked-analysis 'diagnostics))
    (metadata (.ref checked-analysis 'metadata))
    (runtime-executed (.ref checked-analysis 'runtime-executed)))))

;; : (-> Object Boolean)
(def (yuanxu-graph-analysis-id-list? value)
  (list? value))

;; : (-> Object Boolean)
(def (yuanxu-graph-analysis-maybe-list? value)
  (or (not value)
      (list? value)))

;; : (-> YuanxuGraphAnalysis Alist)
(defpoo-final-projection
  yuanxu-graph-analysis->alist (analysis)
  (bindings ((checked-analysis
              (yuanxu-graph-require
               "graph analysis projection requires graph analysis"
               (yuanxu-graph-analysis? analysis)
               analysis))))
  (fields ((kind (.ref checked-analysis 'kind))
           (schema (.ref checked-analysis 'schema))
           (graph-id (.ref checked-analysis 'graph-id))
           (node-count (.ref checked-analysis 'node-count))
           (edge-count (.ref checked-analysis 'edge-count))
           (root-ids (.ref checked-analysis 'root-ids))
           (terminal-ids (.ref checked-analysis 'terminal-ids))
           (reachable-ids (.ref checked-analysis 'reachable-ids))
           (dependency-cone (.ref checked-analysis 'dependency-cone))
           (topological-order (.ref checked-analysis 'topological-order))
           (cycle-path (.ref checked-analysis 'cycle-path))
           (acyclic? (.ref checked-analysis 'acyclic?))
           (diagnostics (.ref checked-analysis 'diagnostics))
           (metadata (.ref checked-analysis 'metadata))
           (runtime-executed (.ref checked-analysis 'runtime-executed)))))
