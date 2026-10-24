;;; Design blocks 2-5 extracted verbatim from module 26. Test scope only.
(def (selection-obligations pipeline context)
  (if (and (.slot? pipeline 'selected-checks)
           (let ((names (.get pipeline selected-checks)))
             (and (list? names)
                  (every symbol? names)
                  (= (length names)
                     (length (delete-duplicates/hash names table: (make-hash-table-eq)))))))
    '()
    (list (.o kind: 'invalid-selected-checks))))

(def PipelineSelectionContract
  (yuanxu-predicate-contract
    'funflow/pipeline-selection object? selection-obligations))

;; Only fixed roles here; do not enumerate optional Check values.
(.def (ProfileShapeContract @ YuanxuObjectContract.)
  identity: 'funflow/profile-shape
  proto: Root
  responsibilities: (.o pipeline: PipelineSelectionContract)
  .obligations: empty-obligations)

;; This descriptor retains native proto checking and final identity obligations.
(.def (SelectedChecksContract @ YuanxuObjectContract.)
  identity: 'funflow/profile-selected
  proto: Root
  responsibilities: (.o)
  .obligations: final-obligations)

;; Maintained once upstream, not repeated in user declarations.
(.def ProfileAdmissionPolicy
  shape: ProfileShapeContract
  selected: SelectedChecksContract
  check-contracts: (.o)              ; optional stricter per-name Contracts
  default-check-contract: CheckPolicyContract
  reserved-slots: '(pipeline responsibilities .admit .type))

(def (selection-name-errors policy names)
  (let ((protected
         (append (.get policy reserved-slots)
                 (.all-slots (.get policy shape responsibilities))
                 (.all-slots (.get policy selected responsibilities)))))
    (foldr
      (lambda (name failures)
        (if (memq name protected)
          (cons (.o kind: 'reserved-check-name name: name) failures)
          failures))
      '() names)))

(def (project-selected-contract policy names)
  (let* ((template (.get policy selected))
         (overrides (.get policy check-contracts))
         (selected-map
          (object<-alist
            (map
              (lambda (name)
                (cons name
                  (if (.slot? overrides name)
                    (.ref overrides name)
                    (.get policy default-check-contract))))
              names))))
    (.cc template 'responsibilities
      (.+ (.get template responsibilities) selected-map))))

(def (covers-responsibilities? descriptor candidate context evidence)
  (and
    (receipt-ok? descriptor candidate context evidence)
    (.slot? evidence 'responsibility-evidence)
    (let* ((contracts (.get descriptor responsibilities))
           (required (.all-slots contracts))
           (entries (.get evidence responsibility-evidence))
           (actual (map (lambda (entry) (.get entry responsibility)) entries)))
      (and
        (= (length required) (length actual))
        (= (length actual) (length (delete-duplicates/hash actual table: (make-hash-table-eq))))
        (every (lambda (name) (memq name required)) actual)
        (every
          (lambda (entry)
            (let ((name (.get entry responsibility)))
              (and (.slot? candidate name)
                   (receipt-ok? (.ref contracts name) (.ref candidate name)
                                context entry))))
          entries)))))

(def (selection-refusal descriptor candidate context failures)
  (yuanxu-validation-evidence
    (.get descriptor identity) candidate
    (yuanxu-type-classify descriptor candidate context)
    failures #f failures context))

(def (admit-selected-profile policy candidate context)
  (let* ((_stage (report 'stage 'shape-start))
         (shape (.get policy shape))
         (shape-evidence (yuanxu-contract-admit shape candidate context)))
    (report 'stage 'shape-returned)
    (if (not (covers-responsibilities? shape candidate context shape-evidence))
      (selection-refusal shape candidate context
        (list (.o kind: 'profile-prerequisite-refused evidence: shape-evidence)))
      (let* ((_stage (report 'stage 'shape-covered))
             (names (.get candidate pipeline selected-checks))
             (errors (selection-name-errors policy names)))
        (report 'stage 'names-checked)
        (if (pair? errors)
          (selection-refusal (.get policy selected) candidate context errors)
          (let* ((descriptor (project-selected-contract policy names))
                 (_stage (report 'stage 'projection-made))
                 (evidence
                  (yuanxu-contract-admit descriptor candidate context)))
            (report 'stage 'children-returned)
            (if (covers-responsibilities? descriptor candidate context evidence)
              (.cc evidence
                'prerequisite-evidence (list shape-evidence)
                'effective-contract descriptor
                'required-checks names)
              (selection-refusal descriptor candidate context
                (list (.o kind: 'selected-responsibility-refused
                          evidence: evidence))))))))))
