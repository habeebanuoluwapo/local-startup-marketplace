;; resource-allocation
;; Contract for managing resource allocation and sharing in the startup marketplace

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-resource-not-found (err u101))
(define-constant err-request-not-found (err u102))
(define-constant err-insufficient-quantity (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-self-request (err u105))

;; Data Maps
(define-map resources
  { resource-id: uint }
  {
    provider: principal,
    name: (string-utf8 100),
    description: (string-utf8 300),
    category: (string-utf8 50),
    resource-type: (string-utf8 30),
    quantity-available: uint,
    quantity-total: uint,
    cost-per-unit: uint,
    requirements: (string-utf8 200),
    location: (string-utf8 100),
    is-active: bool,
    creation-block: uint
  }
)

(define-map resource-requests
  { request-id: uint }
  {
    requester: principal,
    resource-id: uint,
    startup-id: uint,
    quantity-requested: uint,
    purpose: (string-utf8 300),
    duration-blocks: uint,
    status: (string-utf8 20),
    request-block: uint,
    response-block: (optional uint),
    completion-block: (optional uint)
  }
)

(define-map resource-allocations
  { allocation-id: uint }
  {
    request-id: uint,
    resource-id: uint,
    provider: principal,
    requester: principal,
    quantity-allocated: uint,
    start-block: uint,
    end-block: uint,
    actual-return-block: (optional uint),
    condition-rating: (optional uint),
    provider-rating: (optional uint),
    requester-rating: (optional uint)
  }
)

(define-map user-resources
  { user: principal }
  { resource-ids: (list 20 uint) }
)

(define-map user-requests
  { user: principal }
  { request-ids: (list 30 uint) }
)

;; Data Variables
(define-data-var next-resource-id uint u1)
(define-data-var next-request-id uint u1)
(define-data-var next-allocation-id uint u1)
(define-data-var total-resources uint u0)
(define-data-var total-requests uint u0)
(define-data-var total-allocations uint u0)
(define-data-var total-active-allocations uint u0)

;; Private Functions
(define-private (is-valid-resource-type (resource-type (string-utf8 30)))
  (or (is-eq resource-type u"equipment")
      (is-eq resource-type u"workspace")
      (is-eq resource-type u"service")
      (is-eq resource-type u"funding")
      (is-eq resource-type u"expertise"))
)

(define-private (is-valid-status (status (string-utf8 20)))
  (or (is-eq status u"pending")
      (is-eq status u"approved")
      (is-eq status u"rejected")
      (is-eq status u"active")
      (is-eq status u"completed")
      (is-eq status u"cancelled"))
)

;; Public Functions
(define-public (register-resource
    (name (string-utf8 100))
    (description (string-utf8 300))
    (category (string-utf8 50))
    (resource-type (string-utf8 30))
    (quantity-total uint)
    (cost-per-unit uint)
    (requirements (string-utf8 200))
    (location (string-utf8 100))
  )
  (let
    (
      (resource-id (var-get next-resource-id))
      (current-resources (default-to { resource-ids: (list) }
        (map-get? user-resources { user: tx-sender })))
    )
    (asserts! (is-valid-resource-type resource-type) (err u106))
    (asserts! (> quantity-total u0) (err u107))
    
    ;; Register resource
    (map-set resources
      { resource-id: resource-id }
      {
        provider: tx-sender,
        name: name,
        description: description,
        category: category,
        resource-type: resource-type,
        quantity-available: quantity-total,
        quantity-total: quantity-total,
        cost-per-unit: cost-per-unit,
        requirements: requirements,
        location: location,
        is-active: true,
        creation-block: block-height
      }
    )
    
    ;; Update user's resource list
    (map-set user-resources
      { user: tx-sender }
      { resource-ids: (unwrap! (as-max-len?
          (append (get resource-ids current-resources) resource-id) u20)
        (err u108)) }
    )
    
    ;; Update counters
    (var-set next-resource-id (+ resource-id u1))
    (var-set total-resources (+ (var-get total-resources) u1))
    
    (ok resource-id)
  )
)

(define-public (request-resource
    (resource-id uint)
    (startup-id uint)
    (quantity-requested uint)
    (purpose (string-utf8 300))
    (duration-blocks uint)
  )
  (let
    (
      (request-id (var-get next-request-id))
      (resource (unwrap! (map-get? resources { resource-id: resource-id }) err-resource-not-found))
      (current-requests (default-to { request-ids: (list) }
        (map-get? user-requests { user: tx-sender })))
    )
    (asserts! (not (is-eq tx-sender (get provider resource))) err-self-request)
    (asserts! (get is-active resource) (err u109))
    (asserts! (<= quantity-requested (get quantity-available resource)) err-insufficient-quantity)
    (asserts! (> duration-blocks u0) (err u110))
    
    ;; Create resource request
    (map-set resource-requests
      { request-id: request-id }
      {
        requester: tx-sender,
        resource-id: resource-id,
        startup-id: startup-id,
        quantity-requested: quantity-requested,
        purpose: purpose,
        duration-blocks: duration-blocks,
        status: u"pending",
        request-block: block-height,
        response-block: none,
        completion-block: none
      }
    )
    
    ;; Update user's request list
    (map-set user-requests
      { user: tx-sender }
      { request-ids: (unwrap! (as-max-len?
          (append (get request-ids current-requests) request-id) u30)
        (err u111)) }
    )
    
    ;; Update counters
    (var-set next-request-id (+ request-id u1))
    (var-set total-requests (+ (var-get total-requests) u1))
    
    (ok request-id)
  )
)

(define-public (respond-to-request (request-id uint) (approve bool) (quantity-approved uint))
  (let
    (
      (request (unwrap! (map-get? resource-requests { request-id: request-id }) err-request-not-found))
      (resource (unwrap! (map-get? resources { resource-id: (get resource-id request) }) err-resource-not-found))
      (allocation-id (var-get next-allocation-id))
    )
    (asserts! (is-eq tx-sender (get provider resource)) err-unauthorized)
    (asserts! (is-eq (get status request) u"pending") (err u112))
    
    (if approve
      (begin
        (asserts! (<= quantity-approved (get quantity-requested request)) (err u113))
        (asserts! (<= quantity-approved (get quantity-available resource)) err-insufficient-quantity)
        
        ;; Approve request
        (map-set resource-requests
          { request-id: request-id }
          (merge request {
            status: u"approved",
            response-block: (some block-height)
          })
        )
        
        ;; Create allocation
        (map-set resource-allocations
          { allocation-id: allocation-id }
          {
            request-id: request-id,
            resource-id: (get resource-id request),
            provider: tx-sender,
            requester: (get requester request),
            quantity-allocated: quantity-approved,
            start-block: block-height,
            end-block: (+ block-height (get duration-blocks request)),
            actual-return-block: none,
            condition-rating: none,
            provider-rating: none,
            requester-rating: none
          }
        )
        
        ;; Update resource availability
        (map-set resources
          { resource-id: (get resource-id request) }
          (merge resource {
            quantity-available: (- (get quantity-available resource) quantity-approved)
          })
        )
        
        ;; Update counters
        (var-set next-allocation-id (+ allocation-id u1))
        (var-set total-allocations (+ (var-get total-allocations) u1))
        (var-set total-active-allocations (+ (var-get total-active-allocations) u1))
        
        (ok allocation-id)
      )
      (begin
        ;; Reject request
        (map-set resource-requests
          { request-id: request-id }
          (merge request {
            status: u"rejected",
            response-block: (some block-height)
          })
        )
        (ok u0)
      )
    )
  )
)

(define-public (return-resource (allocation-id uint) (condition-rating uint))
  (let
    (
      (allocation (unwrap! (map-get? resource-allocations { allocation-id: allocation-id }) (err u114)))
      (resource (unwrap! (map-get? resources { resource-id: (get resource-id allocation) }) err-resource-not-found))
      (request (unwrap! (map-get? resource-requests { request-id: (get request-id allocation) }) err-request-not-found))
    )
    (asserts! (is-eq tx-sender (get requester allocation)) err-unauthorized)
    (asserts! (is-none (get actual-return-block allocation)) (err u115))
    (asserts! (and (>= condition-rating u1) (<= condition-rating u5)) (err u116))
    
    ;; Mark resource as returned
    (map-set resource-allocations
      { allocation-id: allocation-id }
      (merge allocation {
        actual-return-block: (some block-height),
        condition-rating: (some condition-rating)
      })
    )
    
    ;; Update resource availability
    (map-set resources
      { resource-id: (get resource-id allocation) }
      (merge resource {
        quantity-available: (+ (get quantity-available resource) (get quantity-allocated allocation))
      })
    )
    
    ;; Mark request as completed
    (map-set resource-requests
      { request-id: (get request-id allocation) }
      (merge request {
        status: u"completed",
        completion-block: (some block-height)
      })
    )
    
    (var-set total-active-allocations (- (var-get total-active-allocations) u1))
    (ok true)
  )
)

(define-public (rate-interaction (allocation-id uint) (rating uint) (is-provider bool))
  (let
    (
      (allocation (unwrap! (map-get? resource-allocations { allocation-id: allocation-id }) (err u117)))
    )
    (asserts! (and (>= rating u1) (<= rating u5)) (err u118))
    (asserts! (is-some (get actual-return-block allocation)) (err u119))
    
    (if is-provider
      (begin
        (asserts! (is-eq tx-sender (get provider allocation)) err-unauthorized)
        (map-set resource-allocations
          { allocation-id: allocation-id }
          (merge allocation { provider-rating: (some rating) })
        )
      )
      (begin
        (asserts! (is-eq tx-sender (get requester allocation)) err-unauthorized)
        (map-set resource-allocations
          { allocation-id: allocation-id }
          (merge allocation { requester-rating: (some rating) })
        )
      )
    )
    (ok true)
  )
)

(define-public (update-resource-availability (resource-id uint) (new-quantity uint))
  (let
    (
      (resource (unwrap! (map-get? resources { resource-id: resource-id }) err-resource-not-found))
      (allocated (- (get quantity-total resource) (get quantity-available resource)))
    )
    (asserts! (is-eq tx-sender (get provider resource)) err-unauthorized)
    (asserts! (>= new-quantity allocated) (err u120))
    
    (map-set resources
      { resource-id: resource-id }
      (merge resource {
        quantity-total: new-quantity,
        quantity-available: (- new-quantity allocated)
      })
    )
    (ok true)
  )
)

;; Read Functions
(define-read-only (get-resource (resource-id uint))
  (map-get? resources { resource-id: resource-id })
)

(define-read-only (get-resource-request (request-id uint))
  (map-get? resource-requests { request-id: request-id })
)

(define-read-only (get-allocation (allocation-id uint))
  (map-get? resource-allocations { allocation-id: allocation-id })
)

(define-read-only (get-user-resources (user principal))
  (map-get? user-resources { user: user })
)

(define-read-only (get-user-requests (user principal))
  (map-get? user-requests { user: user })
)

(define-read-only (get-resource-stats)
  {
    total-resources: (var-get total-resources),
    total-requests: (var-get total-requests),
    total-allocations: (var-get total-allocations),
    total-active-allocations: (var-get total-active-allocations),
    next-resource-id: (var-get next-resource-id),
    next-request-id: (var-get next-request-id),
    next-allocation-id: (var-get next-allocation-id)
  }
)

