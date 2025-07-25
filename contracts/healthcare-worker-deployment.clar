;; Healthcare Worker Deployment Contract
;; Manages healthcare personnel assignments during health emergencies

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-INPUT (err u301))
(define-constant ERR-WORKER-NOT-FOUND (err u302))
(define-constant ERR-DEPLOYMENT-NOT-FOUND (err u303))
(define-constant ERR-WORKER-UNAVAILABLE (err u304))

;; Data Variables
(define-data-var deployment-counter uint u0)
(define-data-var shift-counter uint u0)

;; Data Maps
(define-map healthcare-workers
  { worker-id: principal }
  {
    name: (string-ascii 100),
    specialization: (string-ascii 50),
    experience-years: uint,
    current-location: (string-ascii 100),
    availability-status: (string-ascii 20),
    max-hours-per-week: uint,
    current-hours-this-week: uint,
    emergency-contact: (string-ascii 100)
  }
)

(define-map emergency-zones
  { zone-id: (string-ascii 50) }
  {
    name: (string-ascii 100),
    location: (string-ascii 100),
    severity-level: uint,
    required-workers: uint,
    deployed-workers: uint,
    specializations-needed: (list 10 (string-ascii 50))
  }
)

(define-map deployments
  { deployment-id: uint }
  {
    worker-id: principal,
    zone-id: (string-ascii 50),
    start-time: uint,
    end-time: uint,
    role: (string-ascii 50),
    status: (string-ascii 20),
    deployed-by: principal
  }
)

(define-map work-shifts
  { shift-id: uint }
  {
    deployment-id: uint,
    worker-id: principal,
    shift-start: uint,
    shift-end: uint,
    hours-worked: uint,
    performance-rating: uint
  }
)

(define-map authorized-coordinators
  { coordinator: principal }
  { authorized: bool }
)

;; Authorization Functions
(define-public (authorize-coordinator (coordinator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-coordinators { coordinator: coordinator } { authorized: true }))
  )
)

(define-public (register-worker (worker-id principal) (name (string-ascii 100)) (specialization (string-ascii 50)) (experience-years uint) (max-hours uint))
  (begin
    (asserts! (> experience-years u0) ERR-INVALID-INPUT)
    (asserts! (> max-hours u0) ERR-INVALID-INPUT)
    (asserts! (<= max-hours u168) ERR-INVALID-INPUT) ;; Max 168 hours per week

    (ok (map-set healthcare-workers
      { worker-id: worker-id }
      {
        name: name,
        specialization: specialization,
        experience-years: experience-years,
        current-location: "available",
        availability-status: "available",
        max-hours-per-week: max-hours,
        current-hours-this-week: u0,
        emergency-contact: ""
      }
    ))
  )
)

(define-public (create-emergency-zone (zone-id (string-ascii 50)) (name (string-ascii 100)) (location (string-ascii 100)) (severity-level uint) (required-workers uint))
  (let
    (
      (coordinator-auth (default-to { authorized: false } (map-get? authorized-coordinators { coordinator: tx-sender })))
    )
    (asserts! (get authorized coordinator-auth) ERR-NOT-AUTHORIZED)
    (asserts! (> required-workers u0) ERR-INVALID-INPUT)
    (asserts! (< severity-level u6) ERR-INVALID-INPUT)

    (ok (map-set emergency-zones
      { zone-id: zone-id }
      {
        name: name,
        location: location,
        severity-level: severity-level,
        required-workers: required-workers,
        deployed-workers: u0,
        specializations-needed: (list)
      }
    ))
  )
)

;; Deployment Functions
(define-public (deploy-worker (worker-id principal) (zone-id (string-ascii 50)) (role (string-ascii 50)) (duration-hours uint))
  (let
    (
      (worker (unwrap! (map-get? healthcare-workers { worker-id: worker-id }) ERR-WORKER-NOT-FOUND))
      (zone (unwrap! (map-get? emergency-zones { zone-id: zone-id }) ERR-DEPLOYMENT-NOT-FOUND))
      (deployment-id (+ (var-get deployment-counter) u1))
      (coordinator-auth (default-to { authorized: false } (map-get? authorized-coordinators { coordinator: tx-sender })))
    )
    (asserts! (get authorized coordinator-auth) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get availability-status worker) "available") ERR-WORKER-UNAVAILABLE)
    (asserts! (> duration-hours u0) ERR-INVALID-INPUT)
    (asserts! (<= (+ (get current-hours-this-week worker) duration-hours) (get max-hours-per-week worker)) ERR-INVALID-INPUT)

    ;; Create deployment record
    (map-set deployments
      { deployment-id: deployment-id }
      {
        worker-id: worker-id,
        zone-id: zone-id,
        start-time: block-height,
        end-time: (+ block-height duration-hours),
        role: role,
        status: "active",
        deployed-by: tx-sender
      }
    )

    ;; Update worker status
    (map-set healthcare-workers
      { worker-id: worker-id }
      (merge worker {
        availability-status: "deployed",
        current-location: zone-id,
        current-hours-this-week: (+ (get current-hours-this-week worker) duration-hours)
      })
    )

    ;; Update zone statistics
    (map-set emergency-zones
      { zone-id: zone-id }
      (merge zone {
        deployed-workers: (+ (get deployed-workers zone) u1)
      })
    )

    (var-set deployment-counter deployment-id)
    (ok deployment-id)
  )
)

(define-public (complete-deployment (deployment-id uint))
  (let
    (
      (deployment (unwrap! (map-get? deployments { deployment-id: deployment-id }) ERR-DEPLOYMENT-NOT-FOUND))
      (worker-id (get worker-id deployment))
      (zone-id (get zone-id deployment))
      (worker (unwrap! (map-get? healthcare-workers { worker-id: worker-id }) ERR-WORKER-NOT-FOUND))
      (zone (unwrap! (map-get? emergency-zones { zone-id: zone-id }) ERR-DEPLOYMENT-NOT-FOUND))
      (coordinator-auth (default-to { authorized: false } (map-get? authorized-coordinators { coordinator: tx-sender })))
    )
    (asserts! (get authorized coordinator-auth) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status deployment) "active") ERR-INVALID-INPUT)

    ;; Update deployment status
    (map-set deployments
      { deployment-id: deployment-id }
      (merge deployment { status: "completed" })
    )

    ;; Update worker availability
    (map-set healthcare-workers
      { worker-id: worker-id }
      (merge worker {
        availability-status: "available",
        current-location: "available"
      })
    )

    ;; Update zone statistics
    (map-set emergency-zones
      { zone-id: zone-id }
      (merge zone {
        deployed-workers: (- (get deployed-workers zone) u1)
      })
    )

    (ok deployment-id)
  )
)

(define-public (log-work-shift (deployment-id uint) (hours-worked uint) (performance-rating uint))
  (let
    (
      (deployment (unwrap! (map-get? deployments { deployment-id: deployment-id }) ERR-DEPLOYMENT-NOT-FOUND))
      (shift-id (+ (var-get shift-counter) u1))
    )
    (asserts! (is-eq tx-sender (get worker-id deployment)) ERR-NOT-AUTHORIZED)
    (asserts! (> hours-worked u0) ERR-INVALID-INPUT)
    (asserts! (<= performance-rating u5) ERR-INVALID-INPUT)

    (map-set work-shifts
      { shift-id: shift-id }
      {
        deployment-id: deployment-id,
        worker-id: (get worker-id deployment),
        shift-start: block-height,
        shift-end: (+ block-height hours-worked),
        hours-worked: hours-worked,
        performance-rating: performance-rating
      }
    )

    (var-set shift-counter shift-id)
    (ok shift-id)
  )
)

;; Worker Management Functions
(define-public (update-worker-availability (worker-id principal) (status (string-ascii 20)))
  (let
    (
      (worker (unwrap! (map-get? healthcare-workers { worker-id: worker-id }) ERR-WORKER-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender worker-id) ERR-NOT-AUTHORIZED)

    (ok (map-set healthcare-workers
      { worker-id: worker-id }
      (merge worker { availability-status: status })
    ))
  )
)

(define-public (reset-weekly-hours)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    ;; In a real implementation, this would iterate through all workers
    ;; For now, it's a placeholder for the weekly reset functionality
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-worker (worker-id principal))
  (map-get? healthcare-workers { worker-id: worker-id })
)

(define-read-only (get-emergency-zone (zone-id (string-ascii 50)))
  (map-get? emergency-zones { zone-id: zone-id })
)

(define-read-only (get-deployment (deployment-id uint))
  (map-get? deployments { deployment-id: deployment-id })
)

(define-read-only (get-work-shift (shift-id uint))
  (map-get? work-shifts { shift-id: shift-id })
)

(define-read-only (get-deployment-counter)
  (var-get deployment-counter)
)

(define-read-only (get-shift-counter)
  (var-get shift-counter)
)

(define-read-only (is-worker-available (worker-id principal))
  (match (map-get? healthcare-workers { worker-id: worker-id })
    worker (is-eq (get availability-status worker) "available")
    false
  )
)

;; Emergency Functions
(define-public (emergency-deploy-all-available (zone-id (string-ascii 50)))
  (let
    (
      (coordinator-auth (default-to { authorized: false } (map-get? authorized-coordinators { coordinator: tx-sender })))
    )
    (asserts! (get authorized coordinator-auth) ERR-NOT-AUTHORIZED)
    ;; In a real implementation, this would iterate through all available workers
    ;; and deploy them to the emergency zone
    (ok true)
  )
)
