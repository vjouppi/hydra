;
; macros.i
;
CR		equ	13
LF		equ	10

;
; create an ascii representation of a decimal number
; (used for the version/revision numbers in the device id string)
;
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

;
; library call macro
;
; lib Function		-> jsr _LVOFunction(a6)
;
; lib Library,Function	-> move.l a6,-(sp), move.l dev_LibraryBase(a6),a6
;			   jsr _LVOFunction(a6), move.l (sp)+,a6
;
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

;
; generate bit number equates for bit maks (used with S2EVENT_xxx)
;
bitnum		macro	; symbol,bitmask
xxBitMask	set	1
xxBitNum	set	0
		findbit	\2
\1		equ	xxBitNum
		endm
;
; recursive macro to find bit number corresponding to a bit mask.
;
findbit		macro
		ifeq	xxBitMask&(\1)
xxBitMask	set	xxBitMask*2
xxBitNum	set	xxBitNum+1
		findbit	\1
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
