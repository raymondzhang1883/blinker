; Macros use backslash-prefixed parameters and may expand other macros.
.macro increment dst
    addi \dst, 1
.endm
.macro twice dst
    increment \dst
    increment \dst
.endm
li r4, 40
twice r4
halt
