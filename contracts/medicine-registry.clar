;; MediChain Medicine Registry Contract
;; This contract manages the registration and authentication of medicine batches
;; Ensures traceability and authenticity in the medical supply chain

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-invalid-batch (err u103))
(define-constant err-medicine-expired (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-invalid-participant (err u106))
(define-constant err-invalid-expiry (err u107))

;; Data structures
(define-map medicines
    { batch-id: (string-ascii 64) }
    {
        medicine-name: (string-ascii 128),
        manufacturer: principal,
        manufacturer-name: (string-ascii 128),
        quantity: uint,
        manufacturing-date: uint,
        expiry-date: uint,
        status: (string-ascii 32),
        current-owner: principal,
        registration-block: uint,
        is-authentic: bool
    }
)

(define-map authorized-manufacturers
    { manufacturer: principal }
    {
        name: (string-ascii 128),
        license-number: (string-ascii 64),
        registration-date: uint,
        is-active: bool
    }
)

(define-map medicine-batches-count
    { manufacturer: principal }
    { count: uint }
)

(define-map expired-medicines
    { batch-id: (string-ascii 64) }
    {
        expiry-block: uint,
        marked-by: principal,
        removal-date: uint
    }
)

(define-map quality-control-records
    { batch-id: (string-ascii 64) }
    {
        inspector: principal,
        inspection-date: uint,
        quality-score: uint,
        certification-status: (string-ascii 32),
        notes: (string-ascii 256)
    }
)

;; Data variables
(define-data-var total-medicines-registered uint u0)
(define-data-var total-manufacturers uint u0)
(define-data-var contract-active bool true)

;; Public functions

;; Register a new authorized manufacturer
(define-public (register-manufacturer (manufacturer principal) (name (string-ascii 128)) (license-number (string-ascii 64)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-none (map-get? authorized-manufacturers { manufacturer: manufacturer })) err-already-exists)
        (asserts! (> (len name) u0) err-invalid-participant)
        (asserts! (> (len license-number) u0) err-invalid-participant)
        
        (map-set authorized-manufacturers
            { manufacturer: manufacturer }
            {
                name: name,
                license-number: license-number,
                registration-date: stacks-block-height,
                is-active: true
            }
        )
        
        (var-set total-manufacturers (+ (var-get total-manufacturers) u1))
        (ok true)
    )
)

;; Register a new medicine batch
(define-public (register-medicine 
    (batch-id (string-ascii 64))
    (medicine-name (string-ascii 128))
    (manufacturer-name (string-ascii 128))
    (quantity uint)
    (expiry-date uint)
)
    (let
        (
            (manufacturer-info (unwrap! (map-get? authorized-manufacturers { manufacturer: tx-sender }) err-unauthorized))
            (current-block stacks-block-height)
        )
        
        ;; Validation checks
        (asserts! (get is-active manufacturer-info) err-unauthorized)
        (asserts! (is-none (map-get? medicines { batch-id: batch-id })) err-already-exists)
        (asserts! (> (len batch-id) u0) err-invalid-batch)
        (asserts! (> (len medicine-name) u0) err-invalid-batch)
        (asserts! (> quantity u0) err-invalid-batch)
        (asserts! (> expiry-date current-block) err-invalid-expiry)
        (asserts! (var-get contract-active) err-unauthorized)
        
        ;; Register the medicine
        (map-set medicines
            { batch-id: batch-id }
            {
                medicine-name: medicine-name,
                manufacturer: tx-sender,
                manufacturer-name: manufacturer-name,
                quantity: quantity,
                manufacturing-date: current-block,
                expiry-date: expiry-date,
                status: "active",
                current-owner: tx-sender,
                registration-block: current-block,
                is-authentic: true
            }
        )
        
        ;; Update counters
        (let
            (
                (current-count (default-to u0 (get count (map-get? medicine-batches-count { manufacturer: tx-sender }))))
            )
            (map-set medicine-batches-count
                { manufacturer: tx-sender }
                { count: (+ current-count u1) }
            )
        )
        
        (var-set total-medicines-registered (+ (var-get total-medicines-registered) u1))
        (ok batch-id)
    )
)

;; Verify medicine authenticity
(define-public (verify-authenticity (batch-id (string-ascii 64)))
    (let
        (
            (medicine-info (unwrap! (map-get? medicines { batch-id: batch-id }) err-not-found))
            (current-block stacks-block-height)
        )
        
        (asserts! (get is-authentic medicine-info) (err u108)) ;; Not authentic
        (asserts! (< current-block (get expiry-date medicine-info)) err-medicine-expired)
        (asserts! (is-eq (get status medicine-info) "active") (err u109)) ;; Not active
        
        (ok {
            is-authentic: true,
            medicine-name: (get medicine-name medicine-info),
            manufacturer: (get manufacturer medicine-info),
            expiry-date: (get expiry-date medicine-info),
            current-owner: (get current-owner medicine-info)
        })
    )
)

;; Mark medicine as expired
(define-public (mark-as-expired (batch-id (string-ascii 64)))
    (let
        (
            (medicine-info (unwrap! (map-get? medicines { batch-id: batch-id }) err-not-found))
            (current-block stacks-block-height)
        )
        
        ;; Only owner or contract owner can mark as expired
        (asserts! (or (is-eq tx-sender (get current-owner medicine-info)) 
                     (is-eq tx-sender contract-owner)) err-unauthorized)
        
        ;; Update medicine status
        (map-set medicines
            { batch-id: batch-id }
            (merge medicine-info { status: "expired" })
        )
        
        ;; Record expiry information
        (map-set expired-medicines
            { batch-id: batch-id }
            {
                expiry-block: current-block,
                marked-by: tx-sender,
                removal-date: current-block
            }
        )
        
        (ok true)
    )
)

;; Update medicine ownership (for supply chain transfers)
(define-public (update-ownership (batch-id (string-ascii 64)) (new-owner principal))
    (let
        (
            (medicine-info (unwrap! (map-get? medicines { batch-id: batch-id }) err-not-found))
        )
        
        ;; Only current owner can transfer
        (asserts! (is-eq tx-sender (get current-owner medicine-info)) err-unauthorized)
        (asserts! (is-eq (get status medicine-info) "active") (err u109))
        
        ;; Update ownership
        (map-set medicines
            { batch-id: batch-id }
            (merge medicine-info { current-owner: new-owner })
        )
        
        (ok true)
    )
)

;; Add quality control record
(define-public (add-quality-control-record 
    (batch-id (string-ascii 64))
    (quality-score uint)
    (certification-status (string-ascii 32))
    (notes (string-ascii 256))
)
    (let
        (
            (medicine-info (unwrap! (map-get? medicines { batch-id: batch-id }) err-not-found))
            (manufacturer-info (unwrap! (map-get? authorized-manufacturers { manufacturer: tx-sender }) err-unauthorized))
        )
        
        ;; Only authorized manufacturers can add QC records
        (asserts! (get is-active manufacturer-info) err-unauthorized)
        (asserts! (<= quality-score u100) (err u110)) ;; Invalid quality score
        
        (map-set quality-control-records
            { batch-id: batch-id }
            {
                inspector: tx-sender,
                inspection-date: stacks-block-height,
                quality-score: quality-score,
                certification-status: certification-status,
                notes: notes
            }
        )
        
        (ok true)
    )
)

;; Deactivate manufacturer (emergency function)
(define-public (deactivate-manufacturer (manufacturer principal))
    (let
        (
            (manufacturer-info (unwrap! (map-get? authorized-manufacturers { manufacturer: manufacturer }) err-not-found))
        )
        
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (map-set authorized-manufacturers
            { manufacturer: manufacturer }
            (merge manufacturer-info { is-active: false })
        )
        
        (ok true)
    )
)

;; Emergency contract pause
(define-public (pause-contract)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set contract-active false)
        (ok true)
    )
)

;; Resume contract
(define-public (resume-contract)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set contract-active true)
        (ok true)
    )
)

;; Read-only functions

;; Get medicine information
(define-read-only (get-medicine-info (batch-id (string-ascii 64)))
    (map-get? medicines { batch-id: batch-id })
)

;; Get manufacturer information
(define-read-only (get-manufacturer-info (manufacturer principal))
    (map-get? authorized-manufacturers { manufacturer: manufacturer })
)

;; Get quality control record
(define-read-only (get-quality-control-record (batch-id (string-ascii 64)))
    (map-get? quality-control-records { batch-id: batch-id })
)

;; Get expired medicine information
(define-read-only (get-expired-medicine-info (batch-id (string-ascii 64)))
    (map-get? expired-medicines { batch-id: batch-id })
)

;; Get manufacturer batch count
(define-read-only (get-manufacturer-batch-count (manufacturer principal))
    (default-to u0 (get count (map-get? medicine-batches-count { manufacturer: manufacturer })))
)

;; Get contract statistics
(define-read-only (get-contract-stats)
    {
        total-medicines: (var-get total-medicines-registered),
        total-manufacturers: (var-get total-manufacturers),
        contract-active: (var-get contract-active),
        current-block: stacks-block-height
    }
)

;; Check if medicine is expired based on block height
(define-read-only (is-medicine-expired (batch-id (string-ascii 64)))
    (match (map-get? medicines { batch-id: batch-id })
        medicine-info (>= stacks-block-height (get expiry-date medicine-info))
        false
    )
)


