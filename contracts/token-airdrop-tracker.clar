(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-already-claimed (err u102))
(define-constant err-airdrop-not-active (err u103))
(define-constant err-insufficient-balance (err u104))
(define-constant err-invalid-amount (err u105))
(define-constant err-airdrop-ended (err u106))
(define-constant err-not-eligible (err u107))

(define-data-var airdrop-active bool false)
(define-data-var total-airdrop-amount uint u0)
(define-data-var airdrop-per-user uint u1000000)
(define-data-var total-claimed uint u0)
(define-data-var airdrop-end-block uint u0)

(define-map claimed-addresses principal bool)
(define-map eligible-addresses principal bool)
(define-map claim-amounts principal uint)

(define-fungible-token airdrop-token)

(define-read-only (has-claimed (address principal))
  (default-to false (map-get? claimed-addresses address))
)

(define-read-only (is-eligible (address principal))
  (default-to false (map-get? eligible-addresses address))
)

(define-read-only (get-claim-amount (address principal))
  (default-to u0 (map-get? claim-amounts address))
)

(define-read-only (is-airdrop-active)
  (var-get airdrop-active)
)

(define-read-only (get-total-claimed)
  (var-get total-claimed)
)

(define-read-only (get-airdrop-per-user)
  (var-get airdrop-per-user)
)

(define-read-only (get-total-airdrop-amount)
  (var-get total-airdrop-amount)
)

(define-read-only (get-airdrop-end-block)
  (var-get airdrop-end-block)
)

(define-read-only (get-contract-balance)
  (ft-get-balance airdrop-token (as-contract tx-sender))
)

(define-read-only (get-user-balance (address principal))
  (ft-get-balance airdrop-token address)
)

(define-read-only (blocks-until-end)
  (let ((end-block (var-get airdrop-end-block)))
    (if (> end-block stacks-block-height)
        (- end-block stacks-block-height)
        u0
    )
  )
)

(define-read-only (can-claim (address principal))
  (and 
    (var-get airdrop-active)
    (is-eligible address)
    (not (has-claimed address))
    (> (var-get airdrop-end-block) stacks-block-height)
  )
)

(define-public (initialize-airdrop (total-amount uint) (per-user uint) (duration-blocks uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> total-amount u0) err-invalid-amount)
    (asserts! (> per-user u0) err-invalid-amount)
    (var-set total-airdrop-amount total-amount)
    (var-set airdrop-per-user per-user)
    (var-set airdrop-end-block (+ stacks-block-height duration-blocks))
    (try! (ft-mint? airdrop-token total-amount (as-contract tx-sender)))
    (var-set airdrop-active true)
    (ok true)
  )
)

(define-public (add-eligible-address (address principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set eligible-addresses address true)
    (map-set claim-amounts address (var-get airdrop-per-user))
    (ok true)
  )
)

(define-public (add-eligible-addresses (addresses (list 100 principal)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map add-single-eligible addresses))
  )
)

(define-private (add-single-eligible (address principal))
  (begin
    (map-set eligible-addresses address true)
    (map-set claim-amounts address (var-get airdrop-per-user))
    true
  )
)

(define-public (set-custom-claim-amount (address principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (map-set eligible-addresses address true)
    (map-set claim-amounts address amount)
    (ok true)
  )
)

(define-public (claim-airdrop)
  (let (
    (claimer tx-sender)
    (claim-amount (get-claim-amount claimer))
  )
    (asserts! (var-get airdrop-active) err-airdrop-not-active)
    (asserts! (> (var-get airdrop-end-block) stacks-block-height) err-airdrop-ended)
    (asserts! (is-eligible claimer) err-not-eligible)
    (asserts! (not (has-claimed claimer)) err-already-claimed)
    (asserts! (>= (get-contract-balance) claim-amount) err-insufficient-balance)
    
    (map-set claimed-addresses claimer true)
    (var-set total-claimed (+ (var-get total-claimed) claim-amount))
    
    (try! (as-contract (ft-transfer? airdrop-token claim-amount tx-sender claimer)))
    (ok claim-amount)
  )
)

(define-public (emergency-stop)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set airdrop-active false)
    (ok true)
  )
)

(define-public (resume-airdrop)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set airdrop-active true)
    (ok true)
  )
)

(define-public (extend-airdrop (additional-blocks uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set airdrop-end-block (+ (var-get airdrop-end-block) additional-blocks))
    (ok (var-get airdrop-end-block))
  )
)

(define-public (withdraw-remaining)
  (let ((remaining-balance (get-contract-balance)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (or (not (var-get airdrop-active)) (<= (var-get airdrop-end-block) stacks-block-height)) err-airdrop-not-active)
    (try! (as-contract (ft-transfer? airdrop-token remaining-balance tx-sender contract-owner)))
    (ok remaining-balance)
  )
)

(define-read-only (get-airdrop-stats)
  {
    active: (var-get airdrop-active),
    total-amount: (var-get total-airdrop-amount),
    per-user: (var-get airdrop-per-user),
    total-claimed: (var-get total-claimed),
    remaining: (get-contract-balance),
    end-block: (var-get airdrop-end-block),
    blocks-remaining: (blocks-until-end)
  }
)

(define-read-only (get-user-status (address principal))
  {
    eligible: (is-eligible address),
    claimed: (has-claimed address),
    claim-amount: (get-claim-amount address),
    can-claim: (can-claim address),
    balance: (get-user-balance address)
  }
)



(define-constant err-not-found (err u201))
(define-constant err-already-exists (err u202))
(define-constant err-invalid-params (err u203))
(define-constant err-cliff-not-reached (err u204))
(define-constant err-nothing-to-claim (err u205))

(define-data-var next-schedule-id uint u1)

(define-map vesting-schedules 
  uint 
  {
    beneficiary: principal,
    total-amount: uint,
    start-block: uint,
    cliff-blocks: uint,
    duration-blocks: uint,
    claimed-amount: uint,
    revoked: bool
  }
)

(define-map beneficiary-schedules principal (list 50 uint))



(define-read-only (get-schedule (schedule-id uint))
  (map-get? vesting-schedules schedule-id)
)

(define-read-only (get-beneficiary-schedules (beneficiary principal))
  (default-to (list) (map-get? beneficiary-schedules beneficiary))
)

(define-read-only (calculate-vested-amount (schedule-id uint))
  (match (map-get? vesting-schedules schedule-id)
    schedule
    (let (
      (current-block stacks-block-height)
      (start-block (get start-block schedule))
      (cliff-end (+ start-block (get cliff-blocks schedule)))
      (vesting-end (+ start-block (get duration-blocks schedule)))
      (total-amount (get total-amount schedule))
    )
      (if (get revoked schedule)
        u0
        (if (< current-block cliff-end)
          u0
          (if (>= current-block vesting-end)
            total-amount
            (/ (* total-amount (- current-block start-block)) (get duration-blocks schedule))
          )
        )
      )
    )
    u0
  )
)

(define-read-only (calculate-claimable-amount (schedule-id uint))
  (match (map-get? vesting-schedules schedule-id)
    schedule
    (let (
      (vested-amount (calculate-vested-amount schedule-id))
      (claimed-amount (get claimed-amount schedule))
    )
      (if (> vested-amount claimed-amount)
        (- vested-amount claimed-amount)
        u0
      )
    )
    u0
  )
)



(define-public (fund-contract (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (try! (ft-mint? airdrop-token amount (as-contract tx-sender)))
    (ok amount)
  )
)

(define-public (create-vesting-schedule 
  (beneficiary principal) 
  (total-amount uint) 
  (start-block uint) 
  (cliff-blocks uint) 
  (duration-blocks uint)
)
  (let (
    (schedule-id (var-get next-schedule-id))
    (current-schedules (get-beneficiary-schedules beneficiary))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> total-amount u0) err-invalid-params)
    (asserts! (> duration-blocks u0) err-invalid-params)
    (asserts! (<= cliff-blocks duration-blocks) err-invalid-params)
    (asserts! (>= (get-contract-balance) total-amount) err-insufficient-balance)
    
    (map-set vesting-schedules schedule-id {
      beneficiary: beneficiary,
      total-amount: total-amount,
      start-block: start-block,
      cliff-blocks: cliff-blocks,
      duration-blocks: duration-blocks,
      claimed-amount: u0,
      revoked: false
    })
    
    (map-set beneficiary-schedules beneficiary (unwrap-panic (as-max-len? (append current-schedules schedule-id) u50)))
    (var-set next-schedule-id (+ schedule-id u1))
    (ok schedule-id)
  )
)

(define-public (claim-vested-tokens (schedule-id uint))
  (match (map-get? vesting-schedules schedule-id)
    schedule
    (let (
      (claimable-amount (calculate-claimable-amount schedule-id))
      (beneficiary (get beneficiary schedule))
    )
      (asserts! (is-eq tx-sender beneficiary) err-owner-only)
      (asserts! (> claimable-amount u0) err-nothing-to-claim)
      (asserts! (not (get revoked schedule)) err-not-found)
      (asserts! (>= stacks-block-height (+ (get start-block schedule) (get cliff-blocks schedule))) err-cliff-not-reached)
      
      (map-set vesting-schedules schedule-id 
        (merge schedule { claimed-amount: (+ (get claimed-amount schedule) claimable-amount) })
      )
      
      (try! (as-contract (ft-transfer? airdrop-token claimable-amount tx-sender beneficiary)))
      (ok claimable-amount)
    )
    err-not-found
  )
)

(define-public (revoke-schedule (schedule-id uint))
  (match (map-get? vesting-schedules schedule-id)
    schedule
    (let (
      (claimable-amount (calculate-claimable-amount schedule-id))
      (beneficiary (get beneficiary schedule))
      (unvested-amount (- (get total-amount schedule) (calculate-vested-amount schedule-id)))
    )
      (asserts! (is-eq tx-sender contract-owner) err-owner-only)
      (asserts! (not (get revoked schedule)) err-not-found)
      
      (if (> claimable-amount u0)
        (try! (as-contract (ft-transfer? airdrop-token claimable-amount tx-sender beneficiary)))
        true
      )
      
      (map-set vesting-schedules schedule-id (merge schedule { revoked: true }))
      (ok unvested-amount)
    )
    err-not-found
  )
)

(define-public (batch-create-schedules 
  (schedules (list 20 {
    beneficiary: principal,
    total-amount: uint,
    start-block: uint,
    cliff-blocks: uint,
    duration-blocks: uint
  }))
)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map create-single-schedule schedules))
  )
)

(define-private (create-single-schedule (schedule-data {
  beneficiary: principal,
  total-amount: uint,
  start-block: uint,
  cliff-blocks: uint,
  duration-blocks: uint
}))
  (unwrap-panic (create-vesting-schedule 
    (get beneficiary schedule-data)
    (get total-amount schedule-data)
    (get start-block schedule-data)
    (get cliff-blocks schedule-data)
    (get duration-blocks schedule-data)
  ))
)

(define-read-only (get-schedule-summary (schedule-id uint))
  (match (map-get? vesting-schedules schedule-id)
    schedule
    (ok {
      schedule: schedule,
      vested-amount: (calculate-vested-amount schedule-id),
      claimable-amount: (calculate-claimable-amount schedule-id),
      cliff-reached: (>= stacks-block-height (+ (get start-block schedule) (get cliff-blocks schedule))),
      fully-vested: (>= stacks-block-height (+ (get start-block schedule) (get duration-blocks schedule)))
    })
    err-not-found
  )
)

(define-read-only (get-beneficiary-summary (beneficiary principal))
  (let (
    (schedule-ids (get-beneficiary-schedules beneficiary))
  )
    {
      total-schedules: (len schedule-ids),
      schedule-ids: schedule-ids,
      total-balance: (get-user-balance beneficiary)
    }
  )
)