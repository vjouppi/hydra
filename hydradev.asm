;+asm
;add module "hash.o"
;do
;*
;;;;copy hydradev devs:networks/hydra.device
;
; hydradev.a  --  sanaII device driver for Hydra Systems ethernet card
;
; Timo Rossi, 1992-1994
;

;
; notes:
;	- all assembler symbol names in sana2.i are in UPPER case
;	- WireError is ULONG
;	- The C-include file devices/sana2.h (revision 1.10)
;	  has an error in the Sana2DeviceStats structure definition
;	  - SoftMisses-field is missing
;	(SoftMisses has been replaced by an unused field in newer includes)
;
;	- packet types <= 1500 are ieee802.3 length fields
;
; (Disable/Enable should probably be replaced with routines that only
; disable/enable the PORTS/ExtLevel2 interrupt)
;

;
; 1.9 -- 1992-11-27
;	- added buffer overflow check (untested)
;	- trying to fix Abort_All
; 1.10 - 1992-11-29
;	- added S2_GETSPECIALSTATS
; 1.11	- fixed AbortIO()
;	- added S2_ONEVENT and event handling
;	- fixed expunge
; 1.14	- added type tracking
; 1.15	- added promiscuous mode
; 1.16	- small changes (event handling)
;
; 1.17  - now 'Packets Received' global stat is incremented also for dropped
;	  packets.
;
; 1.18  - IEEE802.3 send sets packet length field correctly
;       - added collision count special stat (not sure if it works...)
;	(also added tally counter interrupt, but the counter values
;	are not used for anything yet...)
;
; 1.19	- CIA accesses between NIC accesses to keep the time between
;	  chip selects long enough.
;
; 1.20  - NIC access delays done with a macro
;
; 1.22  - FIFO treshold lowered from 8+2 to 4+2 words by jm
; 1.23  - Copyright message changed.
;
; 1.24	- fixed RAM test routine (still not perfect... no shadow checking)
;
; 1.25	- fixed dev_Open to work with non-zero units (not tested...)
;	- also fixed IOS2_DATALENGTH setting with received raw packets
;
; 1.26	- Now interrupt server is added in S2_CONFIGINTERFACE.
;	  (previously there was a possibility that interrupt server
;	  could be left in free memory...)
;
; 1.27	- Modified card memory check routine. Now should be more reliable.
;
; 1.28  - testing... more NIC_Delays and memory copy as words
;
; 1.29  - fixed queued transmit. changed copy routines to copy longwords again.
; 1.30ß-- 940216 (JM)
;	- now always sets RAM size to 16K (didn't help)
;
; 1.31 -- 940217 (JM)
;	- RAM size check finally, definately fixed by JM (was using a 16-bit
;	  signed index which caused the test to fail with a 64Kb buffer)
;	- Board RAM now properly accessed in interrupt routine (bug located
;	  by TR)
;
; 1.32 -- 940217 (JM)
;	- Two bugs fixed (was using 16-bit signed arithmetic, changed to 32-bit)
;
; 1.33 -- 940217 (JM)
;	- Yet another bug fix (was using a signed branch in a bad place :-)
;
; 1.34 -- skipped (JM version which saves register when calling the
;	  callback routines)
;
; 1.35 -- trying to add PacketFilter support...
; 1.36 -- trying to add multiple read queues
; 1.37 -- fixed device name (???)
;
; 1.38 -- added Disable()/Enable() in CookieList handling
;	  in Open() and Close() routines.
;	  Fixed a bug in find_rec_ioreq_loop, it jumped to orphan_packet,
;	  where it should jump to find_rec_ioreq_cookie_next...
;
; 1.39 -- fixed multiple read queues to work the way they should...
;
; 1.40 -- fixed promiscuous mode flag bit check in close routine
;	  fixed collision statistics (but still not sure if it really works)
;
; 1.41 -- fixed interrupt name
;	  (really strange that it didn't get fixed earlier...)
;
; 1.42 -- fixed orphan packet/normal packet handling interaction
;
; 1.43 -- trying to debug problems with Enlan-DFS ...
;	  (and found a bug in Enlan...)
;
; 1.44 -- now uses Enqueue to queue iorequests (uses priority)
;
;


;
; if DEBUG is defined, the device writes a lot of debugging
; info to the serial port (with RawPutChar())
;
;
;DEBUG		set	1

;;;
		nolist

		include	'exec/types.i'
		include	'exec/resident.i'
		include	'exec/interrupts.i'
		include	'exec/devices.i'
		include	'exec/io.i'
		include	'exec/errors.i'
		include	'exec/memory.i'
		include	'exec/initializers.i'
		include	'devices/timer.i'
		include	'utility/tagitem.i'
		include	'utility/hooks.i'
		include	'libraries/configvars.i'
		include	'hardware/intbits.i'
		include	'hardware/cia.i'

		include	'include/offsets.i'

		include	'devices/sana2.i'
		include	'devices/sana2specialstats.i'

		list

		include	'include/hydraboard.i'
		include	'include/hydradev.i'

		include	'include/macros.i'
;
Ciaa		equ	$bfe001
;

;
; Delay between NIC (Network Interface Controller) accesses. Done by
; accessing a CIA chip.
;
NIC_Delay	macro
		tst.b	Ciaa+ciapra
		tst.b	Ciaa+ciapra
		endm

;
; bit numbers for S2EVENT_xxx
;
		bitnum	S2EVENTB_ERROR,S2EVENT_ERROR
		bitnum	S2EVENTB_TX,S2EVENT_TX
		bitnum	S2EVENTB_RX,S2EVENT_RX
		bitnum	S2EVENTB_ONLINE,S2EVENT_ONLINE
		bitnum	S2EVENTB_OFFLINE,S2EVENT_OFFLINE
		bitnum	S2EVENTB_BUFF,S2EVENT_BUFF
		bitnum	S2EVENTB_HARDWARE,S2EVENT_HARDWARE
		bitnum	S2EVENTB_SOFTWARE,S2EVENT_SOFTWARE

;
		xref	multicast_hash		;exported from hash.a


DEV_VERSION	equ	1
DEV_REVISION	equ	44

;
; start of the first hunk of the device file
; if someone tries to run this from CLI/Shell, return an error
;
dev_SafeExit	moveq	#-1,d0
		rts

dev_romtag	dc.w	RTC_MATCHWORD	;rt_MatchWord
		dc.l	dev_romtag	;rt_MatchTag
		dc.l	dev_endskip	;rt_EndSkip
		dc.b	RTF_AUTOINIT	;rt_Flags
		dc.b	DEV_VERSION	;rt_Version
		dc.b	NT_DEVICE	;rt_Type
		dc.b	0		;rt_Pri
		dc.l	dev_name
		dc.l	dev_idstring
		dc.l	dev_init

dev_name	dc.b	'hydra.device',0

		dc.b	'$VER: '
dev_idstring	dc.b	'hydradev '
		StrNumber DEV_VERSION
		dc.b	'.'
		StrNumber DEV_REVISION
		dc.b	' (01.06.95)',CR,LF,0

copyright_msg	dc.b	'Copyright © 1992-1994 by JMP-Electronics / Bits & Chips, Finland',CR,LF,0

expansion_name	dc.b	'expansion.library',0
intuition_name	dc.b	'intuition.library',0

		ds.w	0	;word align

;
; because the RTF_AUTOINIT flag in the RomTag structure was set
; RT_INIT points to this table of parameters for MakeLibrary()
;
dev_init	dc.l	dev_DataSize
		dc.l	dev_FuncInit
		dc.l	dev_StructInit
		dc.l	dev_InitRoutine

devfunc	macro
		dc.w	\1-dev_FuncInit
		endm

;
; device function init
;
dev_FuncInit	dc.w	-1
; standard library routines
		devfunc	dev_Open
		devfunc	dev_Close
		devfunc	dev_Expunge
		devfunc	dev_Reserved
; standard device routines
		devfunc	dev_BeginIO
		devfunc	dev_AbortIO
		dc.w	-1

;
; device structure init
;
dev_StructInit	INITBYTE LN_TYPE,NT_DEVICE
		INITLONG LN_NAME,dev_name
		INITLONG LIB_IDSTRING,dev_idstring
		INITBYTE LIB_FLAGS,LIBF_CHANGED!LIBF_SUMUSED
		INITLONG LIB_VERSION,(DEV_VERSION<<16)+DEV_REVISION
		dc.l	0

;
; Device initialization routine
;
; Entry:
;   d0  -  device base
;   a6  -  execbase
;
; Return:
;   d0  -  device base if successfull, zero if not
;
dev_InitRoutine	move.l	a4,-(sp)

		ifd	DEBUG
		DMSG	<'Device init entry (device = $%lx)',LF>
		endc

		move.l	d0,a4			;get device base in a4
		move.l	a0,dev_SegList(a4)	;save seglist for expunge
		move.l	a6,dev_SysBase(a4)

		lea	expansion_name(pc),a1
		moveq	#0,d0
		lib	OpenLibrary
		move.l	d0,dev_ExpansionBase(a4)
		beq.b	initfail1

		lea	intuition_name(pc),a1
		moveq	#0,d0
		lib	OpenLibrary
		move.l	d0,dev_IntuitionBase(a4)
		beq.b	initfail2

		move.l	a4,d0
		move.l	(sp)+,a4
		rts

initfail2	move.l	dev_ExpansionBase(a4),a1
		lib	CloseLibrary

initfail1
		ifd	DEBUG
		DMSG	<'Device init fail',LF>
		endc

		move.l	(sp)+,a4

dev_Reserved	moveq	#0,d0
		rts

;
; Device open routine
;
; Entry:
;   a6  -  device base
;   a1  -  io request
;   d0  -  unit number
;   d1  -  flags
;
; Return:
;   d0  -  zero if successfull, error code if failure
;
dev_Open	movem.l	d2/d3/a2/a3,-(sp)

		ifd	DEBUG
		DMSG	<'Device open entry (unit = %ld, flags = $%lx)',LF>
		endc

		move.l	d1,d3
		move.l	a1,a2
		moveq	#NUM_UNITS,d2
		cmp.l	d2,d0
		bcc	open_fail
		move.l	d0,d2
		lsl.l	#2,d2
		move.l	dev_UnitTable(a6,d2.l),d0
		bne.b	unit_ok

		move.l	d2,d0
		lsr.l	#2,d0
		bsr	Initialize_Unit
		tst.l	d0
		beq	open_fail

		move.l	d0,dev_UnitTable(a6,d2.l)

unit_ok		move.l	d0,a3
		tst.w	UNIT_OPENCNT(a3)
		beq.b	excl_ok1
		btst	#SANA2OPB_MINE,d3
		bne	excl_open_fail

excl_ok1	btst	#UNITB_EXCLUSIVE,UNIT_FLAGS(a3)
		bne	excl_open_fail

		btst	#SANA2OPB_MINE,d3
		beq.b	excl_ok2
		bset	#UNITB_EXCLUSIVE,UNIT_FLAGS(a3)

excl_ok2	move.l	IOS2_BUFFERMANAGEMENT(a2),a1
		bsr	InitBuffManagement
		move.l	d0,IOS2_BUFFERMANAGEMENT(a2)
		beq	open_fail
		move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
		move.l	d0,a1
;
; Add magic cookie to the cookie list
; Remember to Disable() when accessing the cookie list
;
		lib	Disable
		lea	du_CookieList(a3),a0
		lib	AddHead
		lib	Enable
		move.l	(sp)+,a6

		btst	#SANA2OPB_PROM,d3
		beq.b	open_ok1
;
; open in promiscuous mode
; use cookie_Flags so we remember to decrement PromCount in close
;
		addq.w	#1,du_PromCount(a3)
		move.l	IOS2_BUFFERMANAGEMENT(a2),a0
		bset	#BFMB_PROM,cookie_Flags(a0)
		move.l	du_BoardAddr1(a3),a0
		move.b	#RCRF_PRO!RCRF_AB!RCRF_AM,NIC_RCR(a0)

		ifd	DEBUG
		DMSG	<'Enabled promiscuous mode',LF>
		endc

open_ok1	move.l	a3,IO_UNIT(a2)
		addq.w	#1,UNIT_OPENCNT(a3)
		addq.w	#1,LIB_OPENCNT(a6)
		and.b	#~LIBF_DELEXP,LIB_FLAGS(a6)

		ifd	DEBUG
		DMSG	<'Open successfull',LF>
		endc

		moveq	#0,d0

open_exit	movem.l	(sp)+,d2/d3/a2/a3
		rts

open_fail	moveq	#IOERR_OPENFAIL,d0

open_err	moveq	#-1,d1
		move.l	d1,IO_DEVICE(a2)
		move.l	d1,IO_UNIT(a2)

		move.b	d0,IO_ERROR(a2)

		ifd	DEBUG
		DMSG	<'Device open failed, error %ld',LF>
		endc

		bra.b	open_exit

excl_open_fail	moveq	#IOERR_UNITBUSY,d0
		bra.b	open_err

;
; Device close routine
;
; Entry:
;   a6  -  device base
;   a1  -  io request
;
; Return:
;   d0  -  seglist if device no longer in use, else zero
;
dev_Close	movem.l	a2/a3,-(sp)

		ifd	DEBUG
		DMSG	<'Device close entry',LF>
		endc

		move.l	a1,a2
		move.l	IO_UNIT(a2),a3
		bclr	#UNITB_EXCLUSIVE,UNIT_FLAGS(a3)

		moveq	#-1,d0
		move.l	d0,IO_DEVICE(a2)
		move.l	d0,IO_UNIT(a2)

		move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
;
; Remove magic cookie from the cookie list
; Remember to Disable() when accessing the cookie list
;
		lib	Disable
		move.l	IOS2_BUFFERMANAGEMENT(a2),a1
		lib	Remove
		lib	Enable
		move.l	IOS2_BUFFERMANAGEMENT(a2),a1
		move.b	cookie_Flags(a1),-(sp)
		moveq	#cookie_Sizeof,d0
		lib	FreeMem
		move.b	(sp)+,d0
		move.l	(sp)+,a6

		subq.w	#1,UNIT_OPENCNT(a3)

		btst	#BFMB_PROM,d0
		beq.b	close_1

		subq.w	#1,du_PromCount(a3)
		bne.b	close_1

; disable promiscuous mode
		move.l	du_BoardAddr1(a3),a0
		move.b	#RCRF_AB!RCRF_AM,NIC_RCR(a0)

		ifd	DEBUG
		DMSG	<'Disabled promiscuous mode',LF>
		endc

close_1		moveq	#0,d0
		subq.w	#1,LIB_OPENCNT(a6)
		bne.b	close_end
		btst	#LIBB_DELEXP,LIB_FLAGS(a6)
		beq.b	close_end
		bsr.b	dev_Expunge

close_end	movem.l	(sp)+,a2/a3
		rts

;
; Device expunge routine
;
; Entry:
;   a6  -  device base
;
; Return:
;   d0  -  seglist if device no longer in use, else zero
;
dev_Expunge	tst.w	LIB_OPENCNT(a6)
		beq.b	do_expunge

		or.b	#LIBF_DELEXP,LIB_FLAGS(a6)	;delayed expunge
		moveq	#0,d0
		rts

;
; really expunge the device
;
do_expunge	movem.l	d2/d3/a4/a6,-(sp)

		ifd	DEBUG
		DMSG	<'do_expunge entry',LF>
		endc

		moveq	#NUM_UNITS-1,d3

unit_expunge_loop
		move.l	d3,d2
		lsl.l	#2,d2
		move.l	dev_UnitTable(a6,d2.l),d0
		beq.b	unit_expunge_next

		move.l	d0,a1
		bsr	Expunge_Unit

		clr.l	dev_UnitTable(a6,d2.l)

unit_expunge_next
		dbf	d3,unit_expunge_loop

		move.l	a6,a4
		move.l	dev_SysBase(a4),a6

		move.l	dev_ExpansionBase(a4),a1
		lib	CloseLibrary

		move.l	dev_IntuitionBase(a4),a1
		lib	CloseLibrary

		move.l	dev_SegList(a4),d2
		move.l	a4,a1
		lib	Remove

		move.l	a4,a1
		moveq	#0,d0
		moveq	#0,d1
		move.w	LIB_NEGSIZE(a4),d0
		move.w	LIB_POSSIZE(a4),d1
		sub.l	d0,a1
		add.l	d1,d0
		lib	FreeMem

		move.l	d2,d0
		movem.l	(sp)+,d2/d3/a4/a6
		rts

;
; Initialize buffer management magic cookie
;
; Entry:
;   a1  -  buffer management taglist
;
; This does not use the 2.0+ utility.library taglist functions,
; and it should also work on the 1.3 operating system.
;
InitBuffManagement
		movem.l	a2/a3,-(sp)
		move.l	a1,a2

		ifd	DEBUG
		move.l	a1,d0
		DMSG	<'InitBuffManagement entry, taglist = $%lx',LF>
		endc

		moveq	#cookie_Sizeof,d0
		move.l	#MEMF_PUBLIC!MEMF_CLEAR,d1
		lib	Exec,AllocMem
		tst.l	d0
		beq	initbuffm_exit
		move.l	d0,a3

		ifd	DEBUG
		DMSG	<'Allocated magic cookie at $%lx',LF>
		endc

		lea	DummyCopy(pc),a0
		move.l	a0,cookie_CopyToBuff(a3)
		move.l	a0,cookie_CopyFromBuff(a3)

		move.l	a2,d0
		beq.b	initbuffm_ok

buffm_tag_loop	move.l	(a2)+,d0
		beq.b	initbuffm_ok	;TAG_DONE == 0

		cmp.l	#S2_COPYTOBUFF,d0
		bne.b	1$
		move.l	(a2)+,cookie_CopyToBuff(a3)
		bra.b	buffm_tag_loop

1$		cmp.l	#S2_COPYFROMBUFF,d0
		bne.b	2$
		move.l	(a2)+,cookie_CopyFromBuff(a3)
		bra.b	buffm_tag_loop

2$		cmp.l	#S2_PACKETFILTER,d0
		bne.b	21$
		move.l	(a2)+,cookie_PacketFilter(a3)
		bra.b	buffm_tag_loop

21$		subq.l	#TAG_IGNORE,d0
		bne.b	3$

55$		addq.l	#4,a2
		bra.b	buffm_tag_loop

3$		subq.l	#TAG_MORE-TAG_IGNORE,d0
		bne.b	4$

		move.l	(a2),a2
		bra.b	buffm_tag_loop

4$		subq.l	#TAG_SKIP-TAG_MORE,d0
		bne.b	55$
		addq.l	#8,a2
		bra.b	55$

initbuffm_ok
		ifd	DEBUG
		move.l	cookie_CopyFromBuff(a3),d0
		move.l	cookie_CopyToBuff(a3),d1
		DMSG	<'CopyFromBuff = $%lx, CopyToBuff = $%lx',LF>
		move.l	cookie_PacketFilter(a3),d0
		DMSG	<'PacketFilter hook = $%lx',LF>
		endc

		lea	cookie_RxQueue(a3),a0
		NEWLIST	a0

		move.l	a3,d0

initbuffm_exit	movem.l	(sp)+,a2/a3
		rts

;
; Dummy copy routine for buffer management
;
DummyCopy	moveq	#1,d0		; success
		rts

;
; Initialize an unit
;
; Entry:
;  d0  -  unit number
;  a6  -  device base
;
; Return:
;  d0  -  pointer to unit structure or zero if failed
;
; Note: Unit number is zero for first Hydra board, one for second etc.
;       Initialize_Unit will fail if the board already has
;       the CONFIGME bit cleared
;
Initialize_Unit	movem.l	d2/d3/a2/a3,-(sp)

		ifd	DEBUG
		DMSG	<'Initialize unit entry, number = %ld',LF>
		endif

		move.l	d0,d2
		move.l	d0,d3

		suba.l	a0,a0

find_board_loop
		move.l	#HYDRA_MANUF_NUM,d0
		move.l	#HYDRA_PROD_NUM,d1
		lib	Expansion,FindConfigDev
		tst.l	d0
		beq	init_unit_exit
		tst.l	d3
		beq.b	found_board
		subq.l	#1,d3
		move.l	d0,a0
		bra.b	find_board_loop

found_board	move.l	d0,a2
		bclr	#CDB_CONFIGME,cd_Flags(a2)
		beq	init_unit_exit	; board already configured

		ifd	DEBUG
		DMSG	<'Found Hydra ethernet board, configdev = $%lx',LF>
		endc

;
; find out the amount of RAM memory on the ethernet card
;
		ifd	DEBUG
		move.l	cd_BoardAddr(a2),d0
		DMSG	<'Looking for card RAM at $%lx',LF>
		endc

		moveq	#0,d3
		move.l	cd_BoardAddr(a2),a0
		move.l	#$5555,d0
		move.l	#$aaaa,d1

ram_size_loop	move.w	d0,0(a0,d3.l)		; .l's added by JM 940217
		move.w	d1,2(a0,d3.l)
		NIC_Delay
		NIC_Delay
		cmp.w	0(a0,d3.l),d0
		bne.b	ram_end
		cmp.w	2(a0,d3.l),d1
		bne.b	ram_end
		add.w	#$100,d3
		cmp.w	#$ff00,d3
		bcs.b	ram_size_loop

ram_end
		ifd	DEBUG
		move.l	d3,d0
		add.l	a0,d0
		DMSG	<'Receive buffer end (end of card RAM) = $%lx',LF>
		endc

		tst.w	d3
		beq	ram_error
		lsr.w	#8,d3

		move.l	#du_Sizeof,d0
		move.l	#MEMF_PUBLIC!MEMF_CLEAR,d1
		lib	Exec,AllocMem
		tst.l	d0
		beq	init_unit_alloc_fail

		move.l	d0,a3
		lea	dev_name(pc),a0
		move.l	a0,LN_NAME(a3)
		move.b	#PA_IGNORE,MP_FLAGS(a3)	;the MsgPort in unit is not used
		move.l	a6,du_DevicePtr(a3)
		move.l	d2,du_UnitNum(a3)
		move.l	a2,du_ConfigDev(a3)
		move.l	cd_BoardAddr(a2),a0
		move.l	a0,du_BoardAddr(a3)
		add.l	#$8000,a0
		move.l	a0,du_BoardAddr1(a3)

		moveq	#-1,d0
		move.l	d0,du_CurrentAddr(a3)
		move.w	d0,du_CurrentAddr+4(a3)
;
; select page 0 & disable & clear NIC interrupts before adding interrupt server
;
		move.b	#CRF_NODMA!CRF_STOP,NIC_CR(a0)
		NIC_Delay
		move.b	#0,NIC_IMR(a0)			; disable interrupts
		NIC_Delay
		move.b	#$ff,NIC_ISR(a0)		; clear interrupts
		NIC_Delay
;
; read default ethernet address from board PROM
;
		lea	HYDRA_DEFADDR(a0),a0
		lea	du_DefaultAddr(a3),a1

		moveq	#EADDR_BYTES-1,d0
get_def_addr_loop
		move.b	(a0),(a1)+
		addq.l	#2,a0
		dbf	d0,get_def_addr_loop

; (interrupt server is added in S2_CONFIGINTERFACE)

;
; initialize transmit page start/receive buffer start/end page variables
;
		clr.b	du_TPStart(a3)
		move.b	#8,du_PStart(a3)
		move.b	d3,du_PStop(a3)
;
; initialize unit transmit/receive queues
;
		lea	du_TxQueue(a3),a0
		NEWLIST	a0

		lea	du_CookieList(a3),a0
		NEWLIST	a0

		lea	du_RxOrphanQueue(a3),a0
		NEWLIST	a0

		lea	du_EventList(a3),a0
		NEWLIST	a0

		lea	du_MultiCastList(a3),a0
		NEWLIST	a0

		lea	du_TypeTrackList(a3),a0
		NEWLIST	a0

init_unit_ok	move.l	a3,d0

init_unit_exit
		ifd	DEBUG
		DMSG	<'Initialize_Unit return = $%lx',LF>
		endc

		movem.l	(sp)+,d2/d3/a2/a3
		rts

ram_error
		ifd	DEBUG
		DMSG	<'Board RAM test failed',LF>
		endc

init_unit_alloc_fail
		bset	#CDB_CONFIGME,cd_Flags(a2)
		moveq	#0,d0
		bra.b	init_unit_exit
;
; Unit expunge routine
;
; Entry:
;  a1  -  pointer to unit structure
;
; Return:
;  nothing
;
Expunge_Unit	movem.l	d2/a2/a3/a6,-(sp)
		move.l	dev_SysBase(a6),a6

		ifd	DEBUG
		move.l	a1,d0
		move.l	du_UnitNum(a1),d1
		DMSG	<'Expunge_Unit called, unit = $%lx (#%ld)',LF>
		endc

		move.l	a1,a3
		move.l	du_BoardAddr1(a3),a0
		move.b	#CRF_NODMA!CRF_STOP,NIC_CR(a0) ; reset & select page 0
		NIC_Delay
		move.b	#0,NIC_IMR(a0)			 ; disable all interrupts
		NIC_Delay
		move.b	#$ff,NIC_ISR(a0)		 ; clear all interrupts

		btst	#UNITB_ONLINE,UNIT_FLAGS(a3)
		beq.b	exp_unit_1

		lea	du_NIC_Intr(a3),a1
		moveq	#INTB_PORTS,d0
		lib	RemIntServer

exp_unit_1
;
; free all multicast addresses that are in use when the unit is expunged
;
		move.l	du_MultiCastList(a3),a2

exp_mca_loop	move.l	(a2),d2
		beq.b	exp_mca_done

		move.l	a2,a1
		move.l	#mca_Sizeof,d0
		lib	FreeMem

		move.l	d2,a2
		bra.b	exp_mca_loop

exp_mca_done
;
; free all type tracking nodes that are still here
;
		move.l	du_TypeTrackList(a3),a2

exp_tt_loop	move.l	(a2),d2
		beq.b	exp_tt_done

		move.l	a2,a1
		move.l	#ttn_Sizeof,d0
		lib	FreeMem

		move.l	d2,a2
		bra.b	exp_tt_loop

exp_tt_done
;
; and free the unit structure itself
;
		move.l	a3,a1
		move.l	du_ConfigDev(a3),a3
		move.l	#du_Sizeof,d0
		lib	FreeMem
;
; allow re-configuration of the board
;
		bset	#CDB_CONFIGME,cd_Flags(a3)
		movem.l	(sp)+,d2/a2/a3/a6
		rts
;
; BeginIO routine
;
; A1  -  pointer to IORequest
; A6  -  pointer to device
;
dev_BeginIO	movem.l	a2/a3,-(sp)
		move.l	a1,a2
		move.b	#NT_MESSAGE,LN_TYPE(a2)		;LN_TYPE != NT_REPLYMSG
		clr.b	IO_ERROR(a2)
		move.l	IO_UNIT(a2),a3

		ifd	DEBUG
		move.l	a1,d0
		moveq	#0,d1
		move.w	IO_COMMAND(a1),d1
		DMSG	<'BeginIO, request = $%lx, command = $%lx',LF>
		endc

		move.w	IO_COMMAND(a2),d0
		cmp.w	#S2_END,d0
		bcc.b	invalid_cmd

		add.w	d0,d0	; d0 *= 2
		lea	dev_CmdTable(pc),a0
		move.l	a0,a1
		add.w	d0,a1
		add.w	(a1),a0

		jsr	(a0)

beginio_exit	movem.l	(sp)+,a2/a3
		rts

invalid_cmd	moveq	#IOERR_NOCMD,d0
		moveq	#0,d1

IOError		move.b	d0,IO_ERROR(a2)
		move.b	d1,IOS2_WIREERROR+3(a2)

;
; a2 - iorequest, a3 - unit, a6 - device
;
TermIO
		ifd	DEBUG
		movem.l	d2/d3,-(sp)
		move.l	a2,d0
		moveq	#0,d1
		move.w	IO_COMMAND(a2),d1
		moveq	#0,d2
		move.b	IO_ERROR(a2),d2
		moveq	#0,d3
		move.b	IO_FLAGS(a2),d3
		DMSG	<'TermIO, req = $%lx, cmd = $%lx, err = $%lx, flags = %lx',LF>
		movem.l	(sp)+,d2/d3
		endc

		move.l	a2,a1
		btst	#SANA2IOB_QUICK,IO_FLAGS(a1)
		bne.b	termio_exit
		lib	Exec,ReplyMsg
termio_exit	rts

;
; AbortIO routine
; a1  -  pointer to IORequest
;
dev_AbortIO	movem.l	d2/a2/a3,-(sp)
		moveq	#IOERR_NOCMD,d2
		move.l	a1,a2

		ifd	DEBUG
		move.l	a1,d0
		DMSG	<'AbortIO, request = $%lx',LF>
		endc

		move.w	IO_COMMAND(a2),d0
		cmp.w	#S2_ONEVENT,d0
		beq.b	abort_onevent

		cmp.w	#CMD_WRITE,d0
		beq.b	abort_write
		cmp.w	#S2_MULTICAST,d0
		beq.b	abort_write
		cmp.w	#S2_BROADCAST,d0
		beq.b	abort_write

		cmp.w	#CMD_READ,d0
		beq.b	abort_read
		cmp.w	#S2_READORPHAN,d0
		bne.b	AbortIO_End

abort_onevent
abort_read
abort_write	bclr	#IOB_QUEUED,IO_FLAGS(a2)
		beq.b	AbortIO_End

		move.l	a2,a1
		lib	Exec,Remove

		ifd	DEBUG
		DMSG	<'Unlinked request',LF>
		endc

		moveq	#IOERR_ABORTED,d0
		moveq	#0,d1
		bsr	IOError
		moveq	#0,d2

AbortIO_End	move.l	d2,d0
		movem.l	(sp)+,d2/a2/a3
		rts

;
; Abort all pending requests, used by CMD_FLUSH and S2_OFFLINE
; A3  -  pointer to unit structure
; A6  -  pointer to device structure
; D0  -  flag, if nonzero, aborts also S2_ONEVENT-commands.
; (this really should only disable PORTS interrupt...
; Disable()ing for this long a time surely affects serial receive...)
; (No request on any of the queues should have IOB_QUICK set)
;
; This doesn't abort the currently active transmit, if there is one
;
Abort_All	movem.l	d2/d3/a2/a4/a6,-(sp)
		move.l	d0,d3

		ifd	DEBUG
		DMSG	<'Abort_All',LF>
		endc

		move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
		lib	Disable

		move.l	du_TxQueue+MLH_HEAD(a3),a2

abort_tx_loop	move.l	(a2),d2
		beq.b	all_tx_aborted

		bclr	#IOB_QUEUED,IO_FLAGS(a2)
		move.b	#IOERR_ABORTED,IO_ERROR(a2)
		move.l	a2,a1
		lib	ReplyMsg

		move.l	d2,a2
		bra.b	abort_tx_loop

all_tx_aborted
		lea	du_TxQueue(a3),a0
		NEWLIST	a0

		ifd	DEBUG
		DMSG	<'Transmit requests aborted',LF>
		endc

		move.l	du_CookieList+MLH_HEAD(a3),a4

abort_rx_cookie_loop
		tst.l	(a4)		; check next node pointer
		beq.b	all_rx_aborted
		move.l	cookie_RxQueue+MLH_HEAD(a4),a2

abort_rx_loop	move.l	(a2),d2		; check & get next node pointer
		beq.b	abort_rx_cookie_next

		bclr	#IOB_QUEUED,IO_FLAGS(a2)
		move.b	#IOERR_ABORTED,IO_ERROR(a2)
		move.l	a2,a1
		lib	ReplyMsg

		move.l	d2,a2
		bra.b	abort_rx_loop

abort_rx_cookie_next
		lea	cookie_RxQueue(a4),a0
		NEWLIST	a0

		move.l	(a4),a4		; node = node->mln_Succ;
		bra.b	abort_rx_cookie_loop

all_rx_aborted
		ifd	DEBUG
		DMSG	<'Receive requests aborted',LF>
		endc

		move.l	du_RxOrphanQueue+MLH_HEAD(a3),a2

abort_orphan_loop
		move.l	(a2),d2
		beq.b	all_orphans_aborted

		bclr	#IOB_QUEUED,IO_FLAGS(a2)
		move.b	#IOERR_ABORTED,IO_ERROR(a2)
		move.l	a2,a1
		lib	ReplyMsg

		move.l	d2,a2
		bra.b	abort_orphan_loop

all_orphans_aborted
		lea	du_RxOrphanQueue(a3),a0
		NEWLIST	a0

		ifd	DEBUG
		DMSG	<'ReadOrphan requests aborted',LF>
		endc

		tst.l	d3
		beq.b	abort_all_done

		move.l	du_EventList+MLH_HEAD(a3),a2

abort_event_loop
		move.l	(a2),d2
		beq.b	all_events_aborted

		bclr	#IOB_QUEUED,IO_FLAGS(a2)
		move.b	#IOERR_ABORTED,IO_ERROR(a2)
		move.l	a2,a1
		lib	ReplyMsg

		move.l	d2,a2
		bra.b	abort_event_loop

all_events_aborted
		ifd	DEBUG
		DMSG	<'OnEvent requests aborted',LF>
		endc

		lea	du_EventList(a3),a0
		NEWLIST	a0

abort_all_done
;
; (it was a looong Disable() ... really shouldn't do that...)
;
		lib	Enable
		move.l	(sp)+,a6

		ifd	DEBUG
		DMSG	<'Abort_All complete',LF>
		endc

		movem.l	(sp)+,d2/d3/a2/a4/a6
		rts

;
; Device command table
;
dev_cmd		macro
		dc.w	\1-dev_CmdTable
		endm

dev_CmdTable	dev_cmd	invalid_cmd		;CMD_INVALID
		dev_cmd	invalid_cmd		;CMD_RESET
		dev_cmd	dev_Read		;CMD_READ
		dev_cmd	dev_Write		;CMD_WRITE
		dev_cmd	invalid_cmd		;CMD_UPDATE
		dev_cmd	invalid_cmd		;CMD_CLEAR
		dev_cmd	invalid_cmd		;CMD_STOP
		dev_cmd	invalid_cmd		;CMD_START
		dev_cmd	dev_Flush		;CMD_FLUSH
		dev_cmd	dev_DeviceQuery		;S2_DEVICEQUERY
		dev_cmd	dev_GetStationAddr	;S2_GETSTATIONADDRESS
		dev_cmd	dev_ConfigInterface	;S2_CONFIGINTERFACE
		dev_cmd	invalid_cmd		;reserved
		dev_cmd	invalid_cmd		;reserved
		dev_cmd	dev_AddMultiCast	;S2_ADDMULTICASTADDRESS
		dev_cmd	dev_DelMultiCast	;S2_DELMULTICASTADDRESS
		dev_cmd	dev_Multicast		;S2_MULTICAST
		dev_cmd	dev_Broadcast		;S2_BROADCAST
		dev_cmd	dev_TrackType		;S2_TRACKTYPE
		dev_cmd	dev_UnTrackType		;S2_UNTRACKTYPE
		dev_cmd	dev_GetTypeStats	;S2_GETTYPESTATS
		dev_cmd	dev_GetSpecialStats	;S2_GETSPECIALSTATS
		dev_cmd	dev_GetGlobalStats	;S2_GETGLOBALSTATS
		dev_cmd	dev_OnEvent		;S2_ONEVENT
		dev_cmd	dev_ReadOrphan		;S2_READORPHAN
		dev_cmd	dev_OnLine		;S2_ONLINE
		dev_cmd	dev_OffLine		;S2_OFFLINE

;
; S2_TRACKTYPE
;
; IOS2_PACKETTYPE - type to be tracked
;
dev_TrackType
		ifd	DEBUG
		move.l	IOS2_PACKETTYPE(a2),d0
		DMSG	<'IOS2_TRACKTYPE ($%lx)',LF>
		endc

		move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
		lib	Forbid

		move.l	du_TypeTrackList(a3),a1
		move.w	IOS2_PACKETTYPE+2(a2),d0
		cmp.w	#1500,d0
		bhi.b	track_find_loop
		moveq	#0,d0		;ieee802.3

track_find_loop	move.l	(a1),d1
		beq.b	track_find_end
		cmp.w	ttn_Type(a1),d0
		beq.b	already_tracked
		move.l	d1,a1
		bra.b	track_find_loop

track_find_end	move.l	d0,-(sp)
		move.l	#ttn_Sizeof,d0
		move.l	#MEMF_CLEAR!MEMF_PUBLIC,d1
		lib	AllocMem
		move.l	(sp)+,d1
		tst.l	d0
		beq	track_alloc_fail
		move.l	d0,a1

		move.w	d1,ttn_Type(a1)

		lib	Disable
		lea	du_TypeTrackList(a3),a0
		lib	AddTail
		lib	Enable

		lib	Permit
		move.l	(sp)+,a6
		bra	TermIO

already_tracked	lib	Permit
		move.l	(sp)+,a6
		moveq	#S2ERR_BAD_STATE,d0
		moveq	#S2WERR_ALREADY_TRACKED,d1
		bra	IOError

track_alloc_fail
		lib	Permit
		move.l	(sp)+,a6
		move.l	#S2EVENT_ERROR!S2EVENT_SOFTWARE,d0
		bsr	DoEvent
		moveq	#S2ERR_NO_RESOURCES,d0
		moveq	#0,d1
		bra	IOError

;
; S2_UNTRACKTYPE
;
; IOS2_PACKETTYPE - type to be removed from tracking
;
dev_UnTrackType
		ifd	DEBUG
		move.l	IOS2_PACKETTYPE(a2),d0
		DMSG	<'IOS2_UNTRACKTYPE ($%lx)',LF>
		endc

		move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
		lib	Forbid

		move.l	du_TypeTrackList(a3),a1
		move.w	IOS2_PACKETTYPE+2(a2),d0
		cmp.w	#1500,d0
		bhi.b	untrack_find_loop
		moveq	#0,d0		;ieee802.3

untrack_find_loop
		move.l	(a1),d1
		beq.b	typetrack_not_found
		cmp.w	ttn_Type(a1),d0
		beq.b	untrack_found
		move.l	d1,a1
		bra.b	untrack_find_loop

untrack_found	move.l	a1,-(sp)
		lib	Disable
		lib	Remove
		lib	Enable
		move.l	(sp)+,a1
		move.l	#ttn_Sizeof,d0
		lib	FreeMem

		lib	Permit
		move.l	(sp)+,a6
		bra	TermIO

typetrack_not_found
		lib	Permit
		move.l	(sp)+,a6
		moveq	#S2ERR_BAD_STATE,d0
		moveq	#S2WERR_NOT_TRACKED,d1
		bra	IOError

;
; S2_GETTYPESTATS
;
; IOS2_PACKETTYPE - get statistics for this type
; IOS2_STATDATA   - pointer to Sana2PacketTypeStats-structure
;
dev_GetTypeStats
		ifd	DEBUG
		move.l	IOS2_PACKETTYPE(a2),d0
		DMSG	<'IOS2_GETTYPESTATS ($%lx)',LF>
		endc

		tst.l	IOS2_STATDATA(a2)
		beq	null_pointer

		move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
		lib	Forbid

		move.l	du_TypeTrackList(a3),a1
		move.w	IOS2_PACKETTYPE+2(a2),d0
		cmp.w	#1500,d0
		bhi.b	typestat_find_loop
		moveq	#0,d0		;ieee802.3

typestat_find_loop
		move.l	(a1),d1
		beq	typetrack_not_found
		cmp.w	ttn_Type(a1),d0
		beq.b	typestat_found
		move.l	d1,a1
		bra.b	typestat_find_loop

typestat_found	lea	ttn_Stat(a1),a0
		move.l	IOS2_STATDATA(a2),a1
		moveq	#S2PTS_SIZE,d0
		lib	CopyMem

		lib	Permit
		move.l	(sp)+,a6
		bra	TermIO

;
; S2_ADDMULTICASTADDRESS
;
; IOS2_SRCADDR  --  Multicast address to add
;
dev_AddMultiCast
		ifd	DEBUG
		move.l	IOS2_SRCADDR(a2),d0
		moveq	#0,d1
		move.w	IOS2_SRCADDR+4(a2),d1
		DMSG	<'S2_ADDMULTICASTADDRESS (%08lx%04lx)',LF>
		endc

		btst	#UNITB_CONFIGURED,UNIT_FLAGS(a3)
		beq	not_configured
		btst	#UNITB_ONLINE,UNIT_FLAGS(a3)
		beq	not_online

		btst	#0,IOS2_SRCADDR(a2)
		beq	bad_multicast_addr

		lib	Exec,Forbid
		lea	IOS2_SRCADDR(a2),a0
		bsr	find_multicast
		tst.l	d0
		bne	add_multi_1
;
; allocate a new multicast node
;
		moveq	#mca_Sizeof,d0
		move.l	#MEMF_CLEAR!MEMF_PUBLIC,d1
		lib	Exec,AllocMem
		tst.l	d0
		beq	out_of_memory
		move.l	d0,a1

		ifd	DEBUG
		DMSG	<'New multicast address, node = $%lx,'>
		endc

		move.l	IOS2_SRCADDR(a2),mca_Addr(a1)
		move.w	IOS2_SRCADDR+4(a2),mca_Addr+4(a1)

		lea	IOS2_SRCADDR(a2),a0
		bsr	multicast_hash		;this doesn't trash a1
		move.w	d0,mca_BitNum(a1)

		ifd	DEBUG
		DMSG	<' bitnum = %ld',LF>
		endc

		add.w	d0,d0
		lea	du_MultiCastBitUseCount(a3),a0
		add.w	d0,a0
		addq.w	#1,(a0)

		ifd	DEBUG
		moveq	#0,d0
		move.w	(a0),d0
		DMSG	<'BitNum usecount = %ld',LF>
		endc

		cmp.w	#1,(a0)
		bhi	add_multi_2

		move.w	mca_BitNum(a1),d0
		move.w	d0,d1
		lsr.w	#3,d1
		add.w	d1,d1	; * 2
		move.l	du_BoardAddr1(a3),a0
		lea	NIC_MAR0(a0),a0
		add.w	d1,a0

		ifd	DEBUG
		movem.l	d0/d1,-(sp)
		move.l	a0,d1
		and.l	#7,d0
		DMSG	<'set bit #%ld at addr $%lx',LF>
		movem.l	(sp)+,d0/d1
		endc
;
; changing to page 1 inside Disable()/Enable() is safe
; (writing 0 to TXP has no effect, and this doesn't use remote DMA)
;
		movem.l	a2/a6,-(sp)
		move.l	dev_SysBase(a6),a6
		lib	Disable
		move.l	du_BoardAddr1(a3),a2
		move.b	#CRF_PAGE0!CRF_NODMA!CRF_START,NIC_CR(a2)
		NIC_Delay
		bset	d0,(a0)
		move.b	#CRF_NODMA!CRF_START,NIC_CR(a2)
		lib	Enable
		movem.l	(sp)+,a2/a6

add_multi_2	move.l	a1,-(sp)
		lea	du_MultiCastList(a3),a0
		lib	Exec,AddTail
		move.l	(sp)+,a1

add_multi_1	addq.l	#1,mca_UseCount(a1)

		ifd	DEBUG
		move.l	mca_UseCount(a1),d0
		DMSG	<'Multicast addr usecount = %ld',LF>
		endc

		lib	Exec,Permit
		bra	TermIO

out_of_memory	lib	Exec,Permit

		move.l	#S2EVENT_ERROR!S2EVENT_SOFTWARE,d0
		bsr	DoEvent

		moveq	#S2ERR_NO_RESOURCES,d0
		moveq	#0,d1
		bra	IOError

;
; S2_DELMULTICASTADDRESS
;
dev_DelMultiCast
		ifd	DEBUG
		move.l	IOS2_SRCADDR(a2),d0
		moveq	#0,d1
		move.w	IOS2_SRCADDR+4(a2),d1
		DMSG	<'S2_DELMULTICASTADDRESS (%08lx%04lx)',LF>
		endc

		btst	#UNITB_CONFIGURED,UNIT_FLAGS(a3)
		beq	not_configured
		btst	#UNITB_ONLINE,UNIT_FLAGS(a3)
		beq	not_online

		btst	#0,IOS2_SRCADDR(a2)
		beq	bad_multicast_addr

		move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
		lib	Forbid
		lea	IOS2_SRCADDR(a2),a0
		bsr	find_multicast
		tst.l	d0
		beq	delmulti_1
		move.l	d0,a1

		ifd	DEBUG
		move.l	mca_UseCount(a1),d1
		DMSG	<'Remove multicast addr, node = $%lx, Usecount = %ld',LF>
		endc

		subq.l	#1,mca_UseCount(a1)
		bne	delmulti_0

		move.w	mca_BitNum(a1),d0

		ifd	DEBUG
		ext.l	d0
		DMSG	<'Multicast bitnum = %ld',LF>
		endc

		add.w	d0,d0
		lea	du_MultiCastBitUseCount(a3),a0
		add.w	d0,a0

		ifd	DEBUG
		moveq	#0,d0
		move.w	(a0),d0
		DMSG	<'Multicast bit use count = %ld',LF>
		endc

		subq.w	#1,(a0)
		bne.b	delmulti_b1

		move.w	mca_BitNum(a1),d0
		move.w	d0,d1
		lsr.w	#3,d1
		move.l	du_BoardAddr1(a3),a0
		add.w	d1,d1	; * 2
		lea	NIC_MAR0(a0),a0
		add.w	d1,a0

		ifd	DEBUG
		movem.l	d0/d1,-(sp)
		move.l	a0,d1
		and.l	#7,d0
		DMSG	<'clear bit #%ld at addr $%lx',LF>
		movem.l	(sp)+,d0/d1
		endc

		move.l	a2,-(sp)
		lib	Disable
		move.l	du_BoardAddr1(a3),a2
		move.b	#CRF_PAGE0!CRF_NODMA!CRF_START,NIC_CR(a2)
		NIC_Delay
		bclr	d0,(a0)
		move.b	#CRF_NODMA!CRF_START,NIC_CR(a2)
		lib	Enable
		move.l	(sp)+,a2

delmulti_b1	move.l	a1,-(sp)
		lib	Remove
		move.l	(sp)+,a1
		moveq	#mca_Sizeof,d0
		lib	FreeMem

delmulti_0	moveq	#1,d0

delmulti_1	lib	Permit		;this doesn't trash any registers
		move.l	(sp)+,a6
		tst.l	d0
		beq	bad_multicast_addr
		bra	TermIO

;
; find a given multicast address from the multicast address list
;
; pointer to address in a0, pointer to unit in a3
;
; returns zero in d0 if not found,
; pointer to multicast address node in d0/a1 if found.
;
find_multicast
		ifd	DEBUG
		DMSG	<'find_multicast',LF>
		endc

		move.l	du_MultiCastList+MLH_HEAD(a3),a1

find_multicast_loop
		move.l	(a1),d1
		beq.b	multicast_not_found

		move.l	mca_Addr(a1),d0
		cmp.l	(a0),d0
		bne.b	find_multicast_next
		move.w	mca_Addr+4(a1),d0
		cmp.w	4(a0),d0
		beq.b	found_multicast

find_multicast_next
		move.l	d1,a1
		bra.b	find_multicast_loop

found_multicast	move.l	a1,d0

		ifd	DEBUG
		DMSG	<'multicast found, node = $%lx',LF>
		endc

		rts

multicast_not_found
		ifd	DEBUG
		DMSG	<'multicast not found',LF>
		endc

		moveq	#0,d0
		rts

;
; CMD_FLUSH
;
dev_Flush	moveq	#1,d0
		bsr	Abort_All	;abort all pending requests
		bra	TermIO		;(including S2_ONEVENTs)

;
; S2_ONLINE
;
dev_OnLine
		ifd	DEBUG
		DMSG	<'S2_ONLINE',LF>
		endc

		btst	#UNITB_CONFIGURED,UNIT_FLAGS(a3)
		beq	not_configured

		move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
		lib	Forbid

		bset	#UNITB_ONLINE,UNIT_FLAGS(a3)
		beq.b	online_ok

		lib	Permit
		move.l	(sp)+,a6

		moveq	#S2ERR_BAD_STATE,d0
		moveq	#S2WERR_UNIT_ONLINE,d1
		bra	IOError

online_ok	lea	du_NIC_Intr(a3),a1
		moveq	#INTB_PORTS,d0
		lib	AddIntServer

		move.l	du_BoardAddr1(a3),a0
		move.b	#CRF_NODMA!CRF_START,NIC_CR(a0) ; start the NIC
		NIC_Delay
		move.b	#$ff,NIC_ISR(a0)	; clear interrupt status
		NIC_Delay
		move.b	#%00111111,NIC_IMR(a0)	; enable interrupts

		lib	Permit
		move.l	(sp)+,a6

		lea	du_LastStart+TV_SECS(a3),a0
		lea	du_LastStart+TV_MICRO(a3),a1
		lib	Intuition,CurrentTime
		bset	#UNITB_ONLINE,UNIT_FLAGS(a3)
		addq.l	#1,du_Reconfigurations(a3)

		moveq	#S2EVENT_ONLINE,d0
		bsr	DoEvent
		bra	TermIO

;
; S2_OFFLINE
;
dev_OffLine
		ifd	DEBUG
		DMSG	<'S2_OFFLINE',LF>
		endc

		btst	#UNITB_CONFIGURED,UNIT_FLAGS(a3)
		beq	not_configured

		bclr	#UNITB_ONLINE,UNIT_FLAGS(a3)
		bne	offline_ok

		moveq	#S2ERR_BAD_STATE,d0
		moveq	#S2WERR_UNIT_OFFLINE,d1
		bra	IOError

offline_ok	moveq	#0,d0		;don't abort S2_ONLINEs
		bsr	Abort_All	;abort all pending requests

; wait for the current transmit to complete
wait_tx_complete
		btst	#UNITB_CURRENTTX,UNIT_FLAGS(a3)
		bne.b	wait_tx_complete	; busy wait loop...
;
; shut down the device
;
		move.l	du_BoardAddr1(a3),a0
		move.b	#CRF_NODMA!CRF_STOP,NIC_CR(a0) ; reset & select page 0
		NIC_Delay
		move.b	#0,NIC_IMR(a0)			 ; disable all interrupts
		NIC_Delay
		move.b	#$ff,NIC_ISR(a0)		 ; clear all interrupts

		lea	du_NIC_Intr(a3),a1
		moveq	#INTB_PORTS,d0
		lib	Exec,RemIntServer

		moveq	#S2EVENT_OFFLINE,d0
		bsr	DoEvent
		bra	TermIO

;
; S2_DEVICEQUERY-command
;
; IOS2_STATDATA  -  pointer to DeviceQuery structure
;
dev_DeviceQuery
		ifd	DEBUG
		DMSG	<'S2_DEVICEQUERY',LF>
		endc

		move.l	IOS2_STATDATA(a2),d0
		beq.b	null_pointer

		move.l	d0,a1
		cmp.l	#S2DQ_SIZE,S2DQ_SIZEAVAILABLE(a1)
		bcs.b	bad_stat_data

		addq.l	#4,a1
		lea	DevQueryData(pc),a0
		move.l	#S2DQ_SIZE-4,d0
		lib	Exec,CopyMem
		bra	TermIO

bad_stat_data	moveq	#S2ERR_BAD_ARGUMENT,d0
		moveq	#S2WERR_BAD_STATDATA,d1
		bra	IOError

null_pointer	moveq	#S2ERR_BAD_ARGUMENT,d0
		moveq	#S2WERR_NULL_POINTER,d1
		bra	IOError

DevQueryData	dc.l	S2DQ_SIZE
		dc.l	0
		dc.l	0
		dc.w	EADDR_BYTES*8		;AddrFieldSize
		dc.l	1500			;MTU
		dc.l	10000000		;bps
		dc.l	S2WIRETYPE_ETHERNET

;
; S2_GETSTATIONADDRESS-command
;
; IOS2_SRCADDR  -  current address
; IOS2_DSTADDR  -  default address
;
dev_GetStationAddr
		ifd	DEBUG
		DMSG	<'S2_GETSTATIONADDRESS',LF>
		endc

		move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
		lib	Forbid

		move.l	du_CurrentAddr(a3),IOS2_SRCADDR(a2)
		move.w	du_CurrentAddr+4(a3),IOS2_SRCADDR+4(a2)
		move.l	du_DefaultAddr(a3),IOS2_DSTADDR(a2)
		move.w	du_DefaultAddr+4(a3),IOS2_DSTADDR+4(a2)

		lib	Permit
		move.l	(sp)+,a6
		bra	TermIO

;
; S2_GETGLOBALSTATS
;
; IOS2_STATDATA  -  pointer to Sana2DeviceStats structure
;
dev_GetGlobalStats
		ifd	DEBUG
		DMSG	<'S2_GETGLOBALSTATS',LF>
		endc

		move.l	IOS2_STATDATA(a2),d0
		beq	null_pointer

		movem.l	a5/a6,-(sp)
		move.l	d0,a5
		move.l	dev_SysBase(a6),a6
		lib	Disable

		move.l	du_PacketsReceived(a3),S2DS_PACKETSRECEIVED(a5)
		move.l	du_PacketsSent(a3),S2DS_PACKETSSENT(a5)
		move.l	du_BadPackets(a3),S2DS_BADDATA(a5)
		move.l	du_Overruns(a3),S2DS_OVERRUNS(a5)
		move.l	du_UnknownTypesReceived(a3),S2DS_UNKNOWNTYPESRECEIVED(a5)
		move.l	du_Reconfigurations(a3),S2DS_RECONFIGURATIONS(a5)
		move.l	du_LastStart+TV_SECS(a3),S2DS_LASTSTART+TV_SECS(a5)
		move.l	du_LastStart+TV_MICRO(a3),S2DS_LASTSTART+TV_MICRO(a5)

		lib	Enable
		movem.l	(sp)+,a5/a6
		bra	TermIO

;
; S2_GETSPECIALSTATS
;
; IOS2_STATDATA  -  pointer to Sana2SpecialStats structure
;
dev_GetSpecialStats
		ifd	DEBUG
		DMSG	<'S2_GETSPECIALSTATS',LF>
		endc

		move.l	IOS2_STATDATA(a2),d0
		beq	null_pointer

		move.l	d0,a1
		move.l	S2SSH_RECORDCOUNTMAX(a1),d1
		beq	bad_stat_data
		clr.l	S2SSH_RECORDCOUNTSUPPLIED(a1)
;
; bad multicast filter count
;
		move.l	#S2SS_ETHERNET_BADMULTICAST,S2SSH_SIZE+S2SSR_TYPE(a1)
		lea	bad_multicast_filter_txt(pc),a0
		move.l	a0,S2SSH_SIZE+S2SSR_STRING(a1)
		move.l	du_BadMultiCastFilterCount(a3),S2SSH_SIZE+S2SSR_COUNT(a1)
		addq.l	#1,S2SSH_RECORDCOUNTSUPPLIED(a1)

;
; total number of collisions
;
		subq.l	#1,d1
		beq.b	specialstats_done

		move.l	#S2SS_ETHERNET_RETRIES,S2SSH_SIZE+S2SSR_SIZE+S2SSR_TYPE(a1)
		lea	num_collisions_txt(pc),a0
		move.l	a0,S2SSH_SIZE+S2SSR_SIZE+S2SSR_STRING(a1)
		move.l	du_Collisions(a3),S2SSH_SIZE+S2SSR_SIZE+S2SSR_COUNT(a1)
		addq.l	#1,S2SSH_RECORDCOUNTSUPPLIED(a1)

specialstats_done
		bra	TermIO

bad_multicast_filter_txt
		dc.b	'Bad multicast filtering',0

num_collisions_txt
		dc.b	'Number of collisions',0
		ds.w	0

;
; S2_CONFIGINTERFACE
;
; IOS2_SRCADDR  --  address of the interface (to be configured)
;
; Note that according to the SanaII-spec, an ethernet driver should refuse
; to configure itself to any other address than the hardware default.
; This device allows configuration to any (non-broad/multicast) address
;
dev_ConfigInterface
		ifd	DEBUG
		DMSG	<'S2_CONFIGINTERFACE',LF>
		endc

		bset	#UNITB_CONFIGURED,UNIT_FLAGS(a3)
		bne	already_configured

		btst	#0,IOS2_SRCADDR(a2)	;check multicast flag
		bne	config_bad_addr

		move.l	IOS2_SRCADDR(a2),du_CurrentAddr(a3)
		move.w	IOS2_SRCADDR+4(a2),du_CurrentAddr+4(a3)
;
; initialize network hardware
;
		move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
		lib	Disable

		move.l	du_BoardAddr1(a3),a0

		move.b	#CRF_NODMA!CRF_STOP,NIC_CR(a0) ; page 0, reset NIC
		NIC_Delay

; fifo thres. 4 bytes, 68k byteorder, word-wide DMA
		move.b	#DCRF_FT0!DCRF_LS!DCRF_BOS!DCRF_WTS,NIC_DCR(a0)
		NIC_Delay

		moveq	#0,d0
		move.b	d0,NIC_RBCR0(a0)
		NIC_Delay
		move.b	d0,NIC_RBCR1(a0)
		NIC_Delay

; accept broadcast & multicast
		move.b	#RCRF_AB!RCRF_AM,NIC_RCR(a0)
		NIC_Delay

		move.b	#TCRF_LB1,NIC_TCR(a0)	; loopback mode (for init)
		NIC_Delay

		move.b	du_PStart(a3),d0
		move.b	d0,NIC_PSTART(a0)
		NIC_Delay
		move.b	d0,NIC_BNDRY(a0)
		NIC_Delay
		move.b	du_PStop(a3),NIC_PSTOP(a0)
		NIC_Delay
;
; Add interrupt server
;
		lea	du_NIC_Intr(a3),a1
		lea	dev_name(pc),a0
		move.l	a0,LN_NAME(a1)
		move.b	#NT_INTERRUPT,LN_TYPE(a1)
		move.b	#20,LN_PRI(a1)
		lea	NIC_IntRoutine(pc),a0
		move.l	a0,IS_CODE(a1)
		move.l	a3,IS_DATA(a1)
		moveq	#INTB_PORTS,d0
		lib	AddIntServer

		move.l	du_BoardAddr1(a3),a0
		move.b	#$ff,NIC_ISR(a0)	; clear interrupt status
		NIC_Delay
		move.b	#%00111111,NIC_IMR(a0)	; enable interrupts
		NIC_Delay

; Select page 1
		move.b	#CRF_PAGE0!CRF_NODMA!CRF_STOP,NIC_CR(a0)
		NIC_Delay

		move.b	du_CurrentAddr(a3),NIC_PAR0(a0)
		NIC_Delay
		move.b	du_CurrentAddr+1(a3),NIC_PAR1(a0)
		NIC_Delay
		move.b	du_CurrentAddr+2(a3),NIC_PAR2(a0)
		NIC_Delay
		move.b	du_CurrentAddr+3(a3),NIC_PAR3(a0)
		NIC_Delay
		move.b	du_CurrentAddr+4(a3),NIC_PAR4(a0)
		NIC_Delay
		move.b	du_CurrentAddr+5(a3),NIC_PAR5(a0)
		NIC_Delay

;
; clear all multicast filter bits
;
		moveq	#0,d0
		move.b	d0,NIC_MAR0(a0)
		NIC_Delay
		move.b	d0,NIC_MAR1(a0)
		NIC_Delay
		move.b	d0,NIC_MAR2(a0)
		NIC_Delay
		move.b	d0,NIC_MAR3(a0)
		NIC_Delay
		move.b	d0,NIC_MAR4(a0)
		NIC_Delay
		move.b	d0,NIC_MAR5(a0)
		NIC_Delay
		move.b	d0,NIC_MAR6(a0)
		NIC_Delay
		move.b	d0,NIC_MAR7(a0)
		NIC_Delay

		move.b	du_PStart(a3),d0
		addq.b	#1,d0
		move.b	d0,NIC_CURR(a0)
		NIC_Delay
		move.b	d0,du_NextPkt(a3)

		move.b	#CRF_NODMA!CRF_START,NIC_CR(a0) ; page 0, start
		NIC_Delay

		move.b	#0,NIC_TCR(a0)		; loopback mode off
;
; NIC is now ready for operation
;

		lib	Enable
		move.l	(sp)+,a6

		lea	du_LastStart+TV_SECS(a3),a0
		lea	du_LastStart+TV_MICRO(a3),a1
		lib	Intuition,CurrentTime
		bset	#UNITB_ONLINE,UNIT_FLAGS(a3)
		addq.l	#1,du_Reconfigurations(a3)
		bra	TermIO

already_configured
		moveq	#S2ERR_BAD_STATE,d0
		moveq	#S2WERR_IS_CONFIGURED,d1
		bra	IOError

config_bad_addr	moveq	#S2ERR_BAD_ADDRESS,d0
		moveq	#0,d1
		bclr	#UNITB_CONFIGURED,UNIT_FLAGS(a3)
		bra	IOError


;
; S2_MULTICAST
;
; (parameters as in CMD_WRITE)
;
dev_Multicast
		ifd	DEBUG
		DMSG	<'S2_MULTICAST',LF>
		endc

		btst	#0,IOS2_DSTADDR(a2)
		bne.b	do_write

bad_multicast_addr
		moveq	#S2ERR_BAD_ADDRESS,d0
		moveq	#S2WERR_BAD_MULTICAST,d1
		bra	IOError

;
; S2_BROADCAST
;
; (parameters as in CMD_WRITE)
;
dev_Broadcast
		ifd	DEBUG
		DMSG	<'S2_BROADCAST',LF>
		endc

;
; set IOS2_DSTADDR to ethernet broadcast address FF:FF:FF:FF:FF:FF
;
		moveq	#-1,d0
		move.l	d0,IOS2_DSTADDR(a2)
		move.w	d0,IOS2_DSTADDR+4(a2)
		bra	do_write

;
; CMD_WRITE
;
; IO_FLAGS     -- SANA2IOB_RAW
; IOS2_PACKETTYPE - type of packet to send
; IOS2_DSTADDR    - destination address
; IOS2_DATALENGTH - length of data to send
; IOS2_DATA       - data to be sent
;
; (should probably check if the address is a destination multicast/broadcast)
; (but Commodore a2065.device does not check either...)
;
dev_Write
		ifd	DEBUG
		DMSG	<'CMD_WRITE',LF>
		endc

do_write	btst	#UNITB_CONFIGURED,UNIT_FLAGS(a3)
		beq	not_configured
		btst	#UNITB_ONLINE,UNIT_FLAGS(a3)
		beq	not_online

		cmp.l	#1500,IOS2_DATALENGTH(a2)
		bhi	mtu_exceeded

		bclr	#SANA2IOB_QUICK,IO_FLAGS(a2)

		move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
		lib	Disable

		bset	#UNITB_CURRENTTX,UNIT_FLAGS(a3)
		bne.b	queue_write

		lib	Enable
		move.l	(sp)+,a6

		ifd	DEBUG
		DMSG	<'Immediate write',LF>
		endc

		move.l	a2,du_CurrentTxReq(a3)
		bra	ActualSendPacket

queue_write	bset	#IOB_QUEUED,IO_FLAGS(a2)
		lea	du_TxQueue(a3),a0
		move.l	a2,a1
		lib	Enqueue		;was AddHead
		lib	Enable

		ifd	DEBUG
		DMSG	<'Queued write',LF>
		endc

		move.l	(sp)+,a6
		rts

not_configured	move.b	#S2ERR_BAD_STATE,d0
		move.b	#S2WERR_NOT_CONFIGURED,d1
		bra	IOError

not_online	move.b	#S2ERR_OUTOFSERVICE,d0
		move.b	#S2WERR_UNIT_OFFLINE,d1
		bra	IOError

mtu_exceeded	move.l	#S2EVENT_ERROR!S2EVENT_TX!S2EVENT_SOFTWARE,d0
		bsr	DoEvent

		move.b	#S2ERR_MTU_EXCEEDED,d0
		moveq	#0,d1
		bra	IOError

;
; CMD_READ
;
;
; IO_FLAGS         -  input SANA2IOB_RAW -- output SANA2IOB_RAW/BCAST/MCAST
; IOS2_PACKETTYPE  -  packet type to receive
; IOS2_DATA        -  received data copied here (with CopyToBuff)
; IOS2_DATALENGTH  -  output: length of the received packet
; IOS2_SRC/DSTADDR -  output: source/destination address
;
dev_Read
		ifd	DEBUG
		move.l	IOS2_PACKETTYPE(a2),d0
		DMSG	<'CMD_READ (packet type = $%04lx)',LF>
		endc

		btst	#UNITB_CONFIGURED,UNIT_FLAGS(a3)
		beq	not_configured
		btst	#UNITB_ONLINE,UNIT_FLAGS(a3)
		beq	not_online

		bclr	#SANA2IOB_QUICK,IO_FLAGS(a2)

		move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
		lib	Disable
		bset	#IOB_QUEUED,IO_FLAGS(a2)
		move.l	IOS2_BUFFERMANAGEMENT(a2),a0
		lea	cookie_RxQueue(a0),a0
		move.l	a2,a1
		lib	Enqueue		;was AddHead
		lib	Enable

		move.l	(sp)+,a6
		rts

dev_ReadOrphan
		ifd	DEBUG
		DMSG	<'S2_READORPHAN',LF>
		endc

		btst	#UNITB_CONFIGURED,UNIT_FLAGS(a3)
		beq	not_configured
		btst	#UNITB_ONLINE,UNIT_FLAGS(a3)
		beq	not_online

		bclr	#SANA2IOB_QUICK,IO_FLAGS(a2)

		move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
		lib	Disable
		bset	#IOB_QUEUED,IO_FLAGS(a2)
		lea	du_RxOrphanQueue(a3),a0
		move.l	a2,a1
		lib	AddHead
		lib	Enable
		move.l	(sp)+,a6
		rts

;
; S2_ONEVENT
;
; IOS2_WIREERROR - event mask (both input & output)
;
; ONLINE/OFFLINE events are returned immediately if the device
; is already in the state to be waited for. All other requests
; are just queued to du_EventList.
;
dev_OnEvent
		ifd	DEBUG
		move.l	IOS2_WIREERROR(a2),d0
		DMSG	<'S2_ONEVENT ($%lx)',LF>
		endc

		btst	#S2EVENTB_ONLINE,IOS2_WIREERROR+3(a2)
		beq.b	no_online

		btst	#UNITB_ONLINE,UNIT_FLAGS(a3)
		beq.b	no_online

		move.b	#S2EVENT_ONLINE,IOS2_WIREERROR+3(a2)
		bra	TermIO

no_online	btst	#S2EVENTB_OFFLINE,IOS2_WIREERROR+3(a2)
		beq.b	no_offline

		btst	#UNITB_ONLINE,UNIT_FLAGS(a3)
		bne.b	no_offline

		move.b	#S2EVENT_OFFLINE,IOS2_WIREERROR+3(a2)
		bra	TermIO

no_offline	move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
		lib	Disable

		bset	#IOB_QUEUED,IO_FLAGS(a2)
		lea	du_EventList(a3),a0
		move.l	a2,a1
		lib	AddTail

		lib	Enable
		move.l	(sp)+,a6
		rts

;
; handle waiting events
; terminate event requests that match the event mask in d0
;
; inputs:
;  d0  -  event mask
;  a3  -  unit ptr
;
DoEvent		movem.l	d2/d3/a2,-(sp)
		ifd	DEBUG
		DMSG	<'DoEvent $%lx',LF>
		endc

		move.l	d0,d3

		move.l	du_EventList(a3),a2

doevent_loop	move.l	(a2),d2
		beq.b	doevent_end

		ifd	DEBUG
		move.l	a2,d0
		move.l	IOS2_WIREERROR(a2),d1
		DMSG	<'DoEvent loop: event $%lx, mask $%lx',LF>
		endc

		move.b	d3,d0
		and.b	IOS2_WIREERROR+3(a2),d0
		beq.b	doevent_next

		move.b	d0,IOS2_WIREERROR+3(a2)

		move.l	a2,a1
		lib	Exec,Remove
		bsr	TermIO

doevent_next	move.l	d2,a2
		bra.b	doevent_loop

doevent_end	movem.l	(sp)+,d2/d3/a2
		rts

;
; actually send a packet
;
; unit pointer in a3, iorequest in a2
;
ActualSendPacket
		btst	#SANA2IOB_RAW,IO_FLAGS(a2)
		bne.b	raw_packet

 		move.l	IOS2_DSTADDR(a2),du_TxBuff(a3)
		move.w	IOS2_DSTADDR+4(a2),du_TxBuff+4(a3)
		move.w	du_CurrentAddr(a3),du_TxBuff+6(a3)
		move.l	du_CurrentAddr+2(a3),du_TxBuff+8(a3)
		move.w	IOS2_PACKETTYPE+2(a2),d0
		cmp.w	#1500,d0
		bhi.b	1$
		move.w	IOS2_DATALENGTH+2(a2),d0	;IEEE802.3 packet length

1$		move.w	d0,du_TxBuff+12(a3)

		move.l	IOS2_DATALENGTH(a2),d0
		move.l	IOS2_DATA(a2),a1
		lea	du_TxBuff+14(a3),a0
		movem.l	d2-d7/a2-a6,-(sp)
		move.l	IOS2_BUFFERMANAGEMENT(a2),a2
		move.l	cookie_CopyFromBuff(a2),a2
		jsr	(a2)
		movem.l	(sp)+,d2-d7/a2-a6
		tst.l	d0
		beq	tx_buffm_error
		moveq	#14,d0
		add.l	IOS2_DATALENGTH(a2),d0
		bra.b	do_send_packet

raw_packet	move.l	IOS2_DATALENGTH(a2),d0
		move.l	IOS2_DATA(a2),a1
		lea	du_TxBuff(a3),a0
		movem.l	d2-d7/a2-a6,-(sp)
		move.l	IOS2_BUFFERMANAGEMENT(a2),a2
		move.l	cookie_CopyFromBuff(a2),a2
		jsr	(a2)
		movem.l	(sp)+,d2-d7/a2-a6
		tst.l	d0
		beq	tx_buffm_error

		move.l	IOS2_DATALENGTH(a2),d0

do_send_packet	move.l	d0,du_TxLength(a3)

		ifd	DEBUG
		DMSG	<'Actually send packet, length = %ld',LF>
		endc

		move.l	du_BoardAddr(a3),a1
		move.b	du_TPStart(a3),d1
		lsl.w	#8,d1
		add.w	d1,a1		; max. TPStart value is $7f

		move.w	d0,d1
		addq.w	#3,d1
		lsr.w	#2,d1		;# of longwords
		lea	du_TxBuff(a3),a0
		bra.b	tx_copy_loop1

tx_copy_loop	move.l	(a0)+,(a1)+
tx_copy_loop1	dbf	d1,tx_copy_loop

		moveq	#64,d1
		cmp.l	d1,d0		;force minimum packet size to 64 bytes
		bcc.b	1$		;(+CRC)
		moveq	#64,d0

1$		move.l	du_BoardAddr1(a3),a0
		move.b	du_TPStart(a3),NIC_TPSR(a0)	;transmit page
		NIC_Delay
		move.b	d0,NIC_TBCR0(a0)		;transmit byte count low
		NIC_Delay
		lsr.w	#8,d0
		move.b	d0,NIC_TBCR1(a0)		;transmit byte count high
		NIC_Delay
; send packet
		move.b	#CRF_NODMA!CRF_TRANSMIT!CRF_START,NIC_CR(a0)
		NIC_Delay
		rts

tx_buffm_error	clr.l	du_CurrentTxReq(a3)	;(not really necessary)
		bclr	#UNITB_CURRENTTX,UNIT_FLAGS(a3)

		moveq	#S2EVENT_ERROR!S2EVENT_TX!S2EVENT_BUFF,d0
		bsr	DoEvent

		move.b	#S2ERR_SOFTWARE,d0
		move.b	#S2WERR_BUFF_ERROR,d1
		bra	IOError


;
; Read the counters 0/1/2
; device base in a6, unit in a3
;
; (note: the counters reset when read)
;
ReadTallyCounters
		move.l	a6,-(sp)
		move.l	dev_SysBase(a6),a6
		lib	Disable
		move.l	du_BoardAddr1(a3),a0
		moveq	#0,d0

		move.b	NIC_CNTR0(a0),d0
		add.l	d0,du_Cntr0(a3)
		NIC_Delay

		move.b	NIC_CNTR1(a0),d0
		add.l	d0,du_Cntr1(a3)
		NIC_Delay

		move.b	NIC_CNTR2(a0),d0
		add.l	d0,du_Cntr2(a3)
		NIC_Delay

		lib	Enable
		move.l	(sp)+,a6
		rts
;
; Ethernet card interrupt routine
;
; IS_DATA is pointer to the device unit structure
;
NIC_IntRoutine	movem.l	d2/d3/d4/a2/a3/a4/a5/a6,-(sp)
		move.l	a1,a3
		move.l	du_DevicePtr(a3),a6
		move.l	du_BoardAddr1(a3),a4
		moveq	#0,d0
		move.b	NIC_ISR(a4),d0
		NIC_Delay
		and.b	#$3f,d0
		beq	nic_int_continue	;next interrupt server

		ifd	DEBUG
		DMSG	<'Interrupt, ISR = $%lx',LF>
		endc

		btst	#ISRB_OVW,d0
		bne	rec_buffer_overflow

		btst	#ISRB_PTX,d0
		bne	transmit_ok
		btst	#ISRB_TXE,d0
		bne	transmit_err

		btst	#ISRB_PRX,d0
		bne.b	receive_ok
		btst	#ISRB_RXE,d0
		bne	receive_err

		btst	#ISRB_CNT,d0
		beq	nic_int_ok

		move.b	#ISRF_CNT,NIC_ISR(a4)
		NIC_Delay

		bsr	ReadTallyCounters

		bra	nic_int_ok

receive_ok	move.b	#ISRF_PRX,NIC_ISR(a4)		; clear interrupt
		NIC_Delay

receive_packet	moveq	#0,d0
		move.b	du_NextPkt(a3),d0

		move.b	#CRF_PAGE0!CRF_NODMA!CRF_START,NIC_CR(a4)	;page 1
		NIC_Delay
		move.b	NIC_CURR(a4),d1
		NIC_Delay
		move.b	#CRF_NODMA!CRF_START,NIC_CR(a4)			;page 0
	 	NIC_Delay
		cmp.b	d0,d1
		beq	nic_int_ok

		moveq	#0,d0
		move.b	du_NextPkt(a3),d0
		lsl.w	#8,d0
		move.l	du_BoardAddr(a3),a4	; added by JM 940217 (found by TR)
		add.l	d0,a4			; changed to add.l by JM 940217

		ifd	DEBUG
		move.l	a4,d0
		move.l	(a4),d1
		DMSG	<'receive ok, Buffer addr = $%lx, first longword = $%lx',LF>
		endc
;
; should we check receive status here? bad packets are discarded anyway...
;

;
; 00	 - next page number
; 01	 - receive status
; 02..03 - packet length
; 04..09 - dest. address
; 0a..0f - src. address
; 10..11 - packet type
; 12..   - packet data
;

		move.w	2(a4),d2	; packet length
		ror.w	#8,d2		; fix byteorder

		cmp.w	#1518,d2
		bhi	next_packet	; drop the packet if too long
; (probably should increment some statistics when dropping oversized packets)

		ifd	DEBUG
		move.l	4(a4),d0
		moveq	#0,d1
		move.w	4+4(a4),d1
		DMSG	<'Dest. addr %08lx%04lx',LF>
		endc

		move.w	4(a4),d0	; (don't access card memory as bytes)
		btst	#8,d0		; check multicast flag
		beq	get_packet_type

		ifd	DEBUG
		DMSG	<'Multicast or broadcast',LF>
		endc

		moveq	#-1,d0		; check broadcast
		cmp.l	4(a4),d0
		bne.b	rec_multicast
		cmp.w	4+4(a4),d0
		beq	get_packet_type	; broadcast
;
; received a multicast packet. do filtering here
;
rec_multicast	ifd	DEBUG
		DMSG	<'Received a multicast packet',LF>
		endc

		lea	4(a4),a0
		bsr	find_multicast
		tst.l	d0
		bne.b	received_multicast_ok

		addq.l	#1,du_BadMultiCastFilterCount(a3)
		ifd	DEBUG
		DMSG	<'Bad multicast filtering',LF>
		endc
		bra	next_packet

received_multicast_ok
		ifd	DEBUG
		DMSG	<'Received multicast ok',LF>
		endc

get_packet_type
;
; increment the du_PacketsReceived count for every packet (even the
; dropped ones)
;
		addq.l	#1,du_PacketsReceived(a3)

		move.w	$10(a4),d3	; get packet type

		ifd	DEBUG
		move.l	d3,d0
		ext.l	d0
		DMSG	<'Packet type = $%lx',LF>
		endc

		moveq	#0,d4		;Packet copied/received-flag

		cmp.w	#1500,d3
		bhi.b	find_ethernet_ioreq

;
; IEEE802.3 packet
;
		move.w	#1500,d3
		move.l	du_CookieList+MLH_HEAD(a3),a5

find_ieee802_cookie_loop
		tst.l	(a5)
		beq	rec_done

		move.l	cookie_RxQueue+MLH_HEAD(a5),a2

find_ieee802_loop
		tst.l	(a2)
		beq	find_ieee802_cookie_next

		cmp.w	IOS2_PACKETTYPE+2(a2),d3
		bcs.b	find_ieee802_next

		tst.b	d4
		bne.b	1$
		bsr	CopyRecPacket
		moveq	#1,d4		;set packet copied-flag

1$		move.l	cookie_PacketFilter(a5),d0
		beq	get_rec_packet1
		move.l	d0,a0
;
; call the packet filter hook
;
; hmm... the iorequest address just
; happens to be in a2 as the callback expects it...
;
		lea	du_RxBuff+14(a3),a1
		btst	#SANA2IOB_RAW,IO_FLAGS(a2)
		beq.b	2$
		sub.w	#14,a1
2$		movem.l	d2-d7/a2-a6,-(sp)
		move.l	h_Entry(a0),a3
		jsr	(a3)
		movem.l	(sp)+,d2-d7/a2-a6
		tst.l	d0
		beq.b	find_ieee802_next

get_rec_packet1	bsr	ReturnRecIOReq
		moveq	#-1,d4		;packet received

find_ieee802_cookie_next
		move.l	(a5),a5
		bra.b	find_ieee802_cookie_loop

find_ieee802_next
		move.l	(a2),a2
		bra.b	find_ieee802_loop


;
; Try to find a 'normal' ethernet iorequest with the
; same packet type as the received packet
;
find_ethernet_ioreq
		ifd	DEBUG
		DMSG	<'find_ethernet_ioreq',LF>
		endc

		move.l	du_CookieList+MLH_HEAD(a3),a5

find_rec_ioreq_cookie_loop
		tst.l	(a5)
		beq	rec_done

		ifd	DEBUG
		move.l	a5,d0
		DMSG	<'find_ethernet_ioreq_cookie_loop ($%lx)',LF>
		endc

		move.l	cookie_RxQueue+MLH_HEAD(a5),a2

find_rec_ioreq_loop
		tst.l	(a2)
		beq	find_rec_ioreq_cookie_next

		ifd	DEBUG
		move.l	a2,d0
		DMSG	<'find_ethernet_ioreq_loop ($%lx)',LF>
		endc

		cmp.w	IOS2_PACKETTYPE+2(a2),d3
		bne.b	find_rec_ioreq_next
		tst.b	d4
		bne.b	1$
		bsr	CopyRecPacket
		moveq	#1,d4		;set packet copied-flag

1$		move.l	cookie_PacketFilter(a5),d0
		beq.b	get_rec_packet2
		move.l	d0,a0
;
; call the packet filter hook
;
; hmm... the iorequest address just
; happens to be in a2 as the callback expects it...
;
		lea	du_RxBuff+14(a3),a1
		btst	#SANA2IOB_RAW,IO_FLAGS(a2)
		beq.b	2$
		sub.w	#14,a1
2$		movem.l	d2-d7/a2-a6,-(sp)
		move.l	h_Entry(a0),a3
		jsr	(a3)
		movem.l	(sp)+,d2-d7/a2-a6
		tst.l	d0
		beq.b	find_rec_ioreq_next

get_rec_packet2	bsr	ReturnRecIOReq
		moveq	#-1,d4		;packet received

find_rec_ioreq_cookie_next
		move.l	(a5),a5	
		bra	find_rec_ioreq_cookie_loop

find_rec_ioreq_next
		move.l	(a2),a2
		bra	find_rec_ioreq_loop

rec_done	tst.w	d4
		bmi	next_packet

;
; handle orphan packets here
;
		ifd	DEBUG
		DMSG	<'Orphan packet',LF>
		endc

		move.l	du_RxOrphanQueue+MLH_TAILPRED(a3),a2
		tst.l	MLN_PRED(a2)
		beq	drop_orphan

		tst.b	d4
		bne.b	1$
		bsr	CopyRecPacket

1$		bsr	ReturnRecIOReq
		bra	next_packet

drop_orphan
		ifd	DEBUG
		DMSG	<'Packet dropped',LF>
		endc
;
; do type tracking for orphan packets here
; packet type is now in d0
;
		move.l	du_TypeTrackList(a3),a1
		cmp.w	#1500,d0
		bhi.b	orphan_track_find_loop
		moveq	#0,d0		;ieee802.3

orphan_track_find_loop
		move.l	(a1),d1
		beq.b	orphan_track_done
		cmp.w	ttn_Type(a1),d0
		beq.b	orphan_track_found
		move.l	d1,a1
		bra.b	orphan_track_find_loop

orphan_track_found
		ifd	DEBUG
		DMSG	<'Incrementing TrackType packet drop count',LF>
		endc

		addq.l	#1,ttn_Stat+S2PTS_PACKETSDROPPED(a1)

orphan_track_done
		addq.l	#1,du_UnknownTypesReceived(a3)
	;;;	bra.b	next_packet

oversize_packet	;;;addq.l	#1,du_Overruns(a3)
		; increment the overrun counter only when there is
		; a receive buffer ring overflow...not here...

	;;	maybe add DoEvent(S2EVENT_RX) here...

next_packet	move.w	(a4),d0
		lsr.w	#8,d0

		ifd	DEBUG
		ext.l	d0
		DMSG	<'Next buffer page = $%lx',LF>
		endc

		move.b	d0,du_NextPkt(a3)
		subq.b	#1,d0
		cmp.b	du_PStart(a3),d0
		bcc.b	1$			; was bge (fix by JM 940217)
		move.b	du_PStop(a3),d0
		subq.b	#1,d0
1$		move.l	du_BoardAddr1(a3),a4
		move.b	d0,NIC_BNDRY(a4)

		NIC_Delay

		ifd	DEBUG
		DMSG	<'New Boundary value = $%lx',LF>
		endc
;
; go back checking if there are any other packets in the buffer ring
;
		bra	receive_packet

;
; receive error. should probably increment some statistics
;
receive_err
		ifd	DEBUG
		DMSG	<'Receive error',LF>
		endc

		addq.l	#1,du_BadPackets(a3)
		move.b	#ISRF_RXE,NIC_ISR(a4)
		NIC_Delay

		moveq	#S2EVENT_ERROR!S2EVENT_RX!S2EVENT_HARDWARE,d0
		bsr	DoEvent
		bra	nic_int_ok

transmit_err
transmit_ok	and.b	#%1010,d0
		move.b	d0,NIC_ISR(a4)		;clear interrupt
		NIC_Delay

		ifd	DEBUG
		DMSG	<'Transmit complete interrupt ($%lx)',LF>
		endc

		bclr	#UNITB_CURRENTTX,UNIT_FLAGS(a3)
		beq	nic_int_ok	; should not happen

;
; record number of collisions
;
		moveq	#0,d1
		move.b	NIC_NCR(a4),d1
		and.b	#%1111,d1
		add.l	d1,du_Collisions(a3)

; Set IO_ERROR/WIREERROR if an error has been detected
; What is a good error number here??
		btst	#3,d0
		beq.b	tx_ok
		move.l	du_CurrentTxReq(a3),a0
		move.b	#S2ERR_NO_RESOURCES,IO_ERROR(a0)
		clr.b	IOS2_WIREERROR(a0)

		move.l	#S2EVENT_ERROR!S2EVENT_TX!S2EVENT_HARDWARE,d0
		bsr	DoEvent
		bra.b	term_tx

tx_ok		addq.l	#1,du_PacketsSent(a3)
;
; do type tracking for transmitted packets
;
		move.l	du_TypeTrackList(a3),a1
		move.w	du_TxBuff+12(a3),d0
		cmp.w	#1500,d0
		bhi.b	tx_track_loop
		moveq	#0,d0		;ieee802.3

tx_track_loop	move.l	(a1),d1
		beq.b	term_tx
		cmp.w	ttn_Type(a1),d0
		beq.b	tx_track_found
		move.l	d1,a1
		bra.b	tx_track_loop

tx_track_found
		ifd	DEBUG
		DMSG	<'Updating TrackType TX stats',LF>
		endc

		addq.l	#1,ttn_Stat+S2PTS_TXPACKETS(a1)
		moveq	#14,d1
		move.l	du_TxLength(a3),d0
		sub.l	d1,d0
		add.l	d0,ttn_Stat+S2PTS_TXBYTES(a1)

term_tx		move.l	du_CurrentTxReq(a3),a2
		bsr	TermIO

		lea	du_TxQueue(a3),a0
		lib	Exec,RemHead		;was RemTail
		move.l	d0,du_CurrentTxReq(a3)
		beq	nic_int_ok

		move.l	d0,a2
		bclr	#IOB_QUEUED,IO_FLAGS(a2)

		ifd	DEBUG
		DMSG	<'Send from TxQueue',LF>
		endc

		bset	#UNITB_CURRENTTX,UNIT_FLAGS(a3)
		bsr	ActualSendPacket
		bra	nic_int_ok

;
; Handle receive buffer overflow here
;
rec_buffer_overflow
		ifd	DEBUG
		DMSG	<'Receive buffer ring overflow',LF>
		endc

		addq.l	#1,du_Overruns(a3)

		move.b	NIC_CR(a4),d2			; store TXP bit
		NIC_Delay
		move.b	#CRF_NODMA!CRF_STOP,NIC_CR(a4)	; stop the NIC
;
; 1.6 ms delay here !!
; (It might be better to do this wait outside the interrupt,
; but this is a low-priority interrupt,
; it shouldn't affect serial receive, for example)
;
		move.w	#2000-1,d0
busy_loop	NIC_Delay	; read a CIA location
		dbf	d0,busy_loop

;
; clear remote byte count registers
;
		moveq	#0,d0
		move.b	d0,NIC_RBCR0(a4)
		NIC_Delay
		move.b	d0,NIC_RBCR1(a4)
		NIC_Delay
;
; check if resend is needed
;
		btst	#CRB_TRANSMIT,d2
		beq.b	recb1

		move.b	NIC_ISR(a4),d0		; read interrupt status
		NIC_Delay
		and.b	#ISRF_PTX!ISRF_TXE,d0	; completed?
		beq.b	recb1

		clr.b	d2			; clear resend flag

recb1		move.b	#TCRF_LB1,NIC_TCR(a4)		; loopback mode
		NIC_Delay
		move.b	#CRF_NODMA!CRF_START,NIC_CR(a4)	; start the NIC
		NIC_Delay
;
; Now remove all packets from the receive buffer ring (!!)
; (This discards some good packets...)
;
		move.b	#CRF_PAGE0!CRF_NODMA!CRF_START,NIC_CR(a4)	;page1
		NIC_Delay
		move.b	NIC_CURR(a4),d0
		move.b	#CRF_NODMA!CRF_START,NIC_CR(a4)			;page0
		NIC_Delay
		move.b	d0,du_NextPkt(a3)
		subq.b	#1,d0
		cmp.b	du_PStart(a3),d0
		bge.b	1$
		move.b	du_PStop(a3),d0
		subq.b	#1,d0
1$		move.l	du_BoardAddr1(a3),a4
		move.b	d0,NIC_BNDRY(a4)
		NIC_Delay

		move.b	#ISRF_OVW,NIC_ISR(a4)		; clear the interrupt
		NIC_Delay
		move.b	#0,NIC_TCR(a4)	; loopback off
		NIC_Delay

		btst	#CRB_TRANSMIT,d2
		beq.b	overflow_ok
;
; retransmit the current packet
;
		move.b	#CRF_NODMA!CRF_TRANSMIT!CRF_START,NIC_CR(a4)
		NIC_Delay
overflow_ok	move.l	#S2EVENT_ERROR!S2EVENT_RX!S2EVENT_HARDWARE,d0
		bsr	DoEvent
;
;
nic_int_ok	moveq	#1,d0
		bra.b	nic_int_end

nic_int_continue
		moveq	#0,d0

nic_int_end	movem.l	(sp)+,d2/d3/d4/a2/a3/a4/a5/a6
		rts

;
; copy packet to du_RxBuff -- used by the receive interrupt
;
; d2 -- packet length
; a2 -- iorequest (not actually used by this routine)
; a3 -- unit
; a4 -- pointer to the card's RAM buffer at the start of this packet
;
CopyRecPacket
		ifd	DEBUG
		move.l	a2,d0
		move.l	d2,d1
		DMSG	<'Copy packet (iorequest = $%lx, packet length = %ld)',LF>
		endc

		move.b	du_PStop(a3),d0
		sub.b	du_NextPkt(a3),d0
		lsl.w	#8,d0
		subq.w	#4,d0
; space from packet start to buffer RAM end, in bytes
; (four bytes of status information before the packet not counted)
; compare with packet length
		cmp.w	d0,d2
		bhi	rec_wrap

		ifd	DEBUG
		ext.l	d0
		DMSG	<'Receive with no wrap (space $%lx)',LF>
		endc

		lea	4(a4),a0
		lea	du_RxBuff(a3),a1
		move.w	d2,d0		;packet length
		addq.w	#3,d0
		lsr.w	#2,d0	;number of longwords

		ifd	DEBUG
		DMSG	<'Receive copy1 length = $%lx longwords',LF>
		endc
		bra.b	rec_copy1_entry

rec_copy1_loop	move.l	(a0)+,(a1)+
rec_copy1_entry	dbf	d0,rec_copy1_loop
		bra	packet_copied

rec_wrap
		ifd	DEBUG
		ext.l	d0
		DMSG	<'Receive packet buffer wrap (space $%lx)',LF>
		endc

		lea	4(a4),a0
		lea	du_RxBuff(a3),a1
		move.w	d0,d1
		lsr.w	#2,d0

		ifd	DEBUG
		DMSG	<'Receive copy2 length = $%lx longwords',LF>
		endc
		bra.b	rec_copy2_entry

rec_copy2_loop	move.l	(a0)+,(a1)+
rec_copy2_entry	dbf	d0,rec_copy2_loop

		moveq	#0,d0
		move.b	du_PStart(a3),d0
		lsl.w	#8,d0
		move.l	du_BoardAddr(a3),a0
		add.l	d0,a0			; changed to add.l by JM 940217

		ifd	DEBUG
		move.l	a0,d0
		DMSG	<'Wrap, continue at $%lx',LF>
		endc

		move.w	d2,d0	;packet length
		sub.w	d1,d0
		addq.w	#3,d0
		lsr.w	#2,d0

		ifd	DEBUG
		DMSG	<'Receive copy3 length = $%lx longwords',LF>
		endc
		bra.b	rec_copy3_entry

rec_copy3_loop	move.l	(a0)+,(a1)+
rec_copy3_entry	dbf	d0,rec_copy3_loop

packet_copied
;
; type tracking for received packets
;
		move.l	du_TypeTrackList(a3),a1
		move.w	du_RxBuff+12(a3),d0
		cmp.w	#1500,d0
		bhi.b	rec_track_find_loop
		moveq	#0,d0		;ieee802.3

rec_track_find_loop
		move.l	(a1),d1
		beq.b	track_ret
		cmp.w	ttn_Type(a1),d0
		beq.b	rec_track_found
		move.l	d1,a1
		bra.b	rec_track_find_loop

rec_track_found
		ifd	DEBUG
		DMSG	<'Updating TrackType RX stats',LF>
		endc

		addq.l	#1,ttn_Stat+S2PTS_RXPACKETS(a1)
		moveq	#0,d0
		move.w	d2,d0
		sub.w	#18,d0
		add.l	d0,ttn_Stat+S2PTS_RXBYTES(a1)

track_ret	rts

;
; D2 - packet length
; A2 - pointer to IORequest
; A3 - pointer to unit structure
;
ReturnRecIOReq	moveq	#-1,d0
		cmp.l	du_RxBuff(a3),d0
		bne.b	1$
		cmp.w	du_RxBuff+4(a3),d0
		bne.b	1$
		bset	#SANA2IOB_BCAST,IO_FLAGS(a2)
1$		bra.b	2$

		btst	#0,du_RxBuff(a3)
		beq.b	2$
		bset	#SANA2IOB_MCAST,IO_FLAGS(a2)
2$
		move.l	du_RxBuff(a3),IOS2_DSTADDR(a2)
		move.w	du_RxBuff+4(a3),IOS2_DSTADDR+4(a2)
		move.w	du_RxBuff+6(a3),IOS2_SRCADDR(a2)
		move.l	du_RxBuff+8(a3),IOS2_SRCADDR+2(a2)
		move.w	du_RxBuff+12(a3),IOS2_PACKETTYPE+2(a2)

		moveq	#0,d0
		move.w	d2,d0
		sub.w	#18,d0
		ext.l	d0
		lea	du_RxBuff+14(a3),a1
		
		btst	#SANA2IOB_RAW,IO_FLAGS(a2)
		beq.b	3$
		move.w	d2,d0
		sub.w	#14,a1

3$		move.l	d0,IOS2_DATALENGTH(a2)
		move.l	IOS2_DATA(a2),a0
		movem.l	d2-d7/a2-a6,-(sp)
		move.l	IOS2_BUFFERMANAGEMENT(a2),a2
		move.l	cookie_CopyToBuff(a2),a2
		jsr	(a2)
		movem.l	(sp)+,d2-d7/a2-a6
		tst.l	d0
		bne.b	4$

		move.b	#S2ERR_SOFTWARE,IO_ERROR(a2)
		move.b	#S2WERR_BUFF_ERROR,IOS2_WIREERROR+3(a2)

		moveq	#S2EVENT_ERROR!S2EVENT_RX!S2EVENT_BUFF,d0
		bsr	DoEvent

4$		move.l	a2,a1
		lib	Exec,Remove
		bra	TermIO

;;;;
		ifd	DEBUG
;
; Printf-like formatting with output to serial port (with RawPutChar)
; format string in a0, arguments in d0-d7
;
DPrintf		movem.l	a2/a3/a6,-(sp)
		movem.l	d0-d7,-(sp)
		move.l	sp,a1
		lea	PutCh(pc),a2
		move.l	4,a6
		move.l	a6,a3
		lib	RawDoFmt
		lea	8*4(sp),sp
		movem.l	(sp)+,a2/a3/a6
		rts

PutCh		move.l	a6,-(sp)
		move.l	a3,a6
		lib	RawPutChar
		move.l	(sp)+,a6
		rts

		endc	;DEBUG

dev_endskip

		end
