#
# Makefile for hydra.device
#
# Timo Rossi, 1992, 1993
#

.SUFFIXES: .asm .o

ASM = a68k
AOPTS = -iai: -iasminc: -f -q500
LNK = blink

.asm.o:
	$(ASM) $(AOPTS) $*.asm


OBJ = hydradev.o hash.o

hydra.device:	$(OBJ)
	$(LNK) from $(OBJ) to hydra.device

hydradev.o:	hydradev.asm include/hydraboard.i include/hydradev.i include/macros.i
	$(ASM) $(AOPTS) hydradev.asm


install:	hydra.device
		copy hydra.device devs:networks

clean:
		delete \#?.o

