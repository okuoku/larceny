; Test suite for SRFI-60
;
; $Id$

(import (rnrs base)
        (rnrs io simple)
        (srfi :60 integer-bits))

(define (writeln . xs)
  (for-each display xs)
  (newline))

(define (fail token . more)
  (writeln "Error: test failed: " token)
  #f)

(or (string=? (number->string (logand #b1100 #b1010) 2)
       "1000")
    (fail 'logand))

(or (string=? (number->string (logior #b1100 #b1010) 2)
              "1110")
    (fail 'logior))

(or (string=? (number->string (logxor #b1100 #b1010) 2)
              "110")
    (fail 'logxor))

(or (string=? (number->string (lognot #b10000000) 2)
              "-10000001")
    (fail 'lognot-1))

(or (string=? (number->string (lognot #b0) 2)
              "-1")
    (fail 'lognot-2))

(or (string=? (number->string (bitwise-if #b11110000 #b10111011 #b00100010) 2)
              "10110010")
    (fail 'bitwise-if))

(or (string=? (number->string
               (bitwise-merge #b11110000 #b10111011 #b00100010)
               2)
              "10110010")
    (fail 'bitwise-merge))

(or (eq? (logtest #b0100 #b1011) #f)
    (fail 'logtest))

(or (eq? (any-bits-set? #b0100 #b0111) #t)
    (fail 'any-bits-set?))

(or (= (logcount #b10101010) 4)
    (fail 'logcount-1))

(or (= (logcount 0) 0)
    (fail 'logcount-2))

(or (= (logcount -2) 1)
    (fail 'logcount))

(or (= (integer-length #b10101010) 8)
    (fail 'integer-length-1))

(or (= (integer-length 0) 0)
    (fail 'integer-length-2))

(or (= (integer-length #b1111) 4)
    (fail 'integer-length-3))

(or (equal? (map log2-binary-factors
                 '(0 -1 -2 -3 -4 -5 -6 -7 -8 -9 -10 -11 -12 -13 -14 -15 -16))
            '(-1 0 1 0 2 0 1 0 3 0 1 0 2 0 1 0 4))
    (fail 'log2-binary-factors-1))

(or (equal? (map log2-binary-factors
                 '(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16))
            '(-1 0 1 0 2 0 1 0 3 0 1 0 2 0 1 0 4))
    (fail 'log2-binary-factors-2))

(or (equal? (map logbit?
                 '(0 1 2 3 4)
                 '(#b1101 #b1101 #b1101 #b1101 #b1101))
            '(#t #f #t #t #f))
    (fail 'logbit?))

(or (equal? (map bit-set?
                 '(0 1 2 3 4)
                 '(#b1101 #b1101 #b1101 #b1101 #b1101))
            '(#t #f #t #t #f))
    (fail 'bit-set?))

(or (string=? (number->string (copy-bit 0 0 #t) 2) "1")
    (fail 'copy-bit-1))

(or (string=? (number->string (copy-bit 2 0 #t) 2) "100")
    (fail 'copy-bit-2))

(or (string=? (number->string (copy-bit 2 #b1111 #f) 2) "1011")
    (fail 'copy-bit-3))

(or (string=? (number->string (bit-field #b1101101010 0 4) 2)
              "1010")
    (fail 'bit-field-1))

(or (string=? (number->string (bit-field #b1101101010 4 9) 2)
              "10110")
    (fail 'bit-field-2))

(or (string=? (number->string (copy-bit-field #b1101101010 0 0 4) 2)
              "1101100000")
    (fail 'copy-bit-field-1))

(or (string=? (number->string (copy-bit-field #b1101101010 -1 0 4) 2)
              "1101101111")
    (fail 'copy-bit-field-2))

(or (string=? (number->string (copy-bit-field #b110100100010000 -1 5 9) 2)
              "110100111110000")
    (fail 'copy-bit-field-3))

(or (string=? (number->string (ash #b1 3) 2)
              "1000")
    (fail 'ash-1))

(or (string=? (number->string (ash #b1010 -1) 2)
              "101")
    (fail 'ash-2))

(or (string=? (number->string (arithmetic-shift #b1 3) 2)
              "1000")
    (fail 'arithmetic-shift-1))

(or (string=? (number->string (arithmetic-shift #b1010 -1) 2)
              "101")
    (fail 'arithmetic-shift-2))

(or (string=? (number->string (rotate-bit-field #b0100 3 0 4) 2)
              "10")
    (fail 'rotate-bit-field-1))

(or (string=? (number->string (rotate-bit-field #b0100 -1 0 4) 2)
              "10")
    (fail 'rotate-bit-field-2))

(or (string=? (number->string (rotate-bit-field #b110100100010000 -1 5 9) 2)
              "110100010010000")
    (fail 'rotate-bit-field-3))

(or (string=? (number->string (rotate-bit-field #b110100100010000 1 5 9) 2)
              "110100000110000")
    (fail 'rotate-bit-field-4))

(or (string=? (number->string (reverse-bit-field #xa7 0 8) 16)
              "e5")
    (fail 'reverse-bit-field))

(or (equal? (integer->list #b110101001000)
            '(#t #t #f #t #f #t #f #f #t #f #f #f))
    (fail 'integer->list-1))

(or (equal? (integer->list #b110101001000 8)
            '(#f #t #f #f #t #f #f #f))
    (fail 'integer->list-2))

(or (equal? (integer->list #b110101001000 16)
            '(#f #f #f #f #t #t #f #t #f #t #f #f #t #f #f #f))
    (fail 'integer->list-3))

(or (and (equal? #b110101001000
                 (list->integer '(#t #t #f #t #f #t #f #f #t #f #f #f)))
         (equal? #b110101001000
                 (list->integer
                  '(#f #f #f #f#t #t #f #t #f #t #f #f #t #f #f #f))))
    (fail 'list->integer))

(or (and (equal? #b110101001000
                 (booleans->integer #t #t #f #t #f #t #f #f #t #f #f #f))
         (equal? #b110101001000
                 (booleans->integer
                  #f #f #f #f#t #t #f #t #f #t #f #f #t #f #f #f)))
    (fail 'booleans->integer))

(writeln "Done.")
