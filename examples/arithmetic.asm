; Reconstructed example: 64-bit constants and register arithmetic.
; Intended final state: r3 = 42. Not validated against the legacy pipeline.
li r1, 20
li r2, 22
add r3, r1, r2
halt
