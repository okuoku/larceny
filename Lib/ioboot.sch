; Lib/ioboot.sch
; Larceny -- i/o system boot code
;
; $Id: ioboot.sch,v 1.3 1997/07/07 20:52:12 lth Exp lth $
;
; This code is loaded in the bootstrap heap image immediately following
; the I/O system.  The call to 'initialize-io-system' opens the console
; input and output ports.

;($$trace "ioboot#begin")

(initialize-io-system)

(add-init-procedure! initialize-io-system)  ; when dumped heaps are reloaded
(add-exit-procedure! shutdown-io-system)    ; always

;($$trace "ioboot#end")

; eof
