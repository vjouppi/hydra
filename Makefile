#
# Makefile for hydra.device
#
# Timo Rossi, 1992
#

.SUFFIXES: .a .o

ASM = a68k
AOPTS = -iai: -iasminc: -iqh0:net/sana2/include -f -q100
LNK = blink

.a.o:
	$(ASM) $(AOPTS) $*.a

OBJ = hydradev.o

hydra.device:	$(OBJ)
	$(LNK) from $(OBJ) to hydra.device

hydradev.o:	hydradev.a hydraboard.i hydradev.i macros.i

