;; mentorship-coordination
;; Contract for coordinating mentorship relationships in the startup marketplace

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-mentor-not-found (err u101))
(define-constant err-mentorship-not-found (err u102))
(define-constant err-already-mentoring (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-self-mentoring (err u105))

;; Data Maps
(define-map mentors
  { mentor: principal }
  {
    name: (string-utf8 100),
    expertise: (string-utf8 200),
    bio: (string-utf8 500),
    experience-years: uint,
    max-mentees: uint,
    current-mentees: uint,
    registration-block: uint,
    is-active: bool,
    rating: uint,
    total-ratings: uint
  }
)

(define-map mentorship-relationships
  { mentorship-id: uint }
  {
    mentor: principal,
    mentee: principal,
    startup-id: uint,
    start-block: uint,
    end-block: (optional uint),
    status: (string-utf8 20),
    session-count: uint,
    goals: (string-utf8 300),
    progress: (string-utf8 300)
  }
)

(define-map mentorship-sessions
  { session-id: uint }
  {
    mentorship-id: uint,
    session-date: uint,
    duration-minutes: uint,
    topics: (string-utf8 200),
    notes: (string-utf8 500),
    mentor-rating: (optional uint),
    mentee-rating: (optional uint)
  }
)

(define-map user-mentorships
  { user: principal }
  { mentorship-ids: (list 20 uint) }
)

;; Data Variables
(define-data-var next-mentorship-id uint u1)
(define-data-var next-session-id uint u1)
(define-data-var total-mentorships uint u0)
(define-data-var total-active-mentorships uint u0)
(define-data-var total-sessions uint u0)

;; Private Functions
(define-private (is-valid-status (status (string-utf8 20)))
  (or (is-eq status u"pending")
      (is-eq status u"active")
      (is-eq status u"completed")
      (is-eq status u"cancelled"))
)

;; Public Functions
(define-public (register-mentor
    (name (string-utf8 100))
    (expertise (string-utf8 200))
    (bio (string-utf8 500))
    (experience-years uint)
    (max-mentees uint)
  )
  (begin
    (map-set mentors
      { mentor: tx-sender }
      {
        name: name,
        expertise: expertise,
        bio: bio,
        experience-years: experience-years,
        max-mentees: max-mentees,
        current-mentees: u0,
        registration-block: block-height,
        is-active: true,
        rating: u0,
        total-ratings: u0
      }
    )
    (ok true)
  )
)

(define-public (request-mentorship
    (mentor-principal principal)
    (startup-id uint)
    (goals (string-utf8 300))
  )
  (let
    (
      (mentorship-id (var-get next-mentorship-id))
      (mentor-data (unwrap! (map-get? mentors { mentor: mentor-principal }) err-mentor-not-found))
      (current-mentorships (default-to { mentorship-ids: (list) }
        (map-get? user-mentorships { user: tx-sender })))
    )
    (asserts! (not (is-eq tx-sender mentor-principal)) err-self-mentoring)
    (asserts! (< (get current-mentees mentor-data) (get max-mentees mentor-data)) (err u106))
    (asserts! (get is-active mentor-data) (err u107))
    
    ;; Create mentorship relationship
    (map-set mentorship-relationships
      { mentorship-id: mentorship-id }
      {
        mentor: mentor-principal,
        mentee: tx-sender,
        startup-id: startup-id,
        start-block: block-height,
        end-block: none,
        status: u"pending",
        session-count: u0,
        goals: goals,
        progress: u""
      }
    )
    
    ;; Update user's mentorship list
    (map-set user-mentorships
      { user: tx-sender }
      { mentorship-ids: (unwrap! (as-max-len?
          (append (get mentorship-ids current-mentorships) mentorship-id) u20)
        (err u108)) }
    )
    
    ;; Update mentor's mentorship list
    (let
      (
        (mentor-mentorships (default-to { mentorship-ids: (list) }
          (map-get? user-mentorships { user: mentor-principal })))
      )
      (map-set user-mentorships
        { user: mentor-principal }
        { mentorship-ids: (unwrap! (as-max-len?
            (append (get mentorship-ids mentor-mentorships) mentorship-id) u20)
          (err u109)) }
      )
    )
    
    ;; Update counters
    (var-set next-mentorship-id (+ mentorship-id u1))
    (var-set total-mentorships (+ (var-get total-mentorships) u1))
    
    (ok mentorship-id)
  )
)

(define-public (respond-to-mentorship (mentorship-id uint) (accept bool))
  (let
    (
      (mentorship (unwrap! (map-get? mentorship-relationships { mentorship-id: mentorship-id }) err-mentorship-not-found))
      (mentor-data (unwrap! (map-get? mentors { mentor: tx-sender }) err-mentor-not-found))
    )
    (asserts! (is-eq tx-sender (get mentor mentorship)) err-unauthorized)
    (asserts! (is-eq (get status mentorship) u"pending") (err u110))
    
    (if accept
      (begin
        ;; Accept mentorship
        (map-set mentorship-relationships
          { mentorship-id: mentorship-id }
          (merge mentorship { status: u"active" })
        )
        
        ;; Update mentor's current mentees count
        (map-set mentors
          { mentor: tx-sender }
          (merge mentor-data { current-mentees: (+ (get current-mentees mentor-data) u1) })
        )
        
        (var-set total-active-mentorships (+ (var-get total-active-mentorships) u1))
        (ok true)
      )
      (begin
        ;; Reject mentorship
        (map-set mentorship-relationships
          { mentorship-id: mentorship-id }
          (merge mentorship { status: u"cancelled", end-block: (some block-height) })
        )
        (ok false)
      )
    )
  )
)

(define-public (log-session
    (mentorship-id uint)
    (duration-minutes uint)
    (topics (string-utf8 200))
    (notes (string-utf8 500))
  )
  (let
    (
      (session-id (var-get next-session-id))
      (mentorship (unwrap! (map-get? mentorship-relationships { mentorship-id: mentorship-id }) err-mentorship-not-found))
    )
    (asserts! (or (is-eq tx-sender (get mentor mentorship))
                  (is-eq tx-sender (get mentee mentorship))) err-unauthorized)
    (asserts! (is-eq (get status mentorship) u"active") (err u111))
    
    ;; Log session
    (map-set mentorship-sessions
      { session-id: session-id }
      {
        mentorship-id: mentorship-id,
        session-date: block-height,
        duration-minutes: duration-minutes,
        topics: topics,
        notes: notes,
        mentor-rating: none,
        mentee-rating: none
      }
    )
    
    ;; Update session count
    (map-set mentorship-relationships
      { mentorship-id: mentorship-id }
      (merge mentorship { session-count: (+ (get session-count mentorship) u1) })
    )
    
    ;; Update counters
    (var-set next-session-id (+ session-id u1))
    (var-set total-sessions (+ (var-get total-sessions) u1))
    
    (ok session-id)
  )
)

(define-public (complete-mentorship (mentorship-id uint) (final-progress (string-utf8 300)))
  (let
    (
      (mentorship (unwrap! (map-get? mentorship-relationships { mentorship-id: mentorship-id }) err-mentorship-not-found))
      (mentor-data (unwrap! (map-get? mentors { mentor: (get mentor mentorship) }) err-mentor-not-found))
    )
    (asserts! (or (is-eq tx-sender (get mentor mentorship))
                  (is-eq tx-sender (get mentee mentorship))) err-unauthorized)
    (asserts! (is-eq (get status mentorship) u"active") (err u112))
    
    ;; Complete mentorship
    (map-set mentorship-relationships
      { mentorship-id: mentorship-id }
      (merge mentorship {
        status: u"completed",
        end-block: (some block-height),
        progress: final-progress
      })
    )
    
    ;; Update mentor's current mentees count
    (map-set mentors
      { mentor: (get mentor mentorship) }
      (merge mentor-data { current-mentees: (- (get current-mentees mentor-data) u1) })
    )
    
    (var-set total-active-mentorships (- (var-get total-active-mentorships) u1))
    (ok true)
  )
)

(define-public (rate-mentor (mentorship-id uint) (rating uint))
  (let
    (
      (mentorship (unwrap! (map-get? mentorship-relationships { mentorship-id: mentorship-id }) err-mentorship-not-found))
      (mentor-data (unwrap! (map-get? mentors { mentor: (get mentor mentorship) }) err-mentor-not-found))
      (current-rating (get rating mentor-data))
      (total-ratings (get total-ratings mentor-data))
      (new-total-ratings (+ total-ratings u1))
      (new-rating (/ (+ (* current-rating total-ratings) rating) new-total-ratings))
    )
    (asserts! (is-eq tx-sender (get mentee mentorship)) err-unauthorized)
    (asserts! (is-eq (get status mentorship) u"completed") (err u113))
    (asserts! (and (>= rating u1) (<= rating u5)) (err u114))
    
    ;; Update mentor's rating
    (map-set mentors
      { mentor: (get mentor mentorship) }
      (merge mentor-data {
        rating: new-rating,
        total-ratings: new-total-ratings
      })
    )
    
    (ok true)
  )
)

;; Read Functions
(define-read-only (get-mentor (mentor-principal principal))
  (map-get? mentors { mentor: mentor-principal })
)

(define-read-only (get-mentorship (mentorship-id uint))
  (map-get? mentorship-relationships { mentorship-id: mentorship-id })
)

(define-read-only (get-session (session-id uint))
  (map-get? mentorship-sessions { session-id: session-id })
)

(define-read-only (get-user-mentorships (user principal))
  (map-get? user-mentorships { user: user })
)

(define-read-only (get-mentorship-stats)
  {
    total-mentorships: (var-get total-mentorships),
    total-active-mentorships: (var-get total-active-mentorships),
    total-sessions: (var-get total-sessions),
    next-mentorship-id: (var-get next-mentorship-id),
    next-session-id: (var-get next-session-id)
  }
)

