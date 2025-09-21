;; startup-registration
;; Contract for registering and managing local startups in the community marketplace

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-startup-exists (err u101))
(define-constant err-startup-not-found (err u102))
(define-constant err-invalid-stage (err u103))
(define-constant err-unauthorized (err u104))

;; Data Maps
(define-map startups
  { startup-id: uint }
  {
    founder: principal,
    name: (string-utf8 100),
    description: (string-utf8 500),
    category: (string-utf8 50),
    stage: (string-utf8 20),
    funding-needed: uint,
    funding-raised: uint,
    registration-block: uint,
    is-active: bool,
    verification-status: (string-utf8 20)
  }
)

(define-map startup-metrics
  { startup-id: uint }
  {
    mentor-connections: uint,
    resource-requests: uint,
    community-support: uint,
    milestone-count: uint
  }
)

(define-map user-startups
  { user: principal }
  { startup-ids: (list 10 uint) }
)

;; Data Variables
(define-data-var next-startup-id uint u1)
(define-data-var total-startups uint u0)
(define-data-var total-funding-needed uint u0)
(define-data-var total-funding-raised uint u0)

;; Private Functions
(define-private (is-valid-stage (stage (string-utf8 20)))
  (or (is-eq stage u"idea")
      (is-eq stage u"prototype")
      (is-eq stage u"mvp")
      (is-eq stage u"growth")
      (is-eq stage u"scaling"))
)

;; Public Functions
(define-public (register-startup 
    (name (string-utf8 100))
    (description (string-utf8 500))
    (category (string-utf8 50))
    (stage (string-utf8 20))
    (funding-needed uint)
  )
  (let 
    (
      (startup-id (var-get next-startup-id))
      (current-startups (default-to { startup-ids: (list) } 
        (map-get? user-startups { user: tx-sender })))
    )
    (asserts! (is-valid-stage stage) err-invalid-stage)
    (asserts! (< (len (get startup-ids current-startups)) u10) (err u105))
    
    ;; Register startup
    (map-set startups
      { startup-id: startup-id }
      {
        founder: tx-sender,
        name: name,
        description: description,
        category: category,
        stage: stage,
        funding-needed: funding-needed,
        funding-raised: u0,
        registration-block: block-height,
        is-active: true,
        verification-status: u"pending"
      }
    )
    
    ;; Initialize metrics
    (map-set startup-metrics
      { startup-id: startup-id }
      {
        mentor-connections: u0,
        resource-requests: u0,
        community-support: u0,
        milestone-count: u0
      }
    )
    
    ;; Update user's startup list
    (map-set user-startups
      { user: tx-sender }
      { startup-ids: (unwrap! (as-max-len? 
          (append (get startup-ids current-startups) startup-id) u10)
        (err u106)) }
    )
    
    ;; Update counters
    (var-set next-startup-id (+ startup-id u1))
    (var-set total-startups (+ (var-get total-startups) u1))
    (var-set total-funding-needed (+ (var-get total-funding-needed) funding-needed))
    
    (ok startup-id)
  )
)

(define-public (update-startup-stage (startup-id uint) (new-stage (string-utf8 20)))
  (let
    (
      (startup (unwrap! (map-get? startups { startup-id: startup-id }) err-startup-not-found))
    )
    (asserts! (is-eq tx-sender (get founder startup)) err-unauthorized)
    (asserts! (is-valid-stage new-stage) err-invalid-stage)
    
    (map-set startups
      { startup-id: startup-id }
      (merge startup { stage: new-stage })
    )
    (ok true)
  )
)

(define-public (update-funding-raised (startup-id uint) (amount uint))
  (let
    (
      (startup (unwrap! (map-get? startups { startup-id: startup-id }) err-startup-not-found))
      (current-raised (get funding-raised startup))
      (new-total (+ current-raised amount))
    )
    (asserts! (is-eq tx-sender (get founder startup)) err-unauthorized)
    
    (map-set startups
      { startup-id: startup-id }
      (merge startup { funding-raised: new-total })
    )
    
    (var-set total-funding-raised (+ (var-get total-funding-raised) amount))
    (ok new-total)
  )
)

(define-public (verify-startup (startup-id uint) (status (string-utf8 20)))
  (let
    (
      (startup (unwrap! (map-get? startups { startup-id: startup-id }) err-startup-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (or (is-eq status u"verified") 
                  (is-eq status u"rejected")
                  (is-eq status u"pending")) (err u107))
    
    (map-set startups
      { startup-id: startup-id }
      (merge startup { verification-status: status })
    )
    (ok true)
  )
)

(define-public (increment-metric (startup-id uint) (metric (string-utf8 20)))
  (let
    (
      (metrics (unwrap! (map-get? startup-metrics { startup-id: startup-id }) err-startup-not-found))
    )
    (if (is-eq metric u"mentor")
      (map-set startup-metrics
        { startup-id: startup-id }
        (merge metrics { mentor-connections: (+ (get mentor-connections metrics) u1) })
      )
      (if (is-eq metric u"resource")
        (map-set startup-metrics
          { startup-id: startup-id }
          (merge metrics { resource-requests: (+ (get resource-requests metrics) u1) })
        )
        (if (is-eq metric u"support")
          (map-set startup-metrics
            { startup-id: startup-id }
            (merge metrics { community-support: (+ (get community-support metrics) u1) })
          )
          (if (is-eq metric u"milestone")
            (map-set startup-metrics
              { startup-id: startup-id }
              (merge metrics { milestone-count: (+ (get milestone-count metrics) u1) })
            )
            false
          )
        )
      )
    )
    (ok true)
  )
)

;; Read Functions
(define-read-only (get-startup (startup-id uint))
  (map-get? startups { startup-id: startup-id })
)

(define-read-only (get-startup-metrics (startup-id uint))
  (map-get? startup-metrics { startup-id: startup-id })
)

(define-read-only (get-user-startups (user principal))
  (map-get? user-startups { user: user })
)

(define-read-only (get-platform-stats)
  {
    total-startups: (var-get total-startups),
    total-funding-needed: (var-get total-funding-needed),
    total-funding-raised: (var-get total-funding-raised),
    next-id: (var-get next-startup-id)
  }
)

