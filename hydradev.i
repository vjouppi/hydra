;
; hydradev.i
;

NUM_UNITS	equ	5
PACKETBUFSIZE	equ	1536
EADDR_BYTES	equ	6

		STRUCTURE Device_Data,DD_SIZE
		 APTR	dev_SegList

		 LABEL	dev_ExecBase
		 APTR	dev_SysBase

		 APTR	dev_ExpansionBase
		 APTR	dev_IntuitionBase
		 STRUCT	dev_UnitTable,NUM_UNITS*4
		LABEL dev_DataSize

		STRUCTURE Device_Unit,UNIT_SIZE
		 ULONG	du_UnitNum
		 APTR	du_DevicePtr
		 STRUCT	du_DefaultAddr,EADDR_BYTES
		 STRUCT	du_CurrentAddr,EADDR_BYTES
		 STRUCT	du_NIC_Intr,IS_SIZE
		 STRUCT	du_TxQueue,MLH_SIZE
		 STRUCT	du_RxQueue,MLH_SIZE
		 STRUCT	du_RxOrphanQueue,MLH_SIZE
		 APTR	du_CurrentTxReq
		 UBYTE	du_PStart		;receive buffer start page
		 UBYTE	du_PStop		;receive buffer end page
		 UBYTE	du_TPStart		;transmit buffer start page
		 UBYTE	du_NextPkt		;next packet to receive (page)
		 APTR	du_ConfigDev
		 APTR	du_BoardAddr
		 APTR	du_BoardAddr1		;boardaddr + $8000
		 ULONG	du_PacketsSent
		 ULONG	du_PacketsReceived
		 ULONG	du_BadPackets
		 ULONG	du_Overruns
		 ULONG	du_SoftMisses
		 ULONG	du_UnknownTypesReceived
		 STRUCT	du_LastStart,TV_SIZE
		 STRUCT	du_TxBuff,PACKETBUFSIZE
		 STRUCT	du_RxBuff,PACKETBUFSIZE
		LABEL du_Sizeof

		BITDEF	UNIT,CONFIGURED,2
		BITDEF	UNIT,ONLINE,3
		BITDEF	UNIT,CURRENTTX,4
		BITDEF	UNIT,EXCLUSIVE,5

;
; an extra IORequest flag
;
		BITDEF	IO,QUEUED,2

;
; Buffer management 'magic cookie'
;
		STRUCTURE BuffManagement,0
		 APTR	buffm_CopyToBuff
		 APTR	buffm_CopyFromBuff
		LABEL buffm_Sizeof

;
