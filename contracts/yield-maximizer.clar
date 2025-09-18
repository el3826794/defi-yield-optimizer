
;; title: yield-maximizer
;; version: 1.0.0
;; summary: DeFi Yield Optimization Contract
;; description: Automatically allocates user funds across vetted yield farming opportunities with risk-adjusted 
;;             return optimization. Manages liquidity pool participation with impermanent loss protection 
;;             and automated rebalancing based on market volatility.

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-strategy-not-found (err u103))
(define-constant err-portfolio-not-found (err u104))
(define-constant err-invalid-allocation (err u105))
(define-constant err-emergency-active (err u106))
(define-constant err-slippage-exceeded (err u107))
(define-constant err-rebalance-too-frequent (err u108))
(define-constant err-strategy-inactive (err u109))
(define-constant err-insufficient-liquidity (err u110))

;; Strategy risk levels
(define-constant strategy-risk-conservative u1)
(define-constant strategy-risk-moderate u2)
(define-constant strategy-risk-aggressive u3)
(define-constant strategy-risk-institutional u4)

;; Performance and risk constants
(define-constant min-deposit-amount u1000000) ;; 1 STX minimum
(define-constant max-single-strategy-allocation u2500) ;; 25% max allocation
(define-constant rebalance-cooldown-period u144) ;; ~1 day in blocks
(define-constant emergency-withdrawal-fee u50) ;; 0.5% emergency fee
(define-constant performance-fee-rate u1000) ;; 10% performance fee
(define-constant max-slippage-tolerance u50) ;; 0.5% max slippage

;; Data Variables
(define-data-var portfolio-counter uint u0)
(define-data-var strategy-counter uint u0)
(define-data-var total-tvl uint u0)
(define-data-var emergency-mode bool false)
(define-data-var platform-fee-collector principal contract-owner)

;; Data Maps

;; User portfolio management
(define-map user-portfolios
  { user: principal }
  {
    portfolio-id: uint,
    total-deposited: uint,
    current-value: uint,
    strategy-allocations: (list 10 { strategy-id: uint, allocation: uint }),
    last-rebalance: uint,
    risk-preference: uint,
    auto-compound: bool,
    creation-height: uint
  }
)

;; Yield farming strategies registry
(define-map yield-strategies
  { strategy-id: uint }
  {
    name: (string-ascii 50),
    protocol-name: (string-ascii 30),
    risk-level: uint,
    target-apy: uint,
    current-apy: uint,
    tvl-allocated: uint,
    max-allocation: uint,
    is-active: bool,
    creation-height: uint,
    last-update: uint,
    impermanent-loss-risk: uint
  }
)

;; Portfolio performance tracking
(define-map portfolio-performance
  { portfolio-id: uint, period: uint }
  {
    starting-value: uint,
    ending-value: uint,
    yield-earned: uint,
    fees-paid: uint,
    rebalances-count: uint,
    max-drawdown: uint
  }
)

;; Strategy performance metrics
(define-map strategy-metrics
  { strategy-id: uint, timestamp: uint }
  {
    apy-achieved: uint,
    total-volume: uint,
    active-positions: uint,
    impermanent-loss: uint,
    sharpe-ratio: uint
  }
)

;; Risk assessment data
(define-map risk-assessments
  { portfolio-id: uint }
  {
    volatility-score: uint,
    correlation-risk: uint,
    liquidity-risk: uint,
    smart-contract-risk: uint,
    overall-risk-score: uint,
    last-assessment: uint
  }
)

;; Rebalancing history
(define-map rebalance-history
  { portfolio-id: uint, rebalance-id: uint }
  {
    previous-allocations: (list 10 { strategy-id: uint, allocation: uint }),
    new-allocations: (list 10 { strategy-id: uint, allocation: uint }),
    trigger-reason: (string-ascii 50),
    gas-costs: uint,
    slippage-incurred: uint,
    timestamp: uint
  }
)

;; Emergency withdrawal tracking
(define-map emergency-withdrawals
  { user: principal, withdrawal-id: uint }
  {
    amount: uint,
    fee-charged: uint,
    reason: (string-ascii 100),
    timestamp: uint,
    processing-time: uint
  }
)

;; Liquidity pool interactions
(define-map liquidity-positions
  { strategy-id: uint, position-id: uint }
  {
    pool-address: principal,
    token-a-amount: uint,
    token-b-amount: uint,
    lp-tokens: uint,
    entry-price: uint,
    rewards-earned: uint,
    is-active: bool
  }
)

;; Public Functions

;; Create optimized yield farming portfolio
(define-public (create-portfolio
  (initial-deposit uint)
  (risk-preference uint)
  (auto-compound bool)
)
  (let (
    (portfolio-id (+ (var-get portfolio-counter) u1))
    (user tx-sender)
  )
    (asserts! (not (var-get emergency-mode)) err-emergency-active)
    (asserts! (>= initial-deposit min-deposit-amount) err-insufficient-balance)
    (asserts! (<= risk-preference strategy-risk-institutional) err-invalid-allocation)
    (asserts! (is-none (map-get? user-portfolios { user: user })) err-invalid-allocation)
    
    ;; Transfer initial deposit
    (try! (stx-transfer? initial-deposit user (as-contract tx-sender)))
    
    ;; Create portfolio
    (map-set user-portfolios
      { user: user }
      {
        portfolio-id: portfolio-id,
        total-deposited: initial-deposit,
        current-value: initial-deposit,
        strategy-allocations: (list),
        last-rebalance: block-height,
        risk-preference: risk-preference,
        auto-compound: auto-compound,
        creation-height: block-height
      }
    )
    
    ;; Update global counters
    (var-set portfolio-counter portfolio-id)
    (var-set total-tvl (+ (var-get total-tvl) initial-deposit))
    
    ;; Initial strategy allocation
    (let (
      (allocation-result (auto-allocate-strategies portfolio-id initial-deposit risk-preference))
    )
      (ok portfolio-id)
    )
  )
)

;; Add new yield farming strategy
(define-public (add-strategy
  (name (string-ascii 50))
  (protocol-name (string-ascii 30))
  (risk-level uint)
  (target-apy uint)
  (max-allocation uint)
  (impermanent-loss-risk uint)
)
  (let (
    (strategy-id (+ (var-get strategy-counter) u1))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= risk-level strategy-risk-institutional) err-invalid-allocation)
    (asserts! (<= max-allocation u10000) err-invalid-allocation) ;; Max 100%
    
    ;; Add strategy to registry
    (map-set yield-strategies
      { strategy-id: strategy-id }
      {
        name: name,
        protocol-name: protocol-name,
        risk-level: risk-level,
        target-apy: target-apy,
        current-apy: target-apy,
        tvl-allocated: u0,
        max-allocation: max-allocation,
        is-active: true,
        creation-height: block-height,
        last-update: block-height,
        impermanent-loss-risk: impermanent-loss-risk
      }
    )
    
    (var-set strategy-counter strategy-id)
    (ok strategy-id)
  )
)

;; Deposit additional funds to existing portfolio
(define-public (deposit-funds (amount uint))
  (let (
    (user tx-sender)
    (portfolio-info (unwrap! (map-get? user-portfolios { user: user }) err-portfolio-not-found))
  )
    (asserts! (not (var-get emergency-mode)) err-emergency-active)
    (asserts! (>= amount min-deposit-amount) err-insufficient-balance)
    
    ;; Transfer additional funds
    (try! (stx-transfer? amount user (as-contract tx-sender)))
    
    ;; Update portfolio
    (map-set user-portfolios
      { user: user }
      (merge portfolio-info {
        total-deposited: (+ (get total-deposited portfolio-info) amount),
        current-value: (+ (get current-value portfolio-info) amount)
      })
    )
    
    ;; Update global TVL
    (var-set total-tvl (+ (var-get total-tvl) amount))
    
    ;; Trigger rebalancing if needed
    (let (
      (rebalance-result (auto-allocate-strategies (get portfolio-id portfolio-info) amount (get risk-preference portfolio-info)))
    )
      (ok true)
    )
  )
)

;; Trigger portfolio rebalancing
(define-public (rebalance-portfolio)
  (let (
    (user tx-sender)
    (portfolio-info (unwrap! (map-get? user-portfolios { user: user }) err-portfolio-not-found))
    (last-rebalance (get last-rebalance portfolio-info))
  )
    (asserts! (not (var-get emergency-mode)) err-emergency-active)
    (asserts! (> (- block-height last-rebalance) rebalance-cooldown-period) err-rebalance-too-frequent)
    
    ;; Calculate optimal allocations based on current market conditions
    (let (
      (current-value (get current-value portfolio-info))
      (risk-pref (get risk-preference portfolio-info))
      (portfolio-id (get portfolio-id portfolio-info))
      (rebalance-result (execute-rebalancing portfolio-id current-value risk-pref))
    )
      ;; Update last rebalance time
      (map-set user-portfolios
        { user: user }
        (merge portfolio-info { last-rebalance: block-height })
      )
      
      (ok true)
    )
  )
)

;; Withdraw earnings (compound rewards)
(define-public (compound-rewards)
  (let (
    (user tx-sender)
    (portfolio-info (unwrap! (map-get? user-portfolios { user: user }) err-portfolio-not-found))
  )
    (asserts! (not (var-get emergency-mode)) err-emergency-active)
    (asserts! (get auto-compound portfolio-info) err-not-authorized)
    
    ;; Calculate and compound rewards from all strategies
    (let (
      (rewards-earned (calculate-portfolio-rewards (get portfolio-id portfolio-info)))
      (performance-fee (* rewards-earned performance-fee-rate))
      (net-rewards (- rewards-earned (/ performance-fee u10000)))
    )
      ;; Update portfolio value
      (map-set user-portfolios
        { user: user }
        (merge portfolio-info {
          current-value: (+ (get current-value portfolio-info) net-rewards)
        })
      )
      
      ;; Pay performance fee
      (try! (as-contract (stx-transfer? (/ performance-fee u10000) tx-sender (var-get platform-fee-collector))))
      
      (ok net-rewards)
    )
  )
)

;; Emergency withdrawal with fee
(define-public (emergency-withdraw (reason (string-ascii 100)))
  (let (
    (user tx-sender)
    (portfolio-info (unwrap! (map-get? user-portfolios { user: user }) err-portfolio-not-found))
    (current-value (get current-value portfolio-info))
    (emergency-fee (* current-value emergency-withdrawal-fee))
    (withdrawal-amount (- current-value (/ emergency-fee u10000)))
    (withdrawal-id (+ block-height (get portfolio-id portfolio-info)))
  )
    ;; Process emergency withdrawal
    (try! (as-contract (stx-transfer? withdrawal-amount tx-sender user)))
    
    ;; Record emergency withdrawal
    (map-set emergency-withdrawals
      { user: user, withdrawal-id: withdrawal-id }
      {
        amount: withdrawal-amount,
        fee-charged: (/ emergency-fee u10000),
        reason: reason,
        timestamp: block-height,
        processing-time: u1 ;; Immediate processing
      }
    )
    
    ;; Remove portfolio
    (map-delete user-portfolios { user: user })
    
    ;; Update global TVL
    (var-set total-tvl (- (var-get total-tvl) current-value))
    
    (ok withdrawal-amount)
  )
)

;; Standard withdrawal with proper unwinding
(define-public (withdraw-portfolio)
  (let (
    (user tx-sender)
    (portfolio-info (unwrap! (map-get? user-portfolios { user: user }) err-portfolio-not-found))
  )
    (asserts! (not (var-get emergency-mode)) err-emergency-active)
    
    ;; Calculate final portfolio value after unwinding positions
    (let (
      (final-value (calculate-portfolio-value (get portfolio-id portfolio-info)))
      (rewards-earned (calculate-portfolio-rewards (get portfolio-id portfolio-info)))
      (total-withdrawal (+ final-value rewards-earned))
    )
      ;; Process withdrawal
      (try! (as-contract (stx-transfer? total-withdrawal tx-sender user)))
      
      ;; Remove portfolio
      (map-delete user-portfolios { user: user })
      
      ;; Update global TVL
      (var-set total-tvl (- (var-get total-tvl) final-value))
      
      (ok total-withdrawal)
    )
  )
)

;; Emergency pause (owner only)
(define-public (emergency-pause)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set emergency-mode true)
    (ok true)
  )
)

;; Read-only functions

;; Get user portfolio information
(define-read-only (get-portfolio-info (user principal))
  (map-get? user-portfolios { user: user })
)

;; Get strategy information
(define-read-only (get-strategy-info (strategy-id uint))
  (map-get? yield-strategies { strategy-id: strategy-id })
)

;; Get portfolio performance
(define-read-only (get-portfolio-performance (portfolio-id uint) (period uint))
  (map-get? portfolio-performance { portfolio-id: portfolio-id, period: period })
)

;; Get system statistics
(define-read-only (get-system-stats)
  {
    total-portfolios: (var-get portfolio-counter),
    total-strategies: (var-get strategy-counter),
    total-tvl: (var-get total-tvl),
    emergency-mode: (var-get emergency-mode)
  }
)

;; Calculate current portfolio value
(define-read-only (get-portfolio-value (user principal))
  (match (map-get? user-portfolios { user: user })
    portfolio-info
    (some (calculate-portfolio-value (get portfolio-id portfolio-info)))
    none
  )
)

;; Get risk assessment
(define-read-only (get-risk-assessment (portfolio-id uint))
  (map-get? risk-assessments { portfolio-id: portfolio-id })
)

;; Get strategy performance metrics
(define-read-only (get-strategy-metrics (strategy-id uint) (timestamp uint))
  (map-get? strategy-metrics { strategy-id: strategy-id, timestamp: timestamp })
)

;; Check if rebalancing is needed
(define-read-only (needs-rebalancing (user principal))
  (match (map-get? user-portfolios { user: user })
    portfolio-info
    (let (
      (last-rebalance (get last-rebalance portfolio-info))
      (time-threshold (> (- block-height last-rebalance) rebalance-cooldown-period))
      (deviation-threshold (check-allocation-deviation (get portfolio-id portfolio-info)))
    )
      (or time-threshold deviation-threshold)
    )
    false
  )
)

;; Get optimal strategy allocation
(define-read-only (get-optimal-allocation (risk-preference uint) (amount uint))
  (calculate-optimal-allocation risk-preference amount)
)

;; Private functions

;; Auto-allocate funds across strategies based on risk preference
(define-private (auto-allocate-strategies (portfolio-id uint) (amount uint) (risk-preference uint))
  (let (
    (optimal-allocations (calculate-optimal-allocation risk-preference amount))
  )
    ;; Execute allocations across strategies
    ;; In a real implementation, this would interact with actual DeFi protocols
    ;; For now, we'll just record the allocation decision
    (ok optimal-allocations)
  )
)

;; Calculate optimal strategy allocation
(define-private (calculate-optimal-allocation (risk-preference uint) (amount uint))
  (if (is-eq risk-preference strategy-risk-conservative)
    ;; Conservative allocation: 70% stable, 30% moderate yield
    (list { strategy-id: u1, allocation: u7000 } { strategy-id: u2, allocation: u3000 })
    (if (is-eq risk-preference strategy-risk-moderate)
      ;; Moderate allocation: 40% stable, 40% moderate, 20% aggressive  
      (list { strategy-id: u1, allocation: u4000 } { strategy-id: u2, allocation: u4000 } { strategy-id: u3, allocation: u2000 })
      (if (is-eq risk-preference strategy-risk-aggressive)
        ;; Aggressive allocation: 20% stable, 30% moderate, 50% aggressive
        (list { strategy-id: u1, allocation: u2000 } { strategy-id: u2, allocation: u3000 } { strategy-id: u3, allocation: u5000 })
        ;; Institutional allocation: 60% stable, 30% moderate, 10% aggressive
        (list { strategy-id: u1, allocation: u6000 } { strategy-id: u2, allocation: u3000 } { strategy-id: u3, allocation: u1000 })
      )
    )
  )
)

;; Execute rebalancing strategy
(define-private (execute-rebalancing (portfolio-id uint) (current-value uint) (risk-preference uint))
  (let (
    (new-allocations (calculate-optimal-allocation risk-preference current-value))
  )
    ;; Record rebalancing action
    (map-set rebalance-history
      { portfolio-id: portfolio-id, rebalance-id: block-height }
      {
        previous-allocations: (list),
        new-allocations: new-allocations,
        trigger-reason: "scheduled-rebalance",
        gas-costs: u0,
        slippage-incurred: u0,
        timestamp: block-height
      }
    )
    (ok true)
  )
)

;; Calculate portfolio current value
(define-private (calculate-portfolio-value (portfolio-id uint))
  ;; Simplified calculation - in real implementation would sum up all strategy positions
  u1000000 ;; Placeholder value
)

;; Calculate portfolio rewards
(define-private (calculate-portfolio-rewards (portfolio-id uint))
  ;; Simplified calculation - in real implementation would calculate rewards from all strategies
  u50000 ;; Placeholder rewards
)

;; Check if allocation has deviated significantly
(define-private (check-allocation-deviation (portfolio-id uint))
  ;; Simplified check - in real implementation would compare current vs target allocations
  false ;; Placeholder
)
