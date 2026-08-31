; load destination, base, offset; store base, source, offset.
; Data at 0x1000 is below the instruction region at 0x2000.
li r1, 0x1000
li r2, 42
store r1, r2, 0
load r3, r1, 0
halt
