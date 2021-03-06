(require 'experimental/tasking)

(with-tasking 
 (lambda () 
   (spawn (lambda ()
	    (do ((i 0 (+ i 1)))
		((= i 3))
	      (display *current-task*)
	      (if (zero? (random 2)) (yield))))
	  "t1")
   (spawn (lambda () 
	    (do ((i 0 (+ i 1)))
		((= i 3))
	      (display *current-task*)
	      (if (zero? (random 2)) (yield))))
	  "t2")
   (do ((i 0 (+ i 1))) 
       ((= i 3))
     (display *current-task*)
     (yield))))