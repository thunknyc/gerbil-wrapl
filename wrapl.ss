(import :std/actor
        :std/format
        :std/sugar)

(defproto wrapl
  id: wrapl
  event: (req xid req)                  ; ->request 
         (cnl xid)                      ; ->cancel
         (rct xid message)              ; receipt->
         (exc xid message irritants)    ; exception->
         (res xid res)                  ; result->
         (tim xid))                     ; timeout->


(def (process-request @source xid req)
  (try
   (let (res (eval req))
     (!!wrapl.res @source xid res))
   (catch (exc)
     (!!wrapl.exc @source xid exc `(,req)))))

(define max-request-seconds (make-parameter 10))

(def (worker-finished? w)
  (let (s (thread-state w))
    (or (thread-state-abnormally-terminated? s)
        (thread-state-normally-terminated? s))))

(def (monitor-process @source xid worker)
  (let (start-seconds (time->seconds (current-time)))
   (let lp ((now-seconds (time->seconds (current-time))))
     (cond ((worker-finished? worker)
            (eprintf "Request ~S complete\n" xid))
           ((> (- now-seconds start-seconds) (max-request-seconds))
            (thread-terminate! worker)
            (eprintf "Terminated ~S due to timeout\n" xid)
            (!!wrapl.tim @source xid))
           (else
            (thread-sleep! 0.5)
            (lp (time->seconds (current-time))))))))

(def (wrapl-server)
  (try
   (let lp ()
     (<- ((!wrapl.req xid req)
          (let* ((worker
                  (make-thread (cut process-request @source xid req)))
                 (monitor
                  (make-thread (cut monitor-process @source xid worker))))
            (thread-start! worker)
            (thread-start! monitor))
          (!!wrapl.rct @source xid 'accepted)
          (lp))))
   (catch (e)
     (eprintf "An internal exception occurred:\n ~S\n" e))))

(def wrapl-service (spawn wrapl-server))