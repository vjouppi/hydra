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
; command register bit values
;
	BITDEF	CMD,STOP,0
	BITDEF	CMD,START,1
	BITDEF	CMD,TRANSMIT,2
	BITDEF	CMD,RREAD,3
	BITDEF	CMD,RWRITE,4
	BITDEF	CMD,NODMA,5
	BITDEF	CMD,PAGE0,6
	BITDEF	CMD,PAGE1,7

;
; Ethernet address PROM
;
HYDRA_DEFADDR	equ	$7fc0

