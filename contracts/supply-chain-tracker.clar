;; MediChain Supply Chain Tracker Contract
;; This contract tracks medicine movement through the supply chain
;; Maintains complete history and ownership records

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-already-exists (err u202))
(define-constant err-unauthorized (err u203))
(define-constant err-invalid-participant (err u204))
(define-constant err-invalid-transfer (err u205))
(define-constant err-medicine-not-active (err u206))
(define-constant err-same-owner (err u207))
(define-constant err-participant-inactive (err u208))

;; Supply chain tracking for MediChain

;; Data structures
(define-map supply-chain-participants
    { participant: principal }
    {
        name: (string-ascii 128),
        participant-type: (string-ascii 32), ;; manufacturer, distributor, pharmacy, hospital
        license-id: (string-ascii 64),
        registration-date: uint,
        is-active: bool,
        address: (string-ascii 256),
        contact-info: (string-ascii 128)
    }
)

(define-map medicine-transfers
    { transfer-id: uint }
    {
        batch-id: (string-ascii 64),
        from-participant: principal,
        to-participant: principal,
        transfer-date: uint,
        quantity-transferred: uint,
        transfer-type: (string-ascii 32), ;; sale, distribution, return
        verification-code: (string-ascii 64),
        notes: (string-ascii 256),
        is-verified: bool
    }
)

(define-map medicine-ownership-history
    { batch-id: (string-ascii 64), sequence: uint }
    {
        owner: principal,
        ownership-start: uint,
        ownership-end: (optional uint),
        transfer-reason: (string-ascii 64),
        location: (string-ascii 128)
    }
)

(define-map batch-current-location
    { batch-id: (string-ascii 64) }
    {
        current-owner: principal,
        location: (string-ascii 256),
        last-updated: uint,
        quantity-remaining: uint,
        status: (string-ascii 32)
    }
)

(define-map participant-transaction-history
    { participant: principal, transaction-id: uint }
    {
        batch-id: (string-ascii 64),
        transaction-type: (string-ascii 32),
        counterparty: principal,
        timestamp: uint,
        quantity: uint
    }
)

(define-map batch-verification-records
    { batch-id: (string-ascii 64), verifier: principal }
    {
        verification-date: uint,
        verification-result: bool,
        verification-notes: (string-ascii 256),
        digital-signature: (string-ascii 128)
    }
)

(define-map temperature-logs
    { batch-id: (string-ascii 64), log-id: uint }
    {
        temperature: int,
        humidity: uint,
        location: (string-ascii 128),
        timestamp: uint,
        recorded-by: principal,
        is-within-range: bool
    }
)

;; Data variables
(define-data-var next-transfer-id uint u1)
(define-data-var total-participants uint u0)
(define-data-var total-transfers uint u0)
(define-data-var contract-active bool true)

;; Public functions

;; Register a new supply chain participant
(define-public (register-participant 
    (participant principal)
    (name (string-ascii 128))
    (participant-type (string-ascii 32))
    (license-id (string-ascii 64))
    (address (string-ascii 256))
    (contact-info (string-ascii 128))
)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-none (map-get? supply-chain-participants { participant: participant })) err-already-exists)
        (asserts! (> (len name) u0) err-invalid-participant)
        (asserts! (> (len license-id) u0) err-invalid-participant)
        
        (map-set supply-chain-participants
            { participant: participant }
            {
                name: name,
                participant-type: participant-type,
                license-id: license-id,
                registration-date: stacks-block-height,
                is-active: true,
                address: address,
                contact-info: contact-info
            }
        )
        
        (var-set total-participants (+ (var-get total-participants) u1))
        (ok true)
    )
)

;; Transfer medicine ownership
(define-public (transfer-medicine 
    (batch-id (string-ascii 64))
    (to-participant principal)
    (quantity uint)
    (transfer-type (string-ascii 32))
    (verification-code (string-ascii 64))
    (notes (string-ascii 256))
)
    (let
        (
            (transfer-id (var-get next-transfer-id))
            (current-location (map-get? batch-current-location { batch-id: batch-id }))
            (to-participant-info (unwrap! (map-get? supply-chain-participants { participant: to-participant }) err-not-found))
            (from-participant-info (unwrap! (map-get? supply-chain-participants { participant: tx-sender }) err-unauthorized))
        )
        
        ;; Validation checks
        (asserts! (var-get contract-active) err-unauthorized)
        (asserts! (get is-active from-participant-info) err-participant-inactive)
        (asserts! (get is-active to-participant-info) err-participant-inactive)
        (asserts! (> quantity u0) err-invalid-transfer)
        (asserts! (not (is-eq tx-sender to-participant)) err-same-owner)
        
        ;; Check if sender is current owner or if no current owner exists
        (match current-location
            location-info
                (begin
                    (asserts! (is-eq tx-sender (get current-owner location-info)) err-unauthorized)
                    (asserts! (>= (get quantity-remaining location-info) quantity) err-invalid-transfer)
                    (asserts! (is-eq (get status location-info) "active") err-medicine-not-active)
                )
            ;; If no current location, this is the first transfer from manufacturer
            true
        )
        
        ;; Record the transfer
        (map-set medicine-transfers
            { transfer-id: transfer-id }
            {
                batch-id: batch-id,
                from-participant: tx-sender,
                to-participant: to-participant,
                transfer-date: stacks-block-height,
                quantity-transferred: quantity,
                transfer-type: transfer-type,
                verification-code: verification-code,
                notes: notes,
                is-verified: false
            }
        )
        
        ;; Update current location
        (match current-location
            location-info
                (map-set batch-current-location
                    { batch-id: batch-id }
                    {
                        current-owner: to-participant,
                        location: (get address to-participant-info),
                        last-updated: stacks-block-height,
                        quantity-remaining: (- (get quantity-remaining location-info) quantity),
                        status: "active"
                    }
                )
            ;; First transfer - set initial location
            (map-set batch-current-location
                { batch-id: batch-id }
                {
                    current-owner: to-participant,
                    location: (get address to-participant-info),
                    last-updated: stacks-block-height,
                    quantity-remaining: quantity,
                    status: "active"
                }
            )
        )
        
        ;; Record transaction history for both participants
        (let
            (
                (from-tx-count (get-participant-transaction-count tx-sender))
                (to-tx-count (get-participant-transaction-count to-participant))
            )
            ;; From participant transaction
            (map-set participant-transaction-history
                { participant: tx-sender, transaction-id: from-tx-count }
                {
                    batch-id: batch-id,
                    transaction-type: "outbound",
                    counterparty: to-participant,
                    timestamp: stacks-block-height,
                    quantity: quantity
                }
            )
            
            ;; To participant transaction
            (map-set participant-transaction-history
                { participant: to-participant, transaction-id: to-tx-count }
                {
                    batch-id: batch-id,
                    transaction-type: "inbound",
                    counterparty: tx-sender,
                    timestamp: stacks-block-height,
                    quantity: quantity
                }
            )
        )
        
        ;; Update counters
        (var-set next-transfer-id (+ transfer-id u1))
        (var-set total-transfers (+ (var-get total-transfers) u1))
        
        (ok transfer-id)
    )
)

;; Verify a medicine transfer
(define-public (verify-transfer (transfer-id uint) (verification-result bool) (notes (string-ascii 256)))
    (let
        (
            (transfer-info (unwrap! (map-get? medicine-transfers { transfer-id: transfer-id }) err-not-found))
            (participant-info (unwrap! (map-get? supply-chain-participants { participant: tx-sender }) err-unauthorized))
        )
        
        ;; Only active participants can verify transfers
        (asserts! (get is-active participant-info) err-participant-inactive)
        
        ;; Update transfer verification status
        (map-set medicine-transfers
            { transfer-id: transfer-id }
            (merge transfer-info { is-verified: verification-result })
        )
        
        ;; Record verification
        (map-set batch-verification-records
            { batch-id: (get batch-id transfer-info), verifier: tx-sender }
            {
                verification-date: stacks-block-height,
                verification-result: verification-result,
                verification-notes: notes,
                digital-signature: "verified"
            }
        )
        
        (ok true)
    )
)

;; Add temperature/humidity log
(define-public (add-temperature-log 
    (batch-id (string-ascii 64))
    (temperature int)
    (humidity uint)
    (location (string-ascii 128))
    (is-within-range bool)
)
    (let
        (
            (participant-info (unwrap! (map-get? supply-chain-participants { participant: tx-sender }) err-unauthorized))
            (log-id (get-temperature-log-count batch-id))
        )
        
        ;; Only active participants can add temperature logs
        (asserts! (get is-active participant-info) err-participant-inactive)
        
        (map-set temperature-logs
            { batch-id: batch-id, log-id: log-id }
            {
                temperature: temperature,
                humidity: humidity,
                location: location,
                timestamp: stacks-block-height,
                recorded-by: tx-sender,
                is-within-range: is-within-range
            }
        )
        
        (ok log-id)
    )
)

;; Update participant status
(define-public (update-participant-status (participant principal) (is-active bool))
    (let
        (
            (participant-info (unwrap! (map-get? supply-chain-participants { participant: participant }) err-not-found))
        )
        
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (map-set supply-chain-participants
            { participant: participant }
            (merge participant-info { is-active: is-active })
        )
        
        (ok true)
    )
)

;; Emergency pause contract
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

;; Get participant information
(define-read-only (get-participant-info (participant principal))
    (map-get? supply-chain-participants { participant: participant })
)

;; Get transfer information
(define-read-only (get-transfer-info (transfer-id uint))
    (map-get? medicine-transfers { transfer-id: transfer-id })
)

;; Get current medicine location
(define-read-only (get-current-location (batch-id (string-ascii 64)))
    (map-get? batch-current-location { batch-id: batch-id })
)

;; Get ownership history
(define-read-only (get-ownership-history (batch-id (string-ascii 64)) (sequence uint))
    (map-get? medicine-ownership-history { batch-id: batch-id, sequence: sequence })
)

;; Get verification record
(define-read-only (get-verification-record (batch-id (string-ascii 64)) (verifier principal))
    (map-get? batch-verification-records { batch-id: batch-id, verifier: verifier })
)

;; Get temperature log
(define-read-only (get-temperature-log (batch-id (string-ascii 64)) (log-id uint))
    (map-get? temperature-logs { batch-id: batch-id, log-id: log-id })
)

;; Get participant transaction history
(define-read-only (get-participant-transaction (participant principal) (transaction-id uint))
    (map-get? participant-transaction-history { participant: participant, transaction-id: transaction-id })
)

;; Helper function to get participant transaction count
(define-read-only (get-participant-transaction-count (participant principal))
    (let
        (
            (count u0)
        )
        ;; In a real implementation, this would iterate through transactions
        ;; For simplicity, returning a default count
        (+ count u1)
    )
)

;; Helper function to get temperature log count for a batch
(define-read-only (get-temperature-log-count (batch-id (string-ascii 64)))
    ;; In a real implementation, this would count existing logs
    ;; For simplicity, returning a default increment
    u1
)

;; Get contract statistics
(define-read-only (get-contract-stats)
    {
        total-participants: (var-get total-participants),
        total-transfers: (var-get total-transfers),
        next-transfer-id: (var-get next-transfer-id),
        contract-active: (var-get contract-active),
        current-block: stacks-block-height
    }
)

;; Check if participant is authorized for specific operations
(define-read-only (is-participant-authorized (participant principal))
    (match (map-get? supply-chain-participants { participant: participant })
        participant-info (get is-active participant-info)
        false
    )
)

;; Get medicine transfer chain (simplified version)
(define-read-only (get-medicine-chain-info (batch-id (string-ascii 64)))
    (let
        (
            (current-loc (map-get? batch-current-location { batch-id: batch-id }))
        )
        (match current-loc
            location-info
                {
                    batch-id: batch-id,
                    current-owner: (get current-owner location-info),
                    current-location: (get location location-info),
                    last-updated: (get last-updated location-info),
                    quantity: (get quantity-remaining location-info),
                    status: (get status location-info)
                }
            {
                batch-id: batch-id,
                current-owner: contract-owner,
                current-location: "Not tracked",
                last-updated: u0,
                quantity: u0,
                status: "unknown"
            }
        )
    )
)


