#
# Makefile for hydra.device
#
# Timo Rossi, 1992, 1993
#

.SUFFIXES: .a .o

ASM = a68k
AOPTS = -iai: -iasminc: -f -q500
LNK = blink

.a.o:
	$(ASM) $(AOPTS) $*.a


OBJ = hydradev.o hash.o

hydra.device:	$(OBJ)
	$(LNK) from $(OBJ) to hydra.device

hydradev.o:	hydradev.asm include/hydraboard.i include/hydradev.i include/macros.i
	$(ASM) $(AOPTS) hydradev.asm

