;
; hydra.i
;
;
; Hydra Systems Ethernet card definitions
;

HYDRA_MANUF_NUM		equ	2121
HYDRA_PROD_NUM		equ	1

;
; 8390 register offsets (from BoardAddr + $8000)
;

;
; page 0, write
;
NIC_CR		equ	$7fe1
NIC_PSTART	equ	$7fe3
NIC_PSTOP	equ	$7fe5
NIC_BNDRY	equ	$7fe7
NIC_TPSR	equ	$7fe9
NIC_TBCR0	equ	$7feb
NIC_TBCR1	equ	$7fed
NIC_ISR		equ	$7fef
NIC_RSAR0	equ	$7ff1
NIC_RSAR1	equ	$7ff3
NIC_RBCR0	equ	$7ff5
NIC_RBCR1	equ	$7ff7
NIC_RCR		equ	$7ff9
NIC_TCR		equ	$7ffb
NIC_DCR		equ	$7ffd
NIC_IMR		equ	$7fff
;
; page 0, read
;
NIC_CLDA0	equ	$7fe3
NIC_CLDA1	equ	$7fe5
NIC_TSR		equ	$7fe9
NIC_NCR		equ	$7feb
NIC_FIFO	equ	$7fed
NIC_CRDA0	equ	$7ff1
NIC_CRDA1	equ	$7ff3
NIC_RSR		equ	$7ff9
NIC_CNTR0	equ	$7ffb
NIC_CNTR1	equ	$7ffd
NIC_CNTR2	equ	$7fff
;
; page 1
;
NIC_PAR0	equ	$7fe3
NIC_PAR1	equ	$7fe5
NIC_PAR2	equ	$7fe7
NIC_PAR3	equ	$7fe9
NIC_PAR4	equ	$7feb
NIC_PAR5	equ	$7fed
NIC_CURR	equ	$7fef
NIC_MAR0	equ	$7ff1
NIC_MAR1	equ	$7ff3
NIC_MAR2	equ	$7ff5
NIC_MAR3	equ	$7ff7
NIC_MAR4	equ	$7ff9
NIC_MAR5	equ	$7ffb
NIC_MAR6	equ	$7ffd
NIC_MAR7	equ	$7fff

;
; command register bits
;
	BITDEF	CR,STOP,0	; Software reset command
	BITDEF	CR,START,1	; Bit used to activate NIC
	BITDEF	CR,TRANSMIT,2	; Transmit packet command
	BITDEF	CR,RREAD,3	; Remote DMA Read
	BITDEF	CR,RWRITE,4	; Remote DMA Write
	BITDEF	CR,NODMA,5	; No Remote DMA
	BITDEF	CR,PAGE0,6	; Page select bit 0
	BITDEF	CR,PAGE1,7	; Page select bit 1

;
; interrupt status register bits
;
	BITDEF	ISR,PRX,0	; Packet received without errors
	BITDEF	ISR,PTX,1	; Packet transmitted without errors
	BITDEF	ISR,RXE,2	; Receive error
	BITDEF	ISR,TXE,3	; Transmit error
	BITDEF	ISR,OVW,4	; Buffer overwrite warning
	BITDEF	ISR,CNT,5	; Network tally counter overflow
	BITDEF	ISR,RDC,6	; Remote DMA complete
	BITDEF	ISR,RST,7	; Reset status (not an interrupt)

;
; transmit configuration register bits
;
	BITDEF	TCR,CRC,0	; CRC disable
	BITDEF	TCR,LB0,1	; loopback select 0
	BITDEF	TCR,LB1,2	; loopback select 1
	BITDEF	TCR,ATD,3	; auto transmit disable
	BITDEF	TCR,OFST,4	; Collision offset enable

;
; receive configuration register bits
;
	BITDEF	RCR,SEP,0	; Save errored packets
	BITDEF	RCR,AR,1	; Accept runt packets
	BITDEF	RCR,AB,2	; Accept broadcast
	BITDEF	RCR,AM,3	; Accept multicast
	BITDEF	RCR,PRO,4	; Promiscuous mode
	BITDEF	RCR,MON,5	; Monitor mode

;
; data configuration register bits
;
	BITDEF	DCR,WTS,0	; Word transfer select
	BITDEF	DCR,BOS,1	; Byte order select
	BITDEF	DCR,LAS,2	; Long address select
	BITDEF	DCR,LS,3	; Loopback select
	BITDEF	DCR,AR,4	; Auto initialize remote
	BITDEF	DCR,FT0,5	; FIFO threshold 0
	BITDEF	DCR,FT1,6	; FIFO threshold 1

;
; Ethernet address PROM
;
HYDRA_DEFADDR	equ	$7fc0

