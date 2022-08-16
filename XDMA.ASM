;
; XDMA.ASM    Written 15-Feb-2006 by Jack R. Ellis.
;
; XDMA is free software.   You can redistribute and/or modify it, under
; the terms of the GNU General Public License (hereafter called GPL) as
; published by the Free Software Foundation, either version 2 of GPL or
; any later versions, at your option.   XDMA is distributed in the hope
; that it will be useful, but WITHOUT ANY WARRANTY and without even the
; implied warranties of MERCHANTABILITY nor of FITNESS FOR A PARTICULAR
; PURPOSE!   See the GPL for details.   You should have received a copy
; of the GPL with your XDMA files.   If not, write to the Free Software
; Foundation Inc., 59 Temple Place Ste. 330, Boston, MA 02111-1307 USA.
; http://www.gnu.org/licenses/
;
; This is a DOS driver for UltraDMA hard-disks on PC motherboards using
; a VIA VT8235 or similar chipset.   On loading, the driver finds which
; IDE drives are UltraDMA hard-disks and will run all such disks.   Any
; UltraDMA disks may be used.   LBA and CHS mode requests are accepted.
; "Read/Write Extended" DMA commands are issued for disk addresses over
; 28 bits and require ATA-6 or newer hard-disks.   Disk addresses of 28
; bits or less use normal DMA commands.   The driver handles BIOS Int13
; read or write requests only.   Other Int13 requests (including seeks)
; and I-O requests having bad parameters are "passed" back to the BIOS.
; If an input buffer is not 32-bit aligned, crosses a 64K DMA boundary,
; or fails VDS "lock", data will go through an XMS memory buffer, using
; UltraDMA to/from the buffer.   HIMEM.SYS or a similar XMS manager and
; 128K of XMS memory are required for use.   XDMA offers output overlap
; which buffers ALL output and does NOT await output end, so user tasks
; may "overlap" DMA!   On output errors or if a 400-msec timer expires,
; an error message is displayed.   Overlap must be enabled using the /O
; switch (see below).   Overlap requires that each IDE channel must NOT
; run an UltraDMA disk and a non-UltraDMA or ATAPI drive (CD-ROM etc.)!
; Other drivers are unaware XDMA leaves output "running" and could post
; controller-busy ERRORS!   NOTE:  The XCDROM driver DOES support using
; an UltraDMA disk and a CD-ROM drive on the same IDE channel!
;
; XDMA switch options are as follows:
;
;   /O   Enables output overlap.
;
;   /L   Limits DMA to "low memory" below 640K.   /L is REQUIRED to use
;	   UMBPCI or any similar driver whose upper-memory areas do not
;	   allow DMA.   If /L is used, the driver must be in LOW memory
;	   so DMA command-lists are fetched properly, or driver loading
;	   will ABORT!   /L causes I-O requests past 640K to go through
;	   the driver's XMS buffer.
;
;   /Q   Suppresses the "beep" on output-overlap errors ("quiet" mode).
;
; For each switch, a dash may replace the slash, and lower-case letters
; may be used.
;
; On exit from successful I-O requests, the AH-register is zero and the
; carry flag is reset.   If an error occurs, the carry flag is SET, and
; the AH-register has one of the following codes:
;
;	Code 08h - DMA timed out.
;	     0Fh - DMA error.
;	     20h - Controller busy before I-O.
;	     21h - Controller busy after I-O.
;	     AAh - Disk not ready before I-O.
;	     ABh - Disk not ready after I-O.
;	     CCh - Disk FAULT before I-O.
;	     CDh - Disk FAULT after I-O.
;	     E0h - Hard error at I-O end.
;	     FFh - XMS memory error.
;
; When output overlap is enabled, run-time output errors will cause the
; following message to display, accompanied by a short "beep" sound:
;
;	XDMA Error eeh, Disk=d LBA=aaaaaaaaaaaah!
;
; where eeh is one of the error codes shown above, d is the disk number
; (0 if primary-master, 1 if primary-slave, 2 if secondary-master, or 3
; if secondary-slave) and aaaaaaaaaaaah shows the starting disk address
; expressed as a 12-digit "logical block address" (LBA).
;
;
; Revision History:
; ----------------
;  v3.4  08.2022: removed driver stack.
;                 enable busmaster in pci controller if not set
;                 fixed VDS bug ( VDS host may modify "size" field )
;                 enable max UDMA mode in drive ( using "set feature" )

;  V3.3  15-Feb-06   JRE   Deleted /B /M /N /S switches.   XDMAJR dis-
;			     continued (XDMA is now under 2.5K bytes).
;  V3.2  31-Jan-06   JRE   Deleted init "Set Mode" commands to prevent
;			     conflicts.   NO run-time changes.
;  V3.1  26-Dec-05   JRE   XDMA with overlap is now named "XDMA1$", so
;			     other drivers can call "OCheck".    Minor
;			     XDMA/XDMAJR updates.   NO size changes.
;  V3.0  15-Dec-05   JRE   XDMA/XDMAJR now set "XDMA_$" names (overlap
;			     XDMA sets "XDMA$$") to confirm controller
;			     address valid.
;  V2.9  14-Dec-05   JRE   XDMA output overlap "re-entry" logic fixed.
;			     No change to non-overlap XDMA nor XDMAJR.
;  V2.8  27-Nov-05   JRE   XDMA and XDMAJR "Internationalized"!   Init
;			     messages are now a separate file; default
;			     is XDMAMSGS.ENG, which has full details.
;  V2.7  24-Nov-05   JRE   XDMA output-overlap posts IDE channel busy/
;                            overlap flags, so overlap WILL work using
;			     other IDE drivers that test XDMA's flags!
;			     NO changes to XDMAJR or non-overlap XDMA.
;  V2.6  17-Nov-05   JRE   XDMA/XDMAJR now have a /N switch to request
;			     NO local-stack.    XDMA.ASM now assembles
;			     EITHER driver!    DRQ-timeout replaced by
;			     DMA-timeout code in error handling logic.
;  V2.5  10-Nov-05   JRE   Re-added /B /S and "DMA only" mode to XDMA.
;			     Re-added /S to XDMAJR.    But for no read
;			     tests XDMA/XDMAJR now equal UDMA2/UDMA2S!
;  V2.4   5-Nov-05   JRE   README.TXT updated with "advisory" RULES on
;			     UMBPCI use.   Minor XDMA/XDMAJR changes.
;  V2.3   2-Nov-05   JRE   Many XDMA/XDMAJR improvements (see README).
;			     XDMAJR upgraded with all but overlap.
;  V2.2  23-Oct-05   JRE   Fixed stack-switching error in XDMA/XDMAJR.
;  V2.1  21-Oct-05   JRE   Fixed XDMA /M error.  No changes to XDMAJR.
;  V2.0  15-Oct-05   JRE   XDMA smaller, re-added XDMAJR disk "names".
;  V1.9  10-Oct-05   JRE   Fixed XDMAJR "no-disks" error.  Other minor
;			     items to improve subroutine reliability.
;  V1.8   2-Oct-05   JRE   Re-added 80386+ check, fixed EDD disk scan.
;  V1.7  24-Sep-05   JRE   Re-added "hardware only" disk scan in XDMA,
;			     for IBM ThinkPad etc.; no XDMAJR changes.
;  V1.6  15-Sep-05   JRE   NASM sources; fixed XDMAJR LBA-mode errors.
;  V1.5  22-Aug-05   JRE   Added small/simple XDMAJR; no XDMA changes.
;  V1.4  18-Aug-05   JRE   Fixed ES-reg. error, minimized "init" code.
;  V1.3   3-Aug-05   JRE   Added David Muller's ALi class-code and 30-
;			     byte EDD BIOS changes.  THANK YOU, David!
;  V1.2  30-Jun-05   JRE   Fixed "forward code-modification" errors.
;  V1.1  18-Jun-05   JRE   Simpler README file; added version number.
;  V1.0  15-Jun-05   JRE   Original issue.
;
;
; General Program Equations.
;
%define	VER	' V3.4, 14.08.2022'
%if 0
BSTACK	equ	304		;"Basic" driver local-stack length.
OSTACK	equ	348		;Overlap driver local-stack length.
%endif
RDYTO	equ	008h		;389-msec minimum I-O timeout.
BIOSTMR equ	0046Ch		;BIOS "tick" timer address.
HDISKS	equ	00475h		;BIOS hard-disk count address.
VDSFLAG equ	0047Bh		;BIOS "Virtual DMA" flag address.
CR	equ	00Dh		;ASCII carriage-return.
LF	equ	00Ah		;ASCII line-feed.
;
; Driver Return Codes.
;
DMATIMO equ	0E8h		;DMA timeout code, 008h at exit.
DMAERR	equ	0EFh		;DMA error   code, 00Fh at exit.
CTLRERR equ	000h		;Ctlr. busy  code, 020h/021h at exit.
DISKERR equ	08Ah		;Disk-busy   code, 0AAh/0ABh at exit.
FAULTED	equ	0ACh		;Disk FAULT  code, 0CCh/0CDh at exit.
HARDERR equ	0BFh		;Hard-error  code, 0E0H at exit.
XMSERR	equ	0FFh		;XMS memory-error code.
;
; IDE Controller Register Definitions.
;
CDATA	equ	001F0h		;Data port.
CSECCT	equ	CDATA+2		;I-O sector count.
CDSEL	equ	CDATA+6		;Disk-select and upper LBA.
CCMD	equ	CDATA+7		;Command register.
CSTAT	equ	CDATA+7		;Primary status register.
CSTAT2	equ	CDATA+206h	;Alternate status register.
;
; Controller Status and Command Definitions.
;
BSY	equ	080h		;IDE controller is busy.
RDY	equ	040h		;IDE disk is "ready".
FLT	equ	020h		;IDE disk has a "fault".
DRQ	equ	008h		;IDE data request.
ERR	equ	001h		;IDE general error flag.
DMI	equ	004h		;DMA interrupt occured.
DME	equ	002h		;DMA error occurred.
DRCMD	equ	0C8h		;DMA read command (write is 0CAh,
				;    LBA48 commands are 025h/035h).
LBABITS equ	0E0h		;Fixed LBA command bits.
;
; LBA "Device Address Packet" Layout.
;
struc	DAP
DapPL	resb	1		;Packet length.
	resb	1		;(Reserved).
DapSC	resb	1		;I-O sector count.
	resb	1		;(Reserved).
DapBuf	resd	1		;I-O buffer address (segment:offset).
DapLBA	resw	1		;48-bit logical block address (LBA).
DapLBA1	resd	1
endstruc
;
; DOS "Request Packet" Layout.
;
struc	RP
	resb	2		;(Unused by us).
RPOp	resb	1		;Opcode.
RPStat	resw	1		;Status word.
	resb	9		;(Unused by us).
RPSize	resd	1		;Resident driver size.
RPCL	resd	1		;Command-line data pointer.
endstruc
RPERR	equ	08003h		;Packet "error" flags.
RPDON	equ	00100h		;Packet "done" flag.
;
; DOS Driver Device Header.
;
@	dd	0FFFFFFFFh	;Link to next header block.
	dw	08000h		;Driver "device attributes".
	dw	Strat		;"Strategy" routine offset.
Timer	equ	$-2		;(400-msec timeout counter after Init).
IDEAd	equ	$-1		;(Lower IDE status address after Init).
	dw	DevInt		;"Device-Interrupt" routine offset.
DMAAd	equ	$-2		;(DMA command-reg. address after Init).
DvrName	db	'XDMA1$',0	;Driver name ("XDMA$" without overlap).
				;NOTE:  XDMA1$ confirms location 8 has
				;  a valid controller address and that
				;  location 12h has IDE channel "busy"
				;  flags.    XDMA1$ also confirms that
				;  "OCheck" is useable with a far call
				;  to XDMA location 0314h.   All these
				;  locations are FIXED, FOREVER!
;
; Resident Driver "Data Page" Variables.   The 0BAh/0B0h bytes in the
;   init class-code "interface byte" table (SecCt2) are for ALi M5529
;   chips.   MANY THANKS to David Muller for this VALUABLE upgrade!
;
VLF	db	0		;VDS "lock" flag (DvrName byte 8).
Flags	db	0		;I-O and IDE channel "busy" flags:
				;  080h = I-O request or timer busy.
				;  040h = Secondary channel is busy.
				;  020h = Secondary channel overlap.
				;  010h = Primary   channel is busy.
				;  008h = Primary   channel overlap.
				;  If overlap disabled, 0FFh = "busy".
ReqBF	db	0		;I-O request channel "busy" flag.
PRDAd	dd	IOAdr		;PRD 32-bit command addr. (Init set).
SecCt2	db	0FAh		;IDE "upper" sector count.
LBA2	db	0F0h,08Ah,080h	;IDE "upper" LBA bits 24-47.
SecCt	db	0BAh		;IDE "lower" sector count.
LBA	db	0B0h,0,0	;IDE "lower" LBA bits 0-23.
DSCmd	db	0		;IDE disk-select and LBA commands.
IOCmd	db	0		;IDE command byte.
XMOfs	dw	0		;XMS 16-bit buffer offset (Init set).
VDSLn	dd	ResEnd		;VDS and XMS buffer length.
VDSOf	dd	0		;VDS 32-bit offset.
VDSSg	dd	0		;VDS 16-bit segment (hi-order zero).
IOAdr	dd	0		;VDS and DMA 32-bit address.
IOLen	dd	080000000h	;DMA byte count and "end" flag.
BiosHD	equ	$-2		;(Number of BIOS disks, during Init).
HDCount	equ	$-3		;(BIOS hard-disk count, during Init).
XMSSH	equ	VDSOf		;(XMS parameters share the VDS block).
XMSDH	equ	VDSSg+2
Units	dd	0FFFFFFFFh	;IDE "active units" table (Init set).
CHSSec	dd	0		;CHS sectors/head   table (Init set).
CHSHd	dd	0		;CHS heads/cylinder table (Init set).
%if 0
CStack	dd	0		;Caller's saved stack pointer.
%endif
;
; Driver Entry Routine.  For CHS requests, the registers contain:
;
;   AH      Request code.  We handle 002h read and 003h write.
;   AL      I-O sector count.
;   CH      Lower 8 bits of starting cylinder.
;   CL      Starting sector and upper 2 bits of cylinder.
;   DH      Starting head.
;   DL      BIOS unit number.  We handle 080h and up (hard-disks).
;   ES:BX   I-O buffer address.
;
; For LBA requests, the registers contain:
;
;   AH      Request code.  We handle 042h read and 043h write.
;   DL      BIOS unit number.  We handle 080h and up (hard-disks).
;   DS:SI   Pointer to Device Address Packet ("DAP"), described above.
;
Entry	push	bp		;Driver entry routine -- save BP-reg.
	mov	bp,1		;Reset active-units table index.
@LastU	equ	$-2		;(Last-unit index, set by Init).
NextU	dec	bp		;Any more active units to check?
	js	QuickX		;No, request NOT for us -- exit quick!
	cmp	dl,[cs:bp+Units-@] ;Does request unit match our table?
	jne	NextU		;No, see if more table entries remain.
	cli			;It's for us!  Disable CPU interrupts.
	push	ax		;Save AX-register for "busy" check.
	mov	ax,bp		;Get driver & request "busy" flags.
	or	al,009h
	inc	ax
	shl	al,4
	test	[cs:Flags],al	;Is driver or desired channel "busy"?
	jz	SetRqBF		;No, set request's "busy" flags.
	pop	ax		;BAAAD News!  Reload AX-register.
	stc			;We're BUSY, you moron!  Post "invalid
	mov	ah,001h		;  function" and exit (most drivers do
	jmp	GetOut		;  NO "re-entry" test and can CRASH!).
SetRqBF	mov	[cs:ReqBF],al	;Set this request's "busy" flags.
	pop	ax		;Reload AX-reg. (saved again below).
%if 0
	mov	[cs:CStack],sp	;Save caller's stack pointer.
	mov	[cs:CStack+2],ss
	push	cs		;Switch to this driver's stack.
	pop	ss
	mov	sp,ResEnd
@Stack	equ	$-2
%endif
	test	byte [cs:Flags],018h  ;Is output overlap running?
	jz	SaveReg		;No, go save all CPU registers.
	push	cs		;Await end of output overlap.
	call	OCheck
SaveReg	pusha			;Save all 16-bit CPU registers.
	cld			;Ensure FORWARD "string" commands.
	mov	dl,0BEh		;Mask out LBA and write request bits.
	and	dl,ah
	cmp	dl,002h		;Is this a CHS or LBA read or write?
	jne	Pass		;No, let BIOS handle this request.
	shl	ah,1		;Is this an LBA read or write request?
	jns	ValSC		;No, go validate CHS sector count.
	mov	al,[si+DapSC]	;Get "DAP" I-O sector count.
	les	dx,[si+DapLBA1]	;Get "DAP" LBA bits 16-47.
	mov	di,es
	les	cx,[si+DapBuf]	;Get "DAP" I-O buffer address.
	cmp	dword [si+DapBuf],byte -1  ;64-bit buffer address?
	mov	si,[si+DapLBA]	;(Get "DAP" LBA bits 0-15).
	jne	ValSC		;No, go validate "DAP" sector count.
Pass	popa			;"Pass" request -- reload all CPU regs.
%if 0
	lss	sp,[cs:CStack]	;Switch back to caller's stack.
%endif
QuickX	mov	bp,sp		;Reload CPU flags saved during Int 13h.
	push	word [bp+6]
	popf
	pop	bp		;Reload BP-register.
	db	0EAh		;Go to next routine in Int 13h chain.
@PrvI13	dd	0		;(Prior INT13 vector, saved by Init).
ValSC	dec	al		;Is sector count zero or over 128?
	js	Pass		;Yes?  Let BIOS handle this "No-No!".
	inc	ax		;Restore sector count -- LBA request?
	js	SaveSeg		;Yes, go save segment registers.
	xchg	ax,cx		;CHS -- save request code and sectors.
	xor	di,di		;Reset upper LBA address bits.
	mov	si,0003Fh	;Set SI-reg. to starting sector.
	and	si,ax
	dec	si
	shr	al,6		;Set AX-reg. to starting cylinder.
	xchg	al,ah
	xchg	ax,dx		     ;Swap cylinder & head values.
	mov	al,[cs:bp+CHSSec-@]  ;Get disk CHS sectors/head value.
	or	al,al		     ;Were disk CHS values legitimate?
	jz	Pass		     ;No?  Let BIOS do this request!
	push	ax		     ;Save CHS sectors/head value.
	mul	ah		     ;Convert head to sectors.
	add	si,ax		     ;Add result to starting sector.
	pop	ax		     ;Reload CHS sectors/head value.
	mul	byte [cs:bp+CHSHd-@] ;Convert cylinder to sectors.
	mul	dx
	add	si,ax		;Add to head/sector value.
	adc	dx,di
	xchg	ax,bx		;Get buffer offset in AX-register.
	xchg	ax,cx		;Swap offset with request/sectors.
SaveSeg	push	ds		;Save CPU segment registers.
	push	es
	push	cs		;Set this driver's DS-register.
	pop	ds
	xor	bx,bx		;Zero BX-reg. for relative commands.
	mov	[bx+LBA+2-@],dl	;Save LBA bits 16-23, to free DL-reg.
	mov	dl,[bx+ReqBF-@]	;Set driver & channel "busy" flags
	or	[bx+Flags-@],dl	;  so other IDE drivers will WAIT!
	sti			;Re-enable CPU interrupts.
	mov	[bx+LBA-@],si	;Save LBA bits 0-15 and 24-47.
	mov	[bx+LBA2-@],dh
	mov	[bx+LBA2+1-@],di
	mov	[bx+VDSOf-@],cx	;Save 32-bit user buffer address.
	mov	[bx+VDSOf+2-@],bx
	mov	[bx+VDSSg-@],es	;Save 16-bit user buffer segment.
	shr	dx,12		;Shift out LBA bits 16-27.
	or	di,dx		;Anything in LBA bits 28-47?
	jnz	LBA48		;Yes, use LBA48 read/write command.
	xchg	dh,[bx+LBA2-@]	;LBA28 -- reload & reset bits 24-27.
	or	ah,(DRCMD+1)	;Get LBA28 read/write command + 5.
	jmp	short GetAdr	;Go get IDE and LBA address bytes.
LBA48	shl	ah,3		;LBA48 -- get command as 020h/030h.
GetAdr	mov	dl,(LBABITS/32)	;Initialize LBA command bits.
	mov	di,(CDSEL-100h)	;Get primary device-address bytes.
@DMALo1	equ	$-1		;(Lower DMA command address, Init set).
	shr	bp,1		;Is this a primary-channel request?
	jz	DevAdr		;Yes, set IDE & PCI address bytes.
	mov	di,(CDSEL+680h)	;Get secondary device-address bytes.
@DMALo2	equ	$-1		;(Lower DMA command address, Init set).
DevAdr	mov	[bx+IDEAd-@],di ;Set current IDE & PCI address bytes.
	rcl	dl,5		;Shift disk-select into LBA commands.
	or	dl,dh		;"Or" in LBA28 bits 24-27 (if any).
	mov	dh,005h		;Get final IDE command byte.
	xor	dh,ah		;(LBA28 = C8h/CAh, LBA48 = 25h/35h).
	mov	[bx+DSCmd-@],dx	;Set LBA and IDE command bytes.
	mov	[bx+SecCt-@],al	;Set I-O sector count.
	mov	ah,0		;Set VDS/XMS and DMA buffer lengths.
	shl	ax,1
	mov	[bx+VDSLn+1-@],ax
	mov	[bx+IOLen+1-@],ax
	test	dh,0			   ;Overlap output request?
@Ovlp1	equ	$-1			   ;(012h if overlap enabled).
	jnz	BufIO			   ;Yes, do buffered output.
        mov es,bx
        test byte [es:47bh],20h
        jz novdslock
	or	dword [bx+IOAdr-@],byte -1 ;Invalidate VDS address.
	mov	ax,08103h		   ;VDS "lock" user buffer.
	mov	dx,0001Ch	; no automatic remap, check 64 kB crossing
	call	VDLock
	jnc vdslock_ok
	mov ax,[bx+IOLen-@]    ;if C, the length field was modified
	mov [bx+VDSLn-@],ax
	mov al,[bx+IOLen+2-@]
	mov [bx+VDSLn+2-@],al
	jmp BufIO			   ;Error -- do buffered I-O.
vdslock_ok:
	mov	ax,[bx+IOAdr-@]		   ;Get lower VDS address.
	cmp	dword [bx+IOAdr-@],byte -1 ;Is VDS address valid?
	jb	SetVLF			   ;Yes, set VDS "lock" flag.
novdslock:
	mov	ax,16		;No VDS -- get 20-bit buffer segment.
	mul	word [bx+VDSSg-@]
	add	ax,[bx+VDSOf-@]	;Add in buffer offset value.
	adc	dx,bx
	mov	[bx+IOAdr-@],ax	;Set 20-bit user buffer address.
	mov	[bx+IOAdr+2-@],dx
SetVLF:
;	adc	[bx+VLF-@],bl	;Set VDS "lock" flag from carry bit.
	test	al,003h		;Is user I-O buffer 32-bit aligned?
	jnz	NoLock		;No, use buffered I-O routines below.
	mov	cx,[bx+IOLen-@]	;Get lower ending DMA address.
	dec	cx		;(IOLen - 1 + IOAdr).
	add	ax,cx		;Would this I-O cross a 64K boundary?
	jc	NoLock		;Yes, use buffered I-O routines below.
	cmp	word [bx+IOAdr+2-@],byte -1  ;DMA I-O above our limit?
@DMALmt	equ	$-1		;(If 640K limit, set to 009h by Init).
	ja	NoLock		;Yes, use buffered I-O routines below.
	call	DoDMA		;Do direct DMA I-O with user's buffer.
Done	mov	bp,sp		;Done -- point to saved registers.
	mov	[bp+19],al	;Set error code in exiting AH-reg.
	pushf			;Save error flag (carry bit).
;	call	VDUnlk		;If needed, "unlock" user I-O buffer.
	cli			;Disable CPU interrupts.
	mov	al,[bx+ReqBF-@]	;Reset driver & channel "busy" flags
	not	al		;  so other IDE drivers may proceed!
	and	[bx+Flags-@],al
	pop	ax		;Reload error flag into carry bit.
	shr	ax,1
	pop	es		;Reload all CPU registers.
	pop	ds
	popa
%if 0
	lss	sp,[cs:CStack]	;Switch back to caller's stack.
%endif
GetOut	mov	bp,sp		;Point to caller's saved BP-reg.
	rcr	byte [bp+6],1	;Set error flag in exiting carry
	rol	byte [bp+6],1	;  bit, in flags saved by Int 13h.
	pop	bp		;Reload BP-register and exit.
	iret
BufOut	call	XMSMov		;Buffered output -- move data to XMS.
	jc	Done		;If error, post return code & exit!
	call	BufDMA		;Output all data from XMS buffer.
	jmp	short Done	;Done -- post any return code & exit.
NoLock:
;	call	VDUnlk		;Buffered I-O -- "unlock" user buffer.
BufIO	shl	dword [bx+VDSOf-@],16  ;Convert to XMS handle & offset.
	test	byte [bx+IOCmd-@],012h ;Is this a write request?
	jnz	BufOut		;Yes, use output routine above.
	call	BufDMA		;Input all data to driver XMS buffer.
	jc	Done		;If error, post return code & exit!
	call	XMSMov		;Move XMS data to user input buffer.
	jmp	short Done	;Done -- post any return code & exit.
;
; Subroutine to move data to or from the driver's XMS buffer.
;
XMSMov	push	cs		;Point ES-reg. to our data.
	pop	es
	mov	di,XMSDH	;Point to XMS destination field.
	jnz	XMSet		;If output, just set XMS destination!
	mov	si,XMSSH	;Point to XMS user-buffer address.
	push	si
	movsw			;Move user-buffer address from
	movsw			;  XMS source to XMS destination.
	movsw
	pop	di		;Point to XMS source field.
XMSet	mov	si,XMOfs	;Set XMS handle and buffer offset as
	mov	ax,0		;  input source or output destination.
@XMHdl	equ	$-2		;(XMS memory "handle", set by Init).
	stosw
	movsw
	mov	[di],bx
	mov	ah,00Bh		;Get XMS "move data" request code.
	push	bx		;Save BX-reg. and execute XMS request.
	db	09Ah		;(SI-reg. points to IOLen after move).
@XEntry dd	0		;(XMS "entry" address, set by Init).
	dec	ax		;Return 0 if success, -1 if error.
	sar	ax,1		;If error, set carry flag on.
	jmp	short VDDone	;Go restore driver settings and exit.
;
; Subroutine to do a VDS "lock" or "unlock".
;
;VDUnlk	shr	byte [bx+VLF-@],1  ;Was I-O buffer "locked" by VDS?
;	jnc	VDExit		;No, just exit below.
VDUnlX	mov	ax,08104h	;Get VDS "unlock" parameters.
	xor	dx,dx
VDLock	mov	di,VDSLn	;Point to VDS parameter block.
	push	cs
	pop	es
	push	bx		;Save BX-reg. and execute VDS request.
	int	04Bh
VDDone	pop	bx		;Reload our BX-register.
	sti			;RESTORE all critical driver settings!
	cld			;(Never-NEVER "trust" external code!).
	push	cs
	pop	ds
VDExit	ret			;Exit.
;
; Subroutine to execute read and write commands.
;
BufDMA	mov	dword [bx+IOAdr-@],0 ;Buffered -- set XMS buffer addr.
@XBufAd	equ	$-4		;(XMS 32-bit buffer address, Init set).
DoDMA	mov	dx,[bx+DMAAd-@]	;Ensure any previous DMA is stopped!
	in	al,dx		;(On some older chipsets, if DMA is
	and	al,0FEh		;  running, reading an IDE register
	out	dx,al		;  causes the chipset to "HANG"!!).
	mov	al,[bx+DSCmd-@]	;Select our desired disk.
	and	al,0F0h
	mov	dl,[bx+IDEAd-@]
	mov	dh,001h
	out	dx,al
	mov	di,dx		;Save IDE drive-select address.
	mov	cx,(RDYTO*256)+(FLT*2)  ;Get timeout & "fault" mask.
	call	Await		;Await controller- and disk-ready.
	jc	VDExit		;If any errors, exit above!
	push	si		;Save BIOS timer pointer.
	mov	si,PRDAd	;Point to parameters we will output.
	test	byte [si+IOCmd-PRDAd],012h  ;Is this a write request?
	jnz	SetDMA		;Yes, reset DMA command register.
	mov	al,008h		;Get "DMA read" command bit.
SetDMA	mov	dx,[bx+DMAAd-@]	;Reset DMA commands and set DMA mode.
	out	dx,al
	inc	dx		;Point to DMA status register.
	inc	dx
	in	al,dx		;Reset DMA status register.
	or	al,006h		;(Done this way so we do NOT alter
	out	dx,al		;  the "DMA capable" status flags!).
	inc	dx		;Set PRD pointer to our DMA address.
	inc	dx
	outsd
	mov	ax,001F7h	;Set IDE parameter-output flags.
NxtPar	lea	dx,[di+CSECCT-CDSEL-1]  ;Point to IDE sector count -1.
IDEPar	inc	dx		;Output all ten LBA48 parameter bytes.
	outsb			;(1st 4 overlayed by 2nd 4 if LBA28!).
	shr	ax,1		;More parameters to go in this group?
	jc	IDEPar		;Yes, loop back and output next one.
	jnz	NxtPar		;If first 4 done, go output last 6.
	pop	si		;Reload BIOS timer pointer.
	mov	dh,003h		;Get IDE alternate-status address.
	dec	dx		;(Primary-status address | 300h - 1).
ChkDRQ	cmp	ch,[es:si]	;Too long without 1st data-request?
	je	DMAEnd		;Yes?  Return carry and DMA timeout!
	in	al,dx		;Read IDE alternate status.
	and	al,DRQ		;Has 1st data-request arrived?
	jz	ChkDRQ		;No, loop back and check again.
	mov	dx,[bx+DMAAd-@]	;Point to DMA command register.
	in	al,dx		;Set DMA Start/Stop bit (starts DMA).
	inc	ax
	out	dx,al
	test	byte [bx+IOCmd-@],0	;Overlap output request?
@Ovlp2	equ	$-1			;(012h if overlap enabled).
	jz	ChkDMA			;No, go await input end.
	mov	al,[bx+ReqBF-@]		;Post channel "overlap" flag,
	and	al,060h			;  so other IDE drivers WAIT!
	shr	al,2
	or	[bx+Flags-@],al
	mov	byte [bx+Timer-@],RDYTO	;Set 400-msec timeout count.
	xor	ax,ax			;Return success & zero carry.
	ret				;Exit back to "BufOut" logic.
;
; Subroutine to await end of I-O.
;
Await	mov	es,bx		;Point to low-memory BIOS timer.
	mov	si,BIOSTMR
	add	ch,[es:si]	;Set timeout limit in CH-reg.
	shr	cl,1		;Are we only checking drive "ready"?
	jnc	ChkRdy		;Yes, use logic below.
ChkDMA	inc	dx		;Point to DMA status register.
	inc	dx
	in	al,dx		;Read DMA controller status.
	dec	dx		;Point back to DMA command register.
	dec	dx
	and	al,DMI+DME	;DMA interrupt or DMA error?
	jnz	HltDMA		;Yes, halt DMA and check results.
	cmp	ch,[es:si]	;Has our DMA transfer timed out?
	jne	ChkDMA		;No, loop back and check again.
HltDMA	push	ax		;Save ending DMA status.
	in	al,dx		;Reset DMA Start/Stop bit.
	and	al,0FEh
	out	dx,al
	pop	ax		;Reload ending DMA status.
	cmp	al,DMI		;Did DMA end with only an interrupt?
	jne	ErrDMA		;No?  Go see what went wrong.
	inc	dx		;Reread DMA controller status.
	inc	dx
	in	al,dx
	test	al,DME		;Any "late" DMA error after DMA end?
	jnz	DMAEnd		;Yes?  Return carry and DMA error!
	inc	cx		;Check "fault" and hard-error at end.
ChkRdy	lea	dx,[di+CSTAT-CDSEL]  ;Read IDE primary status.
	in	al,dx
	test	al,BSY+RDY	;Controller or disk still busy?
	jg	ChkErr		;No, go check for "fault" or error.
	cmp	ch,[es:si]	;Too long without becoming ready?
	jne	ChkRdy		;No, loop back and check again.
	test	al,BSY		;BAAAD News!  Did controller go ready?
	mov	ax,(256*CTLRERR)+DISKERR ;(Get not-ready error codes).
	jmp	short WhichE	;Go see which error code to return.
ChkErr	and	al,cl		;Disk "fault" or hard-error?
	jz	ChkExit		;No, all is well -- go exit below.
	test	al,FLT		;BAAAD News!  Is the disk "faulted"?
	mov	ax,(256*FAULTED)+HARDERR ;(Get hardware error codes).
WhichE	jz	EndErr		;If "zero", use AL-reg. return code.
	mov	al,ah		;Use AH-reg. return code of this pair.
EndErr	add	al,cl		;Add 1 if error occurred at I-O end.
Kaput	stc			;Set carry flag to denote "error"!
ChkExit	ret			;Exit.
ErrDMA	test	al,DME		;BAAAD News!  Did DMA end with error?
DMAEnd	mov	ax,(256*DMAERR)+DMATIMO	 ;(Get DMA error codes).
	jmp	short WhichE	;Go see which error code to return.
BaseLmt	equ	$		;End of resident "basic" logic.
%if 0
BaseEnd	equ	$+BSTACK	;End of resident "basic" driver.
%else
BaseEnd	equ	$			;End of resident "basic" driver.
%endif
;
; Subroutine to display an error-message number.   At entry, the BL-
;   register has the digits count, and the AX-register has the data.
;
Dsply4	inc	bx		;Set 4-digit display count.
	inc	bx
Dsply2	inc	bx		;Set 2-digit display count.
Dsply1	inc	bx		;Set 1-digit display count.
DsplyN	rol	ax,4		;Get next hex digit in low-order.
	push	ax		;Save remaining digits.
	and	al,00Fh		;Mask off next hex digit.
	cmp	al,009h		;Is digit 0-9?
	jbe	DspNmA		;Yes, convert to ASCII.
	add	al,007h		;Add A-F offset.
DspNmA	add	al,030h		;Convert digit to ASCII.
	call	DsplyB		;Display digit using the BIOS.
	pop	ax		;Reload remaining digits.
	dec	bx		;More digits to go?
	jnz	DsplyN		;Yes, loop back.
	ret			;Exit.
;
; Subroutine to display an error-message "text" element.
;   At entry, the "text" pointer is in the SI-register.
;
DspNxt	call	DsplyB		;Display byte using the BIOS.
DsplyM 	cld			;Ensure FORWARD "string" commands!
	lodsb			;Get next output byte.
	or	al,al		;Are we at the terminating "null"?
	jnz	DspNxt		;No, loop back & display next byte.
	ret			;Exit.
;
; Subroutine to await overlap end and display any output-error message.
; NOTE:  Starting in V3.1 XDMA, "OCheck" is FIXED to address 00314h, so
;	 XCDROM or other IDE drivers can call "OCheck" and have it wait
;	 for overlap-end, before doing their own I-O on an IDE channel.
;
OCheck	pusha			;Save all CPU registers.
	push	ds
	push	es
	push	cs		;Set our DS-register.
	pop	ds
	xor	bx,bx		;Zero BX-reg. for relative commands.
	or	byte [bx+Flags-@],080h  ;Set driver I-O "busy" flag.
	sti			;Re-enable CPU interrupts.
	mov	cx,257+(FLT*2)	;Set 1 extra count & "fault" mask.
	add	ch,[bx+Timer-@]	;Get ending output timer value +1.
	mov	al,[bx+IDEAd-@]	;Set IDE status address in DI-reg.
	mov	ah,001h
	xchg	ax,di
	mov	dx,[bx+DMAAd-@]	;Get DMA command-register address.
	call	Await		;Await end of all DMA output.
	jnc	OCExit		;If no output errors, exit below.
 	nop			;(Unused alignment "filler").
	push	ax		;BAAAD News!  Save return code.
	mov	si,OEMsg	;Point to start of message "text".
	call	DsplyM		;Display beginning message text.
	pop	ax		;Display error return code.
	xchg	al,ah
	call	Dsply2
	call	DsplyM		;Display "Disk=" message text.
	mov	ah,[bx+IDEAd-@]	;Get low-order IDE channel number.
	shr	ah,2		;Align channel & disk-select bits.
	xor	ah,[bx+DSCmd-@]	;"XOR" with LBA command disk-select.
	xor	ah,0D0h		;Zero upper bits & re-invert select.
	call	Dsply1		;Display disk number (0 to 3).
	call	DsplyM		;Display "LBA=" message text.
	mov	ax,[bx+LBA2+1-@]  ;Display LBA bits 32-47.
	call	Dsply4
	mov	ax,[bx+LBA+2-@]	;Get LBA bits 16-23 and LBA command.
	and	ah,00Fh		;Anything in "LBA28" bits 24-27?
	jnz	OCMsg1		;Yes, set bits 16-31 in message.
	mov	ah,[bx+LBA2-@]	;Get "LBA48" bits 24-31.
OCMsg1	call	Dsply4		;Display LBA bits 16-31.
	mov	ax,[bx+LBA-@]	;Display LBA bits  0-15.
	call	Dsply4
	call	DsplyM		;Display ending message text.
OCExit	cli			;Disable CPU interrupts.
	and	byte [bx+Flags-@],067h  ;Reset I-O & overlap "busy".
	pop	es		;Reload all CPU registers and exit.
	pop	ds
	popa
	retf
;
; Subroutine to display a message byte using a BIOS "Int 010h" call.
;
DsplyB	push	bx		;Save all needed registers.
	push	si
	push	ax		;Save output byte.
	mov	ah,00Fh		;Get BIOS video "page" in BH-reg.
	int	010h
	pop	ax		;Reload output byte.
	mov	ah,00Eh		;Have BIOS display next message byte.
	int	010h
	sti			;RESTORE all critical driver settings!
	cld			;(Never-NEVER "trust" external code!).
	push	cs
	pop	ds
	pop	si		;Reload registers and exit.
	pop	bx
	ret
;
; Timer-interrupt routine, called every 55-msec by IRQ8 timer "ticks".
;
TmInt	pushf			;Entry -- save CPU flags and call
	db	09Ah		;  all other timer routines first!
@PrvTmr	dd	0		;(Prior timer vector, saved by Init).
	cli			;Disable CPU interrupts.
	push	ds		;Save and set our DS-register.
	push	cs
	pop	ds
	push	bx		;Save and zero our BX-register.
	xor	bx,bx
	dec	byte [bx+Timer-@]    ;Decrement 400-msec timer.
	jg	TmRet		     ;If it has not expired, exit!
	mov	[bx+Timer-@],bl	     ;If zero BEFORE, reset it!
	test	byte [bx+Flags-@],098h  ;Doing I-O, or NO overlap?
	jle	TmRet		     ;If either, exit immediately.
%if 0
	mov	[bx+CStack-@],sp     ;Save caller's stack pointer.
	mov	[bx+CStack+2-@],ss
	push	cs		     ;Switch to driver's stack.
	pop	ss
	mov	sp,ResEnd
%endif
	push	cs		     ;Await end of output overlap.
	call	OCheck
%if 0
	lss	sp,[bx+CStack-@]     ;Switch back to caller stack.
%endif
TmRet	pop	bx		     ;Reload BX- and DS-registers.
	pop	ds
	iret			;Exit.
;
; Output-Overlap Error Message "Text".
;
OEMsg	db	CR,LF,'XDMA Error ',0
	db	'h, Disk=',0
	db	' LBA=',0
	db	'h!',CR,LF
@Beep	db	007h,0
ResLmt	equ	$		;End of resident overlap logic.
%if 0
ResEnd	equ	$+OSTACK	;End of resident overlap driver.
%else
ResEnd	equ	$	;End of resident overlap driver.
%endif
;
; Subroutine to "validate" an UltraDMA hard-disk.
;
I_ValD	xor	bx,bx		;Point ES-reg. to low memory.
	mov	es,bx
	mov	al,0ECh		;Issue "Identify Device" command.
	mov	dx,CCMD
	xor	dl,[bx+IDEAd-@]
	out	dx,al
	mov	bx,BIOSTMR	;Point to low-memory BIOS timer.
	mov	cl,RDYTO	;Set I-O timeout limit in CL-reg.
	add	cl,[es:bx]
	mov	si,IEMsg	;Point to "Identify error" message.
I_IDDly	cmp	cl,[es:bx]	;Has our command timed out?
	je	I_SErr		;Yes, set CPU carry flag & exit.
	in	al,dx		;Get IDE controller status.
	test	al,BSY+RDY	;Controller or disk still busy?
	jle 	I_IDDly		;Yes, loop back and check again.
	test	al,ERR		;Did command cause any errors?
	jz	I_PIO		;No, read I.D. data using PIO mode.
I_SErr	stc			;Set carry flag (error!) and exit.
	ret
I_PIO	add	dx,byte (CDATA-CCMD)  ;Point to PIO data register.
	in	ax,dx		;Read I.D. bytes 0 and 1.
	shl	ax,1		;Save "ATA/ATAPI" flag in carry bit.
	mov	cx,27		;Skip I.D. bytes 2-53 and
I_Skp1	in	ax,dx		;  read I.D. bytes 54-55.
	loop	I_Skp1
	push	cs		;Point to disk-name message.
	pop	es
	mov	di,DName
	mov	cl,26		;Read & swap disk name into message.
I_RdNm	xchg	ah,al		;(I.D. bytes 54-93.  Bytes 94-105 are
	stosw			;  also read but are ignored.   Bytes
	in	ax,dx		;  106-107 are left in the AX-reg.).
	loop	I_RdNm
	xchg	ax,bx		;Save "UltraDMA valid" flag in BL-reg.
	mov	cl,35		;Skip I.D. bytes 108-175 &
I_Skp2	in	ax,dx		;  read I.D. bytes 176-177.
	loop	I_Skp2

;	mov	bh,ah		;Save "current UltraDMA mode" flags in BH-reg.
	mov	bh,al		;Save "supported UltraDMA mode" flags in BH-reg.

	mov	cl,167		;Skip remaining I.D. data.
I_Skp3	in	ax,dx
	loop	I_Skp3
	mov	si,UEMsg	;Point to "is not UltraDMA" message.
	rcr	bl,1		;Shift "ATA/ATAPI" flag into BL-reg.
	and	bl,082h		;ATAPI disk, or UltraDMA bits invalid?
	jle	I_SErr		;Yes?  Exit & display error message.
	mov	di,Modes	;Point to UltraDMA mode table.
	or	bh,bh		;Will disk do UltraDMA mode 0?
	jz	I_SErr		;No?  Exit & display message!

;--- set max udma mode for device

	push bx
	mov bl, bh
	mov bh,0
	bsr ax, bx
	mov ah, al
	mov al, 3
	inc dx
	out dx, al
	inc dx
	mov al, ah
	pop bx
	mov bl, al
	or al, 40h
	out dx, al
	add dx, 5
	mov al, 0EFh
	out dx, al
I_WaitR:
	in al, dx
	and al,0C0h
	js I_WaitR
	sub dx, 7
	mov bh,0
	add bx,bx
	add di,bx
	jmp I_GotM




I_NxtM	cmp	bh,bl		;Will disk do next UltraDMA mode?
	jb	I_GotM		;No, use current mode.
	inc	di		;Point to next mode table value.
	inc	di
	inc	cx		;Get next UltraDMA mode number.
	shl	bl,1		;More UltraDMA modes to check?
	jnz	I_NxtM		;Yes, loop back.
I_GotM	push	word [di]	;Save disk mode value.
	mov	bx,DNEnd	;Point to end of disk name.
I_NxtN	cmp	bx,DName	;Are we at the disk-name start?
	je	I_Name		;Yes, disk name is all spaces!
	dec	bx		;Decrement disk name pointer.
	cmp	byte [bx],' '	;Is this name byte a space?
	je	I_NxtN		;No, continue scan for non-space.
	inc	bx		;Skip non-space character.
	mov	word [bx],", "	;End disk name with comma/space.
	inc	bx		;Skip comma and space.
	inc	bx
I_Name	mov	dword [bx],"ATA-"  ;Set "ATA-" and null after name.
	mov	byte [bx+4],0
	mov	si,DNMsg	;Display "name" of this disk.
	call	DsplyM
	pop	ax		;Get disk "mode" value.
	mov	bx,0000Fh	;Set hex digit count.
	and	bx,ax
	call	DsplyN		;Display disk "mode" value.
	mov	si,CRMsg	;Display message terminators and exit.
	jmp	DsplyM
;
; "Strategy" routine.   At entry, ES:BX points to the DOS init request
;   packet, whose address is saved for processing below.
;
Strat	mov	[cs:LBA+1],bx	;Save DOS request-packet address.
	mov	[cs:LBA+3],es
	retf			;Exit & await DOS "Device Interrupt".
;
; "Device-Interrupt" routine.   This routine initializes the driver.
;
DevInt	pushf			;Entry -- save CPU flags.
	push	ds		;Save CPU segment registers.
	push	es
	push	ax		;Save needed 16-bit CPU registers.
	push	bx
	push	si
	push	cs		;Set our DS-register.
	pop	ds
	les	bx,[LBA+1]	;Point to DOS request packet.
	cmp	byte [es:bx+RPOp],0 ;Is this an "Init" packet?
	je	I_CPU		;Yes, test for minimum 80386 CPU.
	jmp	I_BadP		;Go post errors and exit quick!
I_CPU	push	sp		;See if CPU is an 80286 or newer.
	pop	ax		;(80286+ push SP, then decrement it).
	cmp	ax,sp		;Did SP-reg. get saved "decremented"?
	jne	I_Junk		;Yes, CPU is an 8086/80186, TOO OLD!
	pushf			;80386 test -- save CPU flags.
	push	07000h		;Try to set NT|IOPL status flags.
	popf
	pushf			;Get resulting CPU status flags.
	pop	ax
	popf			;Reload starting CPU flags.
	test	ah,070h		;Did any NT|IOPL bits get set?
	jnz	I_386		;Yes, CPU is at least an 80386.
I_Junk	mov	si,PRMsg	;Point to "No 80386+ CPU" message.
	jmp	I_Quit		;Go display message and exit quick!
I_386	pushad			;80386+ -- save all 32-bit registers.
	les	bx,[es:bx+RPCL]	;Get command-line data pointer.
I_NxtC	mov	ax,[es:bx]	;Get next 2 command-line bytes.
	inc	bx		;Bump pointer past first byte.
	cmp	al,0		;Is byte the command-line terminator?
	je	I_Term		;Yes, go see if overlap was enabled.
	cmp	al,LF		;Is byte an ASCII line-feed?
	je	I_Term		;Yes, go see if overlap was enabled.
	cmp	al,CR		;Is byte an ASCII carriage-return?
	je	I_Term		;Yes, go see if overlap was enabled.
	cmp	al,'-'		;Is byte a dash?
	je	I_NxtS		;Yes, see what next "switch" byte is.
	cmp	al,'/'		;Is byte a slash?
	jne	I_NxtC		;No, check next command-line byte.
I_NxtS	mov	al,ah		;Get byte after the slash or dash.
	and	al,0DFh		;Mask out lower-case bit (020h).
	cmp	al,'O'		;Is this byte an "O" or "o"?
	jne	I_ChkL		;No, go see if byte is "L" or "l".
	mov	al,012h		;Set output overlap flags.
	mov	[@Ovlp1],al
	mov	[@Ovlp2],al
	inc	bx		;Point to next command-line byte.
I_ChkL	cmp	al,'L'		;Is this byte an "L" or "l"?
	jne	I_ChkQ		;No, go see if byte is "Q" or "q".
	mov	byte [@DMALmt],009h ;Set 640K "DMA limit" above.
	inc	bx		;Point to next command-line byte.
I_ChkQ	sub	al,'Q'		;XDMA -- Is this byte a "Q" or "q"?
	jnz	I_NxtC		;No, see if byte is a terminator.
	mov	[@Beep],al	;Suppress "beep" in output-error msg.
	inc	bx		;Point to next command-line byte.
	jmp	short I_NxtC	;Continue scanning for a terminator.
I_Term	cmp	byte [@Ovlp1],0	;Was output overlap ever enabled?
	jne	I_TTL		;Yes, go display driver "title".
	mov	ax,BaseEnd	;Decrease resident-driver size.
	mov	[VDSLn],ax
%if 0
	mov	[@Stack],ax	;Decrease driver stack offset.
%endif
	mov	ax,BaseLmt	;Decrease stack address to "clear".
	mov	[ClrStak],ax
	mov	eax,[CRMsg]	;Omit "overlap" from title message.
	mov	[EOMsg],eax
	shr	dword [DvrName+4],8  ;We are now "XDMA$", no overlap.
I_TTL	mov	si,XDMsg	;Display driver "title" message.
	call	DsplyM
	xor	edi,edi		;Get PCI BIOS "I.D." code.
	mov	al,001h
	call	I_In1A
	mov	si,PEMsg	;Get "Invalid PCI BIOS" message ptr.
	cmp	edx,"PCI "	;Is PCI BIOS V2.0C or newer?
	jne	I_PCEr		;No?  Go display message and exit!
	mov	si,SecCt2	;Point to interface byte table.
I_GetD	mov	ecx,000010100h	;We want class 1 storage, subclass 1 IDE.
	lodsb			;Get next "valid" PCI interface byte.
	mov	cl,al
	push	si		;Search for our PCI class code.
	mov	al,003h		;(Returns bus/device/function in BX).
	xor	si,si
	call	I_In1A
	pop	si
	jnc	I_GotD		   ;Found our boy!  Go process it.
	cmp	si,byte (LBA+1-@)  ;More interface bytes to try?
	jb	I_GetD		   ;Yes, go try next one.
I_CtlE	mov	si,NEMsg	;BAAAD News!  Point to error message.
I_PCEr	jmp	I_EOut		;Go display error message and exit.
I_GotD	mov	dword [NEMsg],"BAD "  ;Change to "BAD controller" msg.
	push	bx		;Save PCI bus/device/function.
	mov	di,4		;Get low-order PCI command byte.
	call	I_PCID
	pop	bx		;Reload PCI bus/device/function.
	not	cl		;Mask Bus-Master and I-O Space bits.
	and	cl,005h		;Is this how our controller is set up?
	jz	I_xxxx		;No?  Display error message and exit!

;--- enable busmaster caps for device

	mov cl, ch
	or cl, 4
	push si
	push bx
	mov di, 4
	mov ax, 0B10Bh
	int 1Ah
	pop bx
	pop si

I_xxxx:
	mov	byte [PCMsg1],' '  ;Enable controller data display.
	push	bx		;Save PCI bus/device/function.
	xor	di,di		;Get Vendor and Device I.D.
	call	I_PCID
	pop	bx		;Reload PCI bus/device/function.
	push	ecx		;Save Vendor and Device I.D.
	mov	di,32		;Get PCI base address (register 4).
	call	I_PCID
	push	cx		;Save PCI base address.
	mov	si,PCMsg	;Display controller-data header.
	call	DsplyM
	pop	ax		;Reload PCI base address.
	and	al,0FCh		;Post our DMA controller address.
	mov	[DMAAd],ax
	mov	[@DMALo1],al	;Set low-order DMA address bytes.
	add	[@DMALo2],al
	xor	bx,bx		;Display DMA controller address.
	call	Dsply4
	call	DsplyM		;Display chip I.D. header.
	pop	ax		;Display Vendor I.D.
	call	Dsply4
	pop	ax		;Display Device I.D.
	call	Dsply4
	call	DsplyM		;Display controller-data trailer.
	mov	ax,03508h	;Get and save IRQ8 timer vector.
	call	I_In21
	push	es
	push	bx
	pop	dword [@PrvTmr]
	mov	ax,03513h	;Get and save current Int 13h vector.
	call	I_In21
	push	es
	push	bx
	pop	dword [@PrvI13]
	mov	ax,04300h	;Inquire about an XMS manager.
	call	I_In2F
	mov	si,NXMsg	;Point to "No XMS manager" message.
	cmp	al,080h		;Is an XMS manager installed?
	jne	I_XErr		;No, display message & disable XMS.
	mov	ax,04310h	;Get XMS manager "entry" address.
	call	I_In2F
	push	es		;Save XMS manager "entry" address.
	push	bx
	pop	dword [@XEntry]
	mov	ah,009h		;Ask XMS manager for 128K of memory.
	mov	dx,128
	call	I_XMS
	jnz	I_XMErr		;If error, display msg. & disable XMS.
	mov	[@XMHdl],dx	;Save XMS buffer handle number.
	mov	ah,00Ch		;"Lock" our XMS memory.
	call	I_XMS
	jnz	I_RidX		;If error, display msg. & disable XMS.
	shl	edx,16		;Get unaligned XMS buffer address.
	or	dx,bx		;Is buffer ALREADY on a 64K boundary?
	mov	eax,edx		;(Copy 32-bit address to EAX-reg.).
	jz	I_XBAd		;Yes, use XMS buffer address as-is.
	add	eax,65536	;Find 1st 64K boundary after start.
	xor	ax,ax
I_XBAd	mov	[@XBufAd],eax	;Set final XMS 32-bit buffer address.
	sub	ax,dx		;Initialize "offset" into XMS memory.
	mov	[XMOfs],ax
	mov	ah,005h		;Local-enable "A20 line" FOREVER!
	call	I_XMS		;("A20" CANNOT turn off during DMA!).
	jz	I_Stop		;If no error, ensure DMA is stopped.
I_RidX	mov	dx,[@XMHdl]	;Error!  Get rid of our XMS buffer.
	call	I_NoXMS
I_XMErr	mov	si,XEMsg	;Point to "XMS init error" message.
I_XErr	jmp	I_EOut		;Go display XMS error message & exit!
I_Stop	mov	dx,[DMAAd]	;Ensure any previous DMA is stopped.
	in	al,dx		;(See "DoDMA" routine notes above).
	and	al,0FEh
	out	dx,al
	add	dx,byte 8	;Stop secondary-channel DMA, also!
	in	al,dx
	and	al,0FEh
	out	dx,al
	xor	eax,eax		;Zero EAX-reg. for 20-bit addressing.
	mov	es,ax		;Point ES-reg. to low memory.
	mov	[SecCt2],al	;Reset IDE upper sector count.
	or	al,[es:HDISKS]	;Did BIOS find any hard-disks?
	jz	I_None		;No?  Display "No disk" and exit!
	mov	[BiosHD],al	;Save BIOS hard-disk count.
	mov	ax,cs		;Set our code segment in VDS block.
	mov	[VDSSg],ax
	shl	eax,4		;Set 20-bit driver virtual address.
	mov	[IOAdr],eax
	cli			;Avoid interrupts during VDS tests.
	test	byte [es:VDSFLAG],020h  ;Are "VDS services" active?
	jz	I_SetA		;No, set 20-bit virtual addresses.
	mov	ax,08103h	;"Lock" this driver into memory.
	mov	dx,0000Ch
	call	VDLock
	mov	si,XEMsg	;Set up "VDS init error" message.
	mov	word [si],"VD"
	jc	I_Err		;If "lock" error, display msg. & exit!
	inc	byte [VDSOf]	;Set initialization VDS "lock" flag.
	mov	eax,[IOAdr]	;Get 32-bit starting driver address.
I_SetA	sti			;Re-enable CPU interrupts.
	add	[PRDAd],eax	;Set relocated 32-bit PRD address.
	movsx	ax,[@DMALmt]	;Get DMA memory limit (if any).
	inc	ax		;Has /L limited DMA to low-memory?
	jz	I_Scan		;No, scan for UltraDMA disks to use.
	cmp	ax,[IOAdr+2]	;Are we loaded in upper-memory?
	ja	I_Scan		;No, scan for UltraDMA disks to use.
	mov	si,PEMsg1	;Set up "/L Invalid" error message.
	mov	word [si],"/L"
	jmp	short I_Err	;Go display error message and exit!
I_RScn	dec	byte [EDDFlag]	;Were we scanning v.s. EDD BIOS data?
	jz	I_Scan		;Yes, try a "hardware only" disk scan.
I_None	mov	si,NDMsg	;BAAAD News!  Point to "No disk" msg.
I_Err	push	si		;Init ERROR!  Save message pointer.
	shr	byte [VDSOf],1	;Was driver "locked" by VDS?
	jnc	I_XDis		;No, check on XMS memory.
	call	VDUnlX		;"Unlock" this driver from memory.
I_XDis	mov	dx,[@XMHdl]	;Get XMS memory "handle".
	or	dx,dx		;Did we reserve XMS memory?
	jz	I_LdMP		;No, go display error message.
	call	I_NoXMS		;Get rid of our XMS buffer.
	mov	ah,006h		;Do local-disable of "A20 line".
	call	I_XMS
I_LdMP	pop	si		;Reload error message pointer.
I_EOut	call	DsplyM		;Display desired error message.
	popad			;Reload all 32-bit CPU registers.
	mov	si,Suffix	;Display error-message suffix.
I_Quit	call	DsplyM
I_BadP	xor	ax,ax		;Get "null" length & error flags.
	mov	si,RPDON+RPERR
	jmp	I_Exit		;Go post "init" packet results & exit.
I_Scan	mov	ax,00080h	;Reset hard-disk unit number & index.
	mov	[HDUnit],ax
	mov	al,[BiosHD]	;Reset remaining hard-disk count.
	mov	[HDCount],al
	cmp	ah,[EDDFlag]	;Will disk scan use the EDD BIOS?
	jne	I_Next		;Yes, go start with BIOS unit 80h.
	mov	si,HOMsg	;Display "Hardware-only disk scan" msg.
	call	DsplyM
I_Next	movzx	bx,[HDIndex]	;Get disk unit-number index.
	cmp	bh,[EDDFlag]	;Scanning for disks using the EDD BIOS?
	je	I_ChMS		;No, check disk at "fixed" addresses.
	mov	ah,041h		;Get EDD "extensions" for this disk.
	mov	bx,055AAh
	call	I_In13
	jc	I_NoEx		;If none, ignore disk & check for more.
	cmp	bx,0AA55h	;Did BIOS "reverse" our entry code?
	jne	I_NoEx		;No, ignore this disk & check for more.
	test	cl,004h		;Does this disk have "EDD" extensions?
	jz	I_NoEx		;No, ignore this disk & check for more.
	mov	si,EDDBuff	;Point to "EDD" input buffer.
	mov	word [si],30	;From David Muller:  Set 30-byte size.
	mov	ah,048h		;Get this disk's "EDD" parameters.
	call	I_In13
	jc	I_ErED		       ;Error?  Display msg. & ignore!
	cmp	word [si],byte 30      ;From David Muller:  30+ bytes?
	jb	I_NoEx		       ;No, ignore disk & check more.
	cmp	dword [si+26],byte -1  ;Valid "DPTE" pointer?
	je	I_NoEx		       ;No, ignore disk & check more.
	les	si,[si+26]	;Get this disk's "DPTE" pointer.
	mov	bx,15		;Calculate "DPTE" checksum.
	xor	cx,cx
I_CkSm	add	cl,[es:bx+si]
	dec	bx
	jns	I_CkSm
	jcxz	I_EDOK		;If checksum O.K., use parameters.
I_ErED	mov	si,EBMsg	;Display "EDD error" and ignore unit!
	jmp	I_ErrD
I_NoEx	jmp	I_More		;No EDD:  ignore disk & check for more.
I_EDOK	mov	bx,00010h	;Initialize IDE unit number index.
	and	bl,[es:si+4]
	shr	bl,4
	mov	ax,[es:si]	;Get disk's IDE base address.
	cmp	ax,CDATA	;Is this a primary-channel disk?
	je	I_ChMS		;Yes, set disk channel and unit.
	inc	bx		;Adjust for secondary channel.
	inc	bx
	cmp	ax,(CDATA-080h)	;Is this a secondary-channel disk?
	jne	I_More		;No, ignore unit & check for more.
I_ChMS	mov	ax,bx		;Separate channel and master/slave.
	shr	al,1
	mov	ah,(LBABITS/32)	;Get drive-select "nibble".
	rcl	ah,5
	ror	al,1		;Set channel offset (2nd = 080h).
	mov	[IDEAd],al
	mov	dx,CDSEL	;Get IDE disk-select address.
	xor	dl,al
	mov	al,ah		;Select master or slave disk.
	out	dx,al
	push	bx		;Save disk's "Units" table index.
	mov	si,PriMsg	;Point to "Primary" channel name.
	test	bl,002h		;Is this a primary-channel disk?
	jz	I_PRNm		;Yes, display "Primary" channel.
	mov	si,SecMsg	;Point to "Secondary" channel name.
I_PRNm	call	DsplyM		;Display disk's IDE channel name.
	mov	si,MstMsg	;Point to "master" disk name.
	shr	bl,1		;Is this disk the master?
	jnc	I_MSNm		;Yes, display "master" name.
	mov	si,SlvMsg	;Point to "slave" disk name.
I_MSNm	call	DsplyM		;Display disk's master/slave name.
	mov	ah,008h		;Get BIOS CHS values for this disk.
	call	I_In13
	pop	bx		;Reload disk's "Units" table index.
	jc	I_CHSE		;If BIOS error, zero sectors/head.
	and	cx,byte 03Fh	;Get sectors/head value (low 6 bits).
	inc	dh		;Get heads/cylinder (BIOS value + 1).
	jnz	I_SetC		;If non-zero, save disk's CHS values.
I_CHSE	xor	cl,cl		;CHS error!  Zero disk's sectors/head.
I_SetC	mov	[bx+CHSHd-@],dh	;Save disk's CHS values in our tables.
	mov	[bx+CHSSec-@],cl
	mov	al,[HDUnit]	;Activate this disk in main driver.
	mov	[bx+Units-@],al
	push	bx		;Validate this UltraDMA disk.
	call	I_ValD
	pop	bx
	jc	I_DelD		  ;If any errors, DELETE this disk!
	cmp	[bx+CHSSec-@],bh  ;Were disk's CHS values legitimate?
	jne	I_More		  ;Yes, check for more disks to use.
	mov	si,CHMsg	  ;Display "BIOS must do CHS" msg.
	jmp	short I_ErrD
I_DelD	mov	byte [bx+Units-@],0FFh  ;DELETE disk in main driver!
I_ErrD	call	DsplyM		;Display error for this disk.
	mov	si,CRMsg	;Display error-message suffix.
	call	DsplyM
I_More	add	word [HDUnit],00101h  ;Bump BIOS unit & disk index.
	cmp	word [EDDFlag],08400h ;No EDD and all 4 units tested?
	je	I_AnyD		;Yes, see if we found any disks.
	dec	byte [HDCount]	;More BIOS disks to check?
	jnz	near I_Next	;Yes, loop back and do next one.
I_AnyD	mov	bx,4		;Set up to scan for last unit.
I_ChkU	dec	bx		;Any more active units to check?
	js	near I_RScn	;No, see if we should do a rescan.
	cmp	byte [bx+Units-@],0FFh  ;Is this unit active?
	je	I_ChkU		;No, loop back and check next unit.
	add	[@LastU],bx	;Post last-unit index in main driver.
	push	cs		;"Clear" driver local-stack memory.
	pop	es		;(Helps debug if unused stack = 0).
%if 0
	mov	cx,OSTACK+4
%endif
	mov	di,[ClrStak]
	xor	ax,ax
%if 0
	rep	stosb
%endif
	cmp	al,[@Ovlp1]	;Is output overlap disabled?
	je	I_HookV		;Yes, "hook" only Int 13h vector.
	mov	[Timer],al	;Reset output-overlap timer.
	mov	ax,02508h	;"Hook" this driver into IRQ8 timer.
	mov	dx,TmInt
	call	I_In21
I_HookV	mov	ax,02513h	;"Hook" this driver into Int 13h.
	mov	dx,Entry
	call	I_In21
	popad			;Reload all 32-bit CPU registers.
	xor	ax,ax		;Load & reset driver length.
	xchg	ax,[VDSLn]
	mov	si,RPDON	;Get initialization "success" code.
I_Exit	lds	bx,[LBA+1]	;Post results in "init" packet.
	mov	[bx+RPSize],ax
	mov	[bx+RPSize+2],cs
	mov	[bx+RPStat],si
	pop	si		;Reload 16-bit CPU registers we used.
	pop	bx
	pop	ax
	pop	es		;Reload CPU segment registers.
	pop	ds
	popf			;Reload CPU flags and exit.
	retf
;
; Subroutines to issue initialization "external" calls.    These and
;   the "clear-stack" logic above must appear AFTER the local-stack!
;
I_NoXMS	mov	ah,00Dh		;Error -- unlock & free XMS buffer.
	push	dx
	call	I_XMS
	mov	ah,00Ah
	pop	dx
I_XMS	call	far [@XEntry]	;Issue desired XMS request.
	dec	ax		;Zero AX-reg. if success, -1 if error.
	jmp	short I_IntX	;Restore driver settings, then exit.
I_In13	mov	dl,[HDUnit]	;Set BIOS unit in DL-reg.
	int	013h		;Issue BIOS data interrupt.
	jmp	short I_IntX	;Restore driver settings, then exit.
I_PCID	mov	al,00Ah		;Set "PCI doubleword" request code.
I_In1A	mov	ah,0B1h		;Issue PCI BIOS interrupt.
	int	01Ah
	db	0BDh		;Skip next command & exit (loads BP).
I_In21	int	021h		;Issue DOS interrupt.
	db	0BDh		;Skip next command & exit (loads BP).
I_In2F	int	02Fh		;Issue XMS interrupt.
I_IntX	sti			;RESTORE all critical driver settings!
	cld			;(Never-NEVER "trust" external code!).
	push	cs
	pop	ds
	ret			;Exit.
;
; Initialization Tables And Variables.
;
	align	2
Modes	dw	01602h		;Mode 0, ATA-16  UDMA mode table (digit
	dw	02502h		;Mode 1, ATA-25    count in low 4 bits).
	dw	03302h		;Mode 2, ATA-33.
	dw	04402h		;Mode 3, ATA-44  (Unusual but possible).
	dw	06602h		;Mode 4, ATA-66.
	dw	01003h		;Mode 5, ATA-100.
	dw	01333h		;Mode 6, ATA-133.
	dw	01663h		;Mode 7, ATA-166.
ClrStak	dw	ResLmt		;Starting stack address to "clear".
EDDFlag db	1		;"EDD BIOS in use" flag.
HDUnit	db	0		;Current BIOS unit number.
HDIndex db	0		;IDE "index" number.
	db	0		;(Unused alignment "filler").
EDDBuff equ	$		;Start of 30-byte EDD input buffer.

XDMsg	db	'XDMA',VER  ;XDMA.ASM provides version and date!
EOMsg	db	', Overlap Enabled.',CR,LF,0
PEMsg	db	'PCI BI'
PEMsg1	db	'OS Invalid',0
NXMsg	db	'No XMS manager',0
XEMsg	db	'XMS init error',0
DNMsg	db	'is '
DName	equ	$		;Disk names overlay the following.
DNEnd	equ	DName+40
NEMsg	db	' No '
PCMsg	db	'UltraDMA controller'	;These 5 message lines MUST
PCMsg1	db	0,'at I-O address ',0	;  appear in this sequence!
	db	'h, Chip I.D. ',0	;  This enables them to get
	db	'h'			;  displayed using only ONE
CRMsg	db	'.',CR,LF,0		;  initial message pointer!
NDMsg	db	'No disk to use',0
EBMsg	db	'EDD BIOS error!  Unit ignored',0
HOMsg	db	'Hardware-only disk scan:',CR,LF,0
PriMsg	db	'Primary-',0
SecMsg	db	'Secondary-',0
MstMsg	db	'master disk ',0
SlvMsg	db	'slave disk ',0
IEMsg	db	'Identify ERROR',0
UEMsg	db	'is not UltraDMA',0
PRMsg	db	'No 80386+ CPU'
Suffix	db	'; XDMA not loaded!',CR,LF,0
CHMsg	db	"** BIOS must do above disk's CHS I-O",0

