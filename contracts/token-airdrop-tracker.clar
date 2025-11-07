(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-already-claimed (err u102))
(define-constant err-airdrop-not-active (err u103))
(define-constant err-insufficient-balance (err u104))
(define-constant err-invalid-amount (err u105))
(define-constant err-airdrop-ended (err u106))
(define-constant err-not-eligible (err u107))
(define-constant err-referral-code-taken (err u108))
(define-constant err-invalid-referral-code (err u109))
(define-constant err-self-referral (err u110))
(define-constant err-already-has-referrer (err u111))
(define-constant err-invalid-early-bird-config (err u112))
(define-constant err-invalid-delegate (err u113))
(define-constant err-delegate-not-authorized (err u114))
(define-constant err-cannot-delegate-to-self (err u115))
(define-constant err-operator-not-authorized (err u116))

(define-data-var airdrop-active bool false)
(define-data-var total-airdrop-amount uint u0)
(define-data-var airdrop-per-user uint u1000000)
(define-data-var total-claimed uint u0)
(define-data-var airdrop-end-block uint u0)
(define-data-var referrer-bonus-percent uint u10)
(define-data-var referee-bonus-percent uint u5)
(define-data-var early-bird-enabled bool true)
(define-data-var early-bird-start-multiplier uint u200)
(define-data-var early-bird-decay-blocks uint u1000)
(define-data-var early-bird-min-multiplier uint u100)

(define-map claimed-addresses principal bool)
(define-map eligible-addresses principal bool)
(define-map claim-amounts principal uint)
(define-map referral-codes (string-ascii 32) principal)
(define-map user-referral-codes principal (string-ascii 32))
(define-map referrals principal principal)
(define-map referral-counts principal uint)
(define-map referral-earnings principal uint)
(define-map claim-delegates principal principal)
(define-map operators principal bool)

(define-fungible-token airdrop-token)

(define-read-only (is-operator (address principal))
  (default-to false (map-get? operators address))
)

(define-public (set-operator (address principal) (enabled bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (if enabled
      (begin (map-set operators address true) (ok true))
      (begin (map-delete operators address) (ok true))
    )
  )
)

(define-public (operator-add-eligible-address (address principal))
  (begin
    (asserts! (is-operator tx-sender) err-operator-not-authorized)
    (map-set eligible-addresses address true)
    (map-set claim-amounts address (var-get airdrop-per-user))
    (ok true)
  )
)

(define-public (operator-add-eligible-addresses (addresses (list 100 principal)))
  (begin
    (asserts! (is-operator tx-sender) err-operator-not-authorized)
    (ok (map add-single-eligible addresses))
  )
)

(define-public (operator-set-custom-claim-amount (address principal) (amount uint))
  (begin
    (asserts! (is-operator tx-sender) err-operator-not-authorized)
    (asserts! (> amount u0) err-invalid-amount)
    (map-set eligible-addresses address true)
    (map-set claim-amounts address amount)
    (ok true)
  )
)

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

(define-read-only (get-referral-code-owner (code (string-ascii 32)))
  (map-get? referral-codes code)
)

(define-read-only (get-user-referral-code (address principal))
  (map-get? user-referral-codes address)
)

(define-read-only (get-referrer (address principal))
  (map-get? referrals address)
)

(define-read-only (get-referral-count (address principal))
  (default-to u0 (map-get? referral-counts address))
)

(define-read-only (get-referral-earnings (address principal))
  (default-to u0 (map-get? referral-earnings address))
)

(define-read-only (get-referral-bonus-percents)
  {
    referrer-bonus: (var-get referrer-bonus-percent),
    referee-bonus: (var-get referee-bonus-percent)
  }
)

(define-read-only (calculate-early-bird-multiplier)
  (if (not (var-get early-bird-enabled))
    u100
    (let (
      (current-block stacks-block-height)
      (end-block (var-get airdrop-end-block))
      (start-multiplier (var-get early-bird-start-multiplier))
      (min-multiplier (var-get early-bird-min-multiplier))
      (decay-blocks (var-get early-bird-decay-blocks))
    )
      (if (>= current-block end-block)
        min-multiplier
        (let (
          (blocks-remaining (blocks-until-end))
          (decay-periods (/ (- (var-get airdrop-end-block) current-block) decay-blocks))
          (multiplier-reduction (* decay-periods u5))
        )
          (let ((calculated-multiplier (- start-multiplier multiplier-reduction)))
            (if (< calculated-multiplier min-multiplier)
              min-multiplier
              calculated-multiplier
            )
          )
        )
      )
    )
  )
)

(define-read-only (get-early-bird-config)
  {
    enabled: (var-get early-bird-enabled),
    start-multiplier: (var-get early-bird-start-multiplier),
    decay-blocks: (var-get early-bird-decay-blocks),
    min-multiplier: (var-get early-bird-min-multiplier),
    current-multiplier: (calculate-early-bird-multiplier)
  }
)

(define-read-only (calculate-early-bird-claim-amount (address principal))
  (let (
    (base-amount (get-claim-amount address))
    (multiplier (calculate-early-bird-multiplier))
  )
    (/ (* base-amount multiplier) u100)
  )
)

(define-read-only (get-delegate (delegator principal))
  (map-get? claim-delegates delegator)
)

(define-read-only (is-authorized-delegate (delegator principal) (delegate principal))
  (match (map-get? claim-delegates delegator)
    authorized-delegate (is-eq authorized-delegate delegate)
    false
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

(define-public (set-referral-code (code (string-ascii 32)))
  (begin
    (asserts! (is-none (map-get? referral-codes code)) err-referral-code-taken)
    (asserts! (> (len code) u0) err-invalid-referral-code)
    (map-set referral-codes code tx-sender)
    (map-set user-referral-codes tx-sender code)
    (ok true)
  )
)

(define-public (use-referral-code (code (string-ascii 32)))
  (let (
    (referrer-opt (map-get? referral-codes code))
  )
    (asserts! (is-some referrer-opt) err-invalid-referral-code)
    (let ((referrer (unwrap-panic referrer-opt)))
      (asserts! (not (is-eq tx-sender referrer)) err-self-referral)
      (asserts! (is-none (map-get? referrals tx-sender)) err-already-has-referrer)
      (map-set referrals tx-sender referrer)
      (map-set referral-counts referrer (+ (get-referral-count referrer) u1))
      (ok referrer)
    )
  )
)

(define-public (set-referral-bonus-percents (referrer-bonus uint) (referee-bonus uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= referrer-bonus u100) err-invalid-amount)
    (asserts! (<= referee-bonus u100) err-invalid-amount)
    (var-set referrer-bonus-percent referrer-bonus)
    (var-set referee-bonus-percent referee-bonus)
    (ok true)
  )
)

(define-public (configure-early-bird (enabled bool) (start-multiplier uint) (decay-blocks uint) (min-multiplier uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (>= start-multiplier u100) err-invalid-early-bird-config)
    (asserts! (>= min-multiplier u100) err-invalid-early-bird-config)
    (asserts! (<= min-multiplier start-multiplier) err-invalid-early-bird-config)
    (asserts! (> decay-blocks u0) err-invalid-early-bird-config)
    (var-set early-bird-enabled enabled)
    (var-set early-bird-start-multiplier start-multiplier)
    (var-set early-bird-decay-blocks decay-blocks)
    (var-set early-bird-min-multiplier min-multiplier)
    (ok true)
  )
)

(define-public (set-claim-delegate (delegate principal))
  (begin
    (asserts! (not (is-eq tx-sender delegate)) err-cannot-delegate-to-self)
    (map-set claim-delegates tx-sender delegate)
    (ok true)
  )
)

(define-public (revoke-claim-delegate)
  (begin
    (map-delete claim-delegates tx-sender)
    (ok true)
  )
)

(define-public (claim-airdrop)
  (let (
    (claimer tx-sender)
    (base-claim-amount (get-claim-amount claimer))
    (early-bird-multiplier (calculate-early-bird-multiplier))
    (early-bird-amount (/ (* base-claim-amount early-bird-multiplier) u100))
    (referrer-opt (map-get? referrals claimer))
    (referee-bonus (/ (* early-bird-amount (var-get referee-bonus-percent)) u100))
    (total-claim-amount (+ early-bird-amount referee-bonus))
  )
    (asserts! (var-get airdrop-active) err-airdrop-not-active)
    (asserts! (> (var-get airdrop-end-block) stacks-block-height) err-airdrop-ended)
    (asserts! (is-eligible claimer) err-not-eligible)
    (asserts! (not (has-claimed claimer)) err-already-claimed)
    (asserts! (>= (get-contract-balance) total-claim-amount) err-insufficient-balance)
    
    (map-set claimed-addresses claimer true)
    (var-set total-claimed (+ (var-get total-claimed) total-claim-amount))
    
    (try! (as-contract (ft-transfer? airdrop-token total-claim-amount tx-sender claimer)))
    
    (match referrer-opt
      referrer
      (let (
        (referrer-bonus (/ (* early-bird-amount (var-get referrer-bonus-percent)) u100))
      )
        (if (and (> referrer-bonus u0) (>= (get-contract-balance) referrer-bonus))
          (begin
            (try! (as-contract (ft-transfer? airdrop-token referrer-bonus tx-sender referrer)))
            (map-set referral-earnings referrer (+ (get-referral-earnings referrer) referrer-bonus))
            (var-set total-claimed (+ (var-get total-claimed) referrer-bonus))
            true
          )
          true
        )
      )
      true
    )
    
    (ok total-claim-amount)
  )
)

(define-public (claim-airdrop-for (beneficiary principal))
  (let (
    (delegate tx-sender)
    (base-claim-amount (get-claim-amount beneficiary))
    (early-bird-multiplier (calculate-early-bird-multiplier))
    (early-bird-amount (/ (* base-claim-amount early-bird-multiplier) u100))
    (referrer-opt (map-get? referrals beneficiary))
    (referee-bonus (/ (* early-bird-amount (var-get referee-bonus-percent)) u100))
    (total-claim-amount (+ early-bird-amount referee-bonus))
  )
    (asserts! (is-authorized-delegate beneficiary delegate) err-delegate-not-authorized)
    (asserts! (var-get airdrop-active) err-airdrop-not-active)
    (asserts! (> (var-get airdrop-end-block) stacks-block-height) err-airdrop-ended)
    (asserts! (is-eligible beneficiary) err-not-eligible)
    (asserts! (not (has-claimed beneficiary)) err-already-claimed)
    (asserts! (>= (get-contract-balance) total-claim-amount) err-insufficient-balance)
    
    (map-set claimed-addresses beneficiary true)
    (var-set total-claimed (+ (var-get total-claimed) total-claim-amount))
    
    (try! (as-contract (ft-transfer? airdrop-token total-claim-amount tx-sender beneficiary)))
    
    (match referrer-opt
      referrer
      (let (
        (referrer-bonus (/ (* early-bird-amount (var-get referrer-bonus-percent)) u100))
      )
        (if (and (> referrer-bonus u0) (>= (get-contract-balance) referrer-bonus))
          (begin
            (try! (as-contract (ft-transfer? airdrop-token referrer-bonus tx-sender referrer)))
            (map-set referral-earnings referrer (+ (get-referral-earnings referrer) referrer-bonus))
            (var-set total-claimed (+ (var-get total-claimed) referrer-bonus))
            true
          )
          true
        )
      )
      true
    )
    
    (ok total-claim-amount)
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
    balance: (get-user-balance address),
    referral-code: (get-user-referral-code address),
    referrer: (get-referrer address),
    referral-count: (get-referral-count address),
    referral-earnings: (get-referral-earnings address),
    early-bird-claim-amount: (calculate-early-bird-claim-amount address),
    current-early-bird-multiplier: (calculate-early-bird-multiplier),
    claim-delegate: (get-delegate address)
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
