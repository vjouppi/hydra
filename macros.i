;
; macros.i
;
CR		equ	13
LF		equ	10

StrNumber	macro
__XXNumber	set	\1
		ifgt	__XXNumber-99
		dc.b	(__XXNumber/100)+'0'
__XXNumber	set	__XXNumber-((__XXNumber/100)*100)
		dc.b	(__XXNumber/10)+'0'
__XXNumber	set	__XXNumber-((__XXNumber/10)*10)
		endc
		ifgt	__XXNumber-9
		iflt	__XXNumber-100
		dc.b	(__XXNumber/10)+'0'
__XXNumber	set	__XXNumber-((__XXNumber/10)*10)
		endc
		endc
		dc.b	__XXNumber+'0'
		endm

lib		macro
		ifeq	NARG-2
		move.l	a6,-(sp)
		move.l	dev_\1Base(a6),a6
		lib	\2
		move.l	(sp)+,a6
		endc
		ifeq	NARG-1
		jsr	_LVO\1(a6)
		endc
		endm

		ifd	DEBUG

; 
; Debug message (Printf-style, parameters in D0-D7)
; This version does not trash any registers
;
DMSG		macro
		movem.l	d0/d1/a0/a1,-(sp)
		lea	DMSG_S\@(pc),a0
		bsr	DPrintf
		bra.s	DMSG_E\@
DMSG_S\@	dc.b	\1
		dc.b	0
		ds.w	0
DMSG_E\@	movem.l	(sp)+,d0/d1/a0/a1
		endm

		endc	;DEBUG

;
