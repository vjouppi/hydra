;
; hash.a
;
; Timo Rossi, 1992
;
; This computes the multicast hash value for a given ethernet address
;

		xdef	multicast_hash


; Ethernet CRC (FCS)
;
; Polynomial (Autodin II):
;
;  32   26   23   22   16   12   11   10   8    7    5    4    2    1
; X  + X  + X  + X  + X  + X  + X  + X  + X  + X  + X  + X  + X  + X  + 1
;
;
; 33-bit polynomial code:
;
; 3 33222222 22221111 11111100 00000000   bit
; 2 10987654 32109876 54321098 76543210 numbers
;
; 1 00000100 11000001 00011101 10110111 code (hex $104C11DB7)
;
; bit-reversed 32-bit code:
;
; 33222222 22221111 11111100 00000000   bit
; 10987654 32109876 54321098 76543210 numbers
;
; 11101101 10111000 10000011 00100000 code (hex $EDB88320)
;

CRC_POLY	equ	$EDB88320

;
; Multcast Hash value computation (for 8390 NIC)
;
; pointer to 6-byte ethernet address in A0
; 
; This computes the CRC of the address, takes the last 6 bits
; and puts them in the correct order
;
multicast_hash	movem.l	d2/d3/d4,-(sp)
		moveq	#6-1,d4
		moveq	#-1,d1

crc_byte_loop	moveq	#7,d3
		move.b	(a0)+,d0

crc_bit_loop	move.b	d1,d2
		eor.b	d0,d2
		lsr.l	#1,d1
		btst	#0,d2
		beq.s	1$
		eor.l	#CRC_POLY,d1
1$		lsr.b	#1,d0
		dbf	d3,crc_bit_loop

		dbf	d4,crc_byte_loop

		moveq	#0,d0
		moveq	#6-1,d3
bitrev_loop	lsr.b	#1,d1
		roxl.b	#1,d0
		dbf	d3,bitrev_loop

		movem.l	(sp)+,d2/d3/d4
		rts

		end
