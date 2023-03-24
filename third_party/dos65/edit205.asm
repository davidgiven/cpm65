;edit
;dos/65 context editor
;version 2.05-S
;released:	25 september 1982
;last revision:
;	27 november 1983
;		added code so returns to default drive
;	20 april 1986
;		added version reporting at start
;		added ? command for help
;		eliminated loc 0 and 1
;	31 march 2008
;		reformatted for TASm & ASM210
;	17 decemeber 2009
;		added parameter pzstrt
;		changed page zero def & init to use pzstrt
;	1 march 2011
;		changed opening message
;		added file name checking
;assembly time options
strmax	=	100		;maximum string length
srclng	=	1024		;source buffer length
dstlng	=	1024		;destination buffer length
;dos/65 references
pzstrt	=	$2		;start of page zero free RAM
boot	=	$100		;warm boot
pem	=	$103		;pem jump
dflfcb	=	$107		;default fcb
dflbuf	=	$128		;default buffer
tea	=	$200		;origin
condef	=	55		;condef block offset in sim
;fixed parameters
plus	=	$ff		;plus sign
minus	=	0		;minus sign
cr	=	$d		;carriage return
lf	=	$a		;linefeed
eof	=	$1a		;end of file
null	=	0
blank	=	$20		;ascii space
tab	=	9		;ctl-i
ctlr	=	$12		;repeat line
ctlx	=	$18		;cancel line
ctll	=	$c		;cr-lf substitute
delete	=	$7f		;backspace
;page zero variables
	*=	pzstrt
prmsgn				;parameter sign (0=-,ff=+)
	*=	*+1
number				;parameter value
	*=	*+2
column				;console column
	*=	*+1
curdrv				;current drive (default)
	*=	*+1
dstdrv				;destination drive
	*=	*+1
nxtchr				;next character from input
	*=	*+1
cnsind				;index into cnstxt
	*=	*+1
macflg				;macro flag and maximum index
	*=	*+1
macind				;macro buffer index
	*=	*+1
insflg				;insert mode if >127
	*=	*+1
nomore				;no more console input if >127
	*=	*+1
libind				;.lib file index
	*=	*+1
xlbind				;x$$$$$$$.lib file index
	*=	*+1
rdsccn				;read sector count
	*=	*+1
strind				;index into strbuf
	*=	*+1
nxttxt				;pointer to next char position
	*=	*+2
srcind				;source file pointer
	*=	*+2
dstind				;destination file pointer
	*=	*+2
uprtxt				;upper text pointer value
	*=	*+2
lwrlmt				;lower move limit
	*=	*+2
uprlmt				;maximum text pointer
	*=	*+2
maxtxt				;txtlmt-1
	*=	*+2
txtlmt				;limit of text buffer
	*=	*+2
point				;general use buffer
	*=	*+2
maccnt				;macro count
	*=	*+2
typpnt				;pointer for type
	*=	*+2
cmppnt				;pointer for compre
	*=	*+2
prsstr				;parse start
	*=	*+1
endstr				;end of search string
	*=	*+1
xlbpnt				;x$$$$$$$.lib pointer
	*=	*+2
normal				;normal video
	*=	*+1
invert				;invert video
	*=	*+1
forwar				;forward space
	*=	*+1
clreol				;clear to eol
	*=	*+1
backsp				;backspace
	*=	*+1
endcol				;last column
	*=	*+1
outflg				;output ok if < 128
	*=	*+1
dfldrv				;default drive
	*=	*+1
lastzp
;-------------------------------
;main program
;-------------------------------
	*=	tea
	jmp	edit		;go execute
	.byte	"COPYRIGHT (C) 2009 - "
	.byte	"RICHARD A. LEARY"
;clear page zero
edit	ldx	#pzstrt		;set starting loc
	lda	#0		;clear accum
clrzrp	sta	$0,x		;clear byte
	inx			;count up
	cpx	#lastzp		;see if end
	bne	clrzrp		;loop if more
;send opening message
	lda	#<opnmsg	;point to it
	ldy	#>opnmsg
	jsr	prtbuf		;send it
;get console definition parameters from sim
	lda	boot+2		;get high
	sta	getsys+2	;and save
	ldx	#condef+3	;get normal
	jsr	getsys		;char
	sta	normal		;and save
	ldx	#condef+4	;same
	jsr	getsys		;for
	sta	invert		;invert
	ldx	#condef+2	;and
	jsr	getsys		;for
	sta	forwar		;forward
	ldx	#condef+1	;then
	jsr	getsys		;for
	sta	clreol		;clear to eol
	ldx	#condef+0	;finally
	jsr	getsys		;get
	sta	backsp		;backspace
;find default drive
	jsr	rdecur		;get from pem
	sta	dfldrv		;and save for later
;calculate pointers for text buffer
	sec			;set
	lda	pem+1		;upper
	ldy	pem+2		;text
	sbc	#1		;limits
	sta	txtlmt		;to
	sta	maxtxt		;pem
	bcs	*+3		;location
	dey			;minus
	sty	txtlmt+1	;one
	sty	maxtxt+1	;then
	ldy	#0		;clear index
	tya			;and accum
	sta	(txtlmt),y	;and insert a zero
	lda	maxtxt		;subtract
	bne	*+4		;one from limit
	dec	maxtxt+1	;to make
	dec	maxtxt		;maximum
;test for good name format
;first test for possible afn in both fcbs
	ldx	#11		;check every position
	lda	#'?'		;test for ?
tstmre	cmp	dflfcb,x	;do compare
	beq	nmeerr		;is error if ?
	cmp	dflfcb+16,x	;check second name also
	beq	nmeerr		;it too must be ufn
	dex			;move forward
	bne	tstmre		;loop if more
	beq	tstblk		;otherwise test for blan in first position
;there is an error in the file names
nmeerr	lda	#<nmemsg	;point to error message
	ldy	#>nmemsg
	jmp	prtbuf		;send it and return
;keep going and check for blanks were needed
tstblk	lda	#blank		;test for blank
	cmp	dflfcb+1	;test first char
	beq	nmeerr		;error if blank
	cmp	dflfcb+17	;then if second
	bne	nmeerr		;blank is ok
	cmp	dflfcb+25	;also check extension
	bne	nmeerr		;error if not blank
;set up current and destination drives
	lda	dflfcb		;get automatic drive
	pha			;save it
	lda	#0		;clear
	sta	dflfcb		;automatic
	pla			;get drive
	sta	curdrv		;and save
	bne	noatsr		;if not zero use
	lda	dfldrv		;else get current
	sta	curdrv		;save it
	inc	curdrv		;bump it
noatsr	dec	curdrv		;drop it to 0 to 7
	lda	dflfcb+16	;get automatic
	sta	dstdrv		;and save
	bne	noatds		;if non zero use
	ldx	curdrv		;get current
	inx			;bump it
	stx	dstdrv		;and use it
noatds	dec	dstdrv		;drop in either case
;initialize files
	jsr	intxlb		;initialize x$$$$$$$.lib
;rentry for re-edit of file
rentry	lda	#source+srclng*256/256	;set
	ldy	#source+srclng/256	;source
	sta	srcind		;index to
	sty	srcind+1	;illegal
	lda	#<dest		;set
	ldy	#>dest		;destination
	sta	dstind		;pointer
	sty	dstind+1	;to first
	lda	#0		;clear
	sta	dflfcb+12	;extent
	sta	dflfcb+13
	sta	dflfcb+32	;and next record
	ldx	#32		;move
stdsfc	lda	dflfcb,x	;default fcb
	sta	dstfcb,x	;to destination
	dex			;fcb
	bpl	stdsfc		;in high mem
	lda	dstdrv		;get destination drive
	cmp	curdrv		;compare to current
	beq	dstsme		;branch if same
	jsr	setdrv		;else set dest
	lda	#<dflfcb	;point
	ldy	#>dflfcb	;to default
	ldx	#17		;search
	jsr	pem		;for it
	bmi	dstsme		;ok if not
	lda	#<flxmsg	;else send
	ldy	#>flxmsg	;file exists
	jsr	prcrbf		;message
	jmp	dlxlex		;and exit
dstsme	lda	curdrv		;get current
	jsr	setdrv		;and set
	lda	#<dflfcb	;then
	ldy	#>dflfcb	;open
	jsr	opnfle		;source
	bne	srisok		;ok if there
	lda	#<dflfcb	;else
	ldy	#>dflfcb	;create
	jsr	crtfle		;it
	bne	*+5		;jump if ok
	jmp	doserr		;else error
	lda	#<nwfmsg	;point to
	ldy	#>nwfmsg	;new file message
	jsr	prcrbf		;and send it
	jsr	crlf		;and another cr and lf
srisok	lda	#<bakstr	;change
	ldy	#>bakstr	;destination
	jsr	chgtyp		;to .bak
	lda	#<dstfcb	;delete
	ldy	#>dstfcb	;it if
	jsr	dltfle		;there
	lda	dstdrv		;if dest
	cmp	curdrv		;same as current
	beq	dntddd		;jump
	jsr	setdrv		;else
	lda	#<dstfcb	;delete
	ldy	#>dstfcb	;it on
	jsr	dltfle		;destination
dntddd	lda	#<dlrstr	;change
	ldy	#>dlrstr	;type
	jsr	chgtyp		;to .$$$
	lda	#<dstfcb	;delete
	ldy	#>dstfcb	;it if
	jsr	dltfle		;there
	lda	#<dstfcb	;then
	ldy	#>dstfcb	;create
	jsr	crtfle		;it
	bne	*+5		;jump if ok
	jmp	dlxlex		;else exit
	lda	#lf		;insert a lf
	sta	txtbuf		;at start of buffer
	lda	#txtbuf+1*256/256	;initialize
	ldy	#txtbuf+1/256	;next
	sta	nxttxt		;pointer to
	sty	nxttxt+1	;start + 1
	lda	maxtxt		;set upper
	ldy	maxtxt+1	;to max
	sta	uprtxt		;point
	sty	uprtxt+1	;in buffer
	lda	#0		;clear column
	sta	column		;index
	jmp	begin		;and begin
;error/break loop entries
;can not do command specified times
cntdmr	lda	#0
	beq	brklpe
;unrecognized command
unrccm	lda	#1
	bne	brklpe
;memory buffer full
mmbffl	lda	#2
brklpe	pha			;save error
	lda	#<brkmsg	;send
	ldy	#>brkmsg	;break
	jsr	prcrbf		;message
	pla			;then
	asl	a		;make index
	tax
	lda	errtbl,x	;get message address
	ldy	errtbl+1,x
	jsr	prtbuf		;print message
	lda	#<atmsg		;send
	ldy	#>atmsg		;at
	jsr	prtbuf		;message
	lda	nxtchr		;then last
	jsr	chrout		;char
	jsr	crlf		;and a cr&lf
begin	ldx	#$ff		;reset stack
	txs			;in case altered
	stx	nomore		;buffer empty
	inx			;clear
	stx	macflg		;macro flag
;main parsing loop entry
prsmre	lda	#0		;clear insert
	sta	insflg		;mode flag
	jsr	gtnxch		;get an input
	lda	cnsind		;get index
	sta	prsstr		;and save
;? for help
	lda	#'?'		;match ?
	jsr	tstfon
	bne	nothlp		;no so try next
	lda	#<help0		;do first part
	ldy	#>help0
	jsr	prtbuf
	lda	#<help1		;then second part
	ldy	#>help1
	jsr	prtbuf
	lda	#<help2		;then third part
	ldy	#>help2
	jsr	prtbuf
	lda	#<help3		;and final part
	ldy	#>help3
	jsr	prtbuf
	jmp	prsmre		;and do main loop
;e for end
nothlp	lda	#'E'		;see if e
	jsr	tstfon		;and only e
	bne	notend		;try next if not
	jsr	flusfl		;flush file
	jmp	dlxlex		;delete x$$$$$$$.lib and boot
;h for head
notend	lda	#'H'		;see if h
	jsr	tstfon		;and only h
	bne	nothea		;try next if not
	jsr	flusfl		;flush file
	lda	dstdrv		;switch
	ldx	curdrv		;current and
	stx	dstdrv		;destination
	sta	curdrv		;drives
	jmp	rentry		;and restart
;i for insert
nothea	lda	nxtchr		;get next char
	cmp	#'I'		;if i
	beq	*+5		;then insert
	jmp	notins		;else try next
	ldx	#0		;set x to zero
	lda	cnslng		;compare length
	cmp	cnsind		;to index
	bne	stinmd		;if not same clear insert mode
	lda	macflg		;get macro flag
	bne	stinmd		;clear insert if not zero
	dex			;else set x to ff
stinmd	stx	insflg		;save insert flag
insmre	jsr	gttsen		;get input and test for eof
	bne	*+5		;continue if not
	jmp	endins		;else end insert
	lda	nxtchr		;get char
	beq	insmre		;loop if a null
	cmp	#ctlx		;if not ctl-x
	bne	ntctlx		;try next
	jsr	clear		;clear line
	jsr	stnm0		;set number to zero
	lda	#minus		;and sign
	sta	prmsgn		;to minus
	jsr	lmtclc		;see how much to move
	jsr	movdlt		;do it
	jmp	insmre		;and loop
ntctlx	cmp	#ctlr		;if not ctl-r
	bne	ntrtdl		;try next
dorpt	jsr	clear		;clear line
	jsr	stnm0		;set number to zero
	lda	#minus		;and sign
	sta	prmsgn		;to negative
	jsr	type		;else type line
	jmp	insmre		;and get more
ntrtdl	cmp	#delete		;if not delete
	bne	notdlt		;try next
	jsr	dobs		;wipe out the delete
dlt	lda	#txtbuf+1*256/256	;if
	cmp	nxttxt		;not
	bne	dltok		;at
	lda	#txtbuf+1/256	;beginning
	cmp	nxttxt+1	;is
	bne	dltok		;ok
	jsr	clear		;clear line
	jmp	insmre		;else try again
dltok	jsr	getcol		;set current column
	lda	column		;and save
	sta	endcol
	jsr	drnxtx		;drop next text
	ldy	#0		;clear index
	lda	(nxttxt),y	;get char
	cmp	#lf		;if a lf
	beq	dlt		;then kill cr too
	cmp	#cr		;if a cr
	beq	dorpt		;type new line
	jsr	getcol		;calc new column
	sec
	lda	endcol		;calculate number of bs's
	sbc	column
	sta	endcol		;and save
bslpe	jsr	dobs		;do one
	dec	endcol
	bne	bslpe		;loop if more
	jmp	insmre		;then get next char
notdlt	cmp	#ctll		;if not a clt-l
	bne	notctl		;try next
	jsr	incrlf		;else insert cr and lf
	jmp	insmre		;and loop
notctl	jsr	instch		;insert char
	lda	nxtchr		;get it again
	cmp	#lf		;if not a lf
	bne	notalf		;try next
	jmp	insmre		;else loop
notalf	cmp	#cr		;if a cr
	beq	isacr		;continue
	cmp	#tab		;see if tab
	bne	*+5		;continue if not
	jmp	insmre		;else loop
	cmp	#' '		;if less than blank
	bcc	*+5		;continue
	jmp	insmre		;else loop
	jsr	chrout		;echo control
	jmp	insmre		;and loop
isacr	lda	#lf		;get a lf
	sta	nxtchr		;store it
	ldx	macflg		;get macro flag
	bne	*+5		;jump if macro
	jsr	chrout		;else echo
	jsr	instch		;insert it
	jmp	insmre		;and loop
endins	lda	nxtchr		;get char
	cmp	#eof		;if an eof
	beq	*+5		;then skip
	jsr	incrlf		;cr and lf insertion
	jmp	prsmre		;parse more
;o for original file
notins	lda	#'O'		;get an o
	jsr	tstvrf		;see if one and only
	bne	*+5		;try next if not
	jmp	rentry		;else restart
;r for read library file
	lda	nxtchr		;get char
	cmp	#'R'		;if an r
	beq	*+5		;is a read
	jmp	notrlb		;else try next
	lda	#1		;set index
	sta	libind		;to one
	jsr	curdfl		;default file
gtrlnm	jsr	gttsen		;get char
	beq	rnmend		;jump if end
	ldx	libind		;get index
	cpx	#9		;compare to max+1
	bcc	*+5		;ok if less
	jmp	cntdmr		;else error
	jsr	chtolf		;insert into fcb
	jmp	gtrlnm		;loop for more
rnmend	lda	#blank		;set for
	sta	nxtchr		;blank fill
	ldx	libind		;get index
	dex			;drop
	bne	notxlb		;.lib if not zero
	ldx	#8		;else
xlflbf	lda	xlbfcb,x	;is
	sta	libfcb,x	;x$$$$$$$.lib
	dex			;so fill
	bne	xlflbf		;fcb
	beq	lbflok		;and go use
notxlb	ldx	libind		;get index
	cpx	#9		;compare to 9
	bcs	lbflok		;done if that
	jsr	chtolf		;else insert
	jmp	notxlb		;and loop
lbflok	lda	#0		;clear
	sta	libfcb+12	;extent
	sta	libfcb+13
	sta	libfcb+32	;and record
	lda	#<libfcb	;then
	ldy	#>libfcb	;open
	jsr	opnfle		;file
	bne	*+7		;continue if ok
	lda	#3		;else send
	jmp	brklpe		;break
	lda	#128		;set index
	sta	libind		;to illegal
rdlbch	jsr	getlib		;get char
	sta	nxtchr		;store
	cmp	#eof		;if eof
	beq	*+8		;then done
	jsr	instch		;else insert
	jmp	rdlbch		;and loop
	jmp	prsmre		;main loop
;q for quit
notrlb	lda	#'Q'		;see if q
	jsr	tstvrf		;and verify
	bne	notqut		;branch if not
	lda	#<dstfcb	;else
	ldy	#>dstfcb	;delete
	jsr	dltfle		;destination
	jmp	dlxlex		;and exit
;number
notqut	jsr	dflprm		;set default parms
	lda	nxtchr		;get char
	cmp	#'-'		;if not a -
	bne	sgnpos		;then branch
	lda	#minus		;else get
	sta	prmsgn		;minus and set
	jsr	gtnxch		;and get command
	lda	nxtchr		;get char
sgnpos	cmp	#'#'		;if not #
	bne	ntmxnu		;skip forward
	jsr	stnmmx		;else set to max
	jsr	gtnxch		;get another
	jmp	gotnum		;and continue
ntmxnu	jsr	tstdec		;test for decimal
	bcc	gotnum		;if not jump
	jsr	bldnum		;else build parm
gotnum	jsr	tstnm0		;test for zero
	bne	*+6		;branch if not
	lda	#minus		;if zero set
	sta	prmsgn		;sign to minus
;b for beginning or end (+b or -b)
	lda	nxtchr		;get char
	cmp	#'B'		;if not b
	bne	notbgn		;try next
	lda	prmsgn		;get sign
	eor	#$ff		;complement it
	sta	prmsgn		;and save
	lda	#txtbuf+1*256/256	;set
	ldy	#txtbuf+1/256	;lower
	sta	lwrlmt		;limit
	sty	lwrlmt+1	;to start
	lda	maxtxt		;and
	ldy	maxtxt+1	;upper
	sta	uprlmt		;limit
	sty	uprlmt+1	;to max
	jsr	movonl		;move
	jmp	prsmre		;and loop
;c for move n char
notbgn	cmp	#'C'		;if not c
	bne	notcmv		;try next
	jsr	chrlmt		;calc limits
	jsr	movonl		;and move
	jmp	prsmre		;and loop
;d for delete n characters
notcmv	cmp	#'D'		;if not d
	bne	notcdl		;try next
	jsr	chrlmt		;calc limits
	jsr	movdlt		;move and deleue
	jmp	prsmre		;and loop
;k for kill n lines
notcdl	cmp	#'K'		;if not k
	bne	notkln		;try next
	jsr	lmtclc		;calc limits
	jsr	movdlt		;move with delete
	jmp	prsmre		;loop for more
;l for move n lones
notkln	cmp	#'L'		;if not l
	bne	notmln		;try next
	jsr	movnln		;do the move
	jmp	prsmre		;and loop
;t for type n lines
notmln	cmp	#'T'		;if not t
	bne	nottyp		;try next
	jsr	type		;go do it
	jmp	prsmre		;loop for more
;cr for move n lines and type
nottyp	cmp	#cr		;if not a cr
	bne	ntcr		;try next
	ldx	macflg		;but if a macro
	bne	endcr		;do nothing
	ldx	prsstr		;get start
	cpx	#1		;if not one
	bne	endcr		;do nothing
	jsr	movnln		;move
	jsr	dflprm		;then type
	jsr	type		;one line
endcr	jmp	prsmre		;loop
;for all following commands sign must be plus
ntcr	bit	prmsgn		;test sign
	bmi	trya		;ok if plus
	jsr	tstnm0		;if number zero
	beq	*+5		;is ok
	jmp	unrccm		;else unknown
	lda	nxtchr		;get char
;a for append lines
trya	cmp	#'A'		;if ot a
	bne	notapp		;try next
	lda	nxttxt		;set
	ldy	nxttxt+1	;lower
	sta	lwrlmt		;mimit
	sty	lwrlmt+1	;to next
	lda	maxtxt		;and upper
	ldy	maxtxt+1	;limit
	sta	uprlmt		;to
	sty	uprlmt+1	;maximum
	jsr	movonl		;then move
	jsr	tstnm0		;if number not zero
	bne	*+4		;then use it
	inc	number		;else set to one
appnlp	jsr	tstadj		;test for zero
	beq	append		;exit if done
	jsr	addlne		;else add a line
	jmp	appnlp		;and loop for next
append	lda	#minus		;set sign to
	sta	prmsgn		;minus and
	jsr	movonl		;move back
	jmp	prsmre		;loop for more
;f for find string
notapp	cmp	#'F'		;if not f
	bne	notfnd		;try next
	jsr	clstfl		;clear index and fill
fndstr	jsr	tstadj		;test number
	bne	*+5		;continue if not zero
	jmp	prsmre		;else done
	jsr	match		;try to match
	jmp	fndstr		;jump if match
;m for macro
notfnd	cmp	#'M'		;if not m
	bne	notmac		;try next
	ldx	macflg		;jump if flag
	bne	notmac		;not zero
	lda	#$ff		;else set index
	sta	macind		;to -1
	lda	number+1	;if high number
	bne	maclpe		;is not zero then use
	ldx	number		;if low number
	dex			;is not zero
	bne	maclpe		;then use
	jsr	stnm0		;else set to zeso
maclpe	inc	macind		;bump index
	jsr	getchr		;get char
	ldx	macind		;and new index
	sta	macbuf,x	;save char
	cmp	#cr		;if not a cr
	bne	maclpe		;loop for more
	lda	macind		;get index
	sta	macflg		;and set flag
	lda	#0		;then clear
	sta	macind		;index
	lda	number		;set
	ldy	number+1	;macro
	sta	maccnt		;count
	sty	maccnt+1	;to number
	jmp	prsmre		;and loop
;s for substitute strings
notmac	cmp	#'S'		;if not s
	bne	notsub		;try next
	jsr	clstfl		;get search string
	jsr	flstbf		;then replacement
sublpe	jsr	tstadj		;test number
	bne	*+5		;jump if more
	jmp	prsmre		;else done
	jsr	match		;try to match
	sec			;drop
	lda	nxttxt		;next
	sbc	endstr		;pointer
	sta	nxttxt		;by
	bcs	*+4		;search
	dec	nxttxt+1	;length
	ldx	endstr		;get start index
sbchlp	cpx	strind		;compare to end
	bcs	sublpe		;branch if end or more
	lda	strbuf,x	;else get char
	sta	nxtchr		;save it
	jsr	instch		;insert in text
	inx			;bump index
	bne	sbchlp		;and loop
;w for write
notsub	cmp	#'W'		;if not w
	bne	notwrt		;try next
	jsr	write		;else write
	jmp	prsmre		;and loop
;x for transfer to x$$$$$$$.lib
notwrt	cmp	#'X'		;if not x
	bne	notxfr		;try next
	jsr	stupxl		;set up files
	jsr	tstnm0		;test for zero
	bne	ntdlxl		;branch if not
	jsr	intxlb		;else
	lda	#<xlbfcb	;delete
	ldy	#>xlbfcb	;the
	jsr	dltfle		;file
	jmp	prsmre		;and loop
ntdlxl	jsr	intxlb		;else set up
	lda	#<xlbfcb	;then
	ldy	#>xlbfcb	;delete
	jsr	dltfle		;file
	lda	#<xlbfcb	;then
	ldy	#>xlbfcb	;initialize
	jsr	crtfle		;it again
	bne	*+5		;branch if ok
	jmp	doserr		;else error
	jsr	lmtclc		;calculate limits
	lda	lwrlmt		;then set
	ldy	lwrlmt+1	;pointer
	sta	xlbpnt		;to lower
	sty	xlbpnt+1	;limit
xfrlpe	lda	uprlmt		;if xlbpnt
	cmp	xlbpnt		;is greater
	lda	uprlmt+1	;than upper
	sbc	xlbpnt+1	;limit
	bcc	endxfr		;end transfer
	ldy	#0		;else clear index
	lda	(xlbpnt),y	;get byte
	jsr	putxlb		;and write
	inc	xlbpnt		;bump
	bne	xfrlpe		;pointer
	inc	xlbpnt+1	;and
	bne	xfrlpe		;loop
endxfr	bit	xlbind		;test index
	bmi	clsxfr		;done if > 127
	lda	#eof		;else insert
	jsr	putxlb		;an eof
	jmp	endxfr		;and loop
clsxfr	lda	#<xlbfcb	;write
	ldy	#>xlbfcb	;final
	jsr	wrtrcr		;record
	beq	*+5		;continue if ok
	jmp	doserr		;else error
	lda	#<xlbfcb	;close
	ldy	#>xlbfcb	;the
	jsr	clsfle		;file
	jmp	prsmre		;loop for more
;null command
notxfr	cmp	#null		;if not null
	bne	*+5		;branch
	jmp	prsmre		;else loop
	jmp	unrccm		;bad command
;-------------------------------
;subroutines
;-------------------------------
;calculate current column
getcol	lda	#$ff		;turn off output
	sta	outflg
	jsr	clear		;do a cr
	jsr	stnm0		;type line to get column
	lda	#minus
	sta	prmsgn
	jsr	type
	lsr	outflg		;clear flag
	rts
;do backspace sequence
dobs	lda	backsp		;do one
	jsr	cnsout
	lda	#' '		;then a space
	jsr	cnsout
	lda	backsp		;and one more
	jmp	cnsout
;clear current line
clear	lda	#cr		;get a return
	jsr	chrout		;send it
	lda	clreol		;then a clear
	jmp	cnsout		;to eol
;read from condef block
getsys	lda	$ff00,x		;dummy indexed
	rts
;flush text buffer and source file to destination file
flusfl	jsr	emtxbf		;empty text buffer
fluslp	jsr	getsrc		;get source char
	cmp	#eof		;if eof
	beq	flusex		;then close
	jsr	putdst		;else put in dest
	jmp	fluslp		;and loop
flusex	jmp	clsdst		;close out dest
;empty text buffer to destination file
emtxbf	jsr	stnmmx		;set number to max
	jmp	write		;and write
;carriage return and linefeed
crlf	lda	#cr
	jsr	chrout
	lda	#lf
;output char to console
chrout	cmp	#blank		;if blank or more
	bcs	sndinc		;send with col bump
	cmp	#cr		;if a return
	beq	clrcol		;clear column
	cmp	#lf		;if a linefeed
	beq	cnsout		;just send
	cmp	#tab		;if a tab
	beq	tabblk		;go expand
	cmp	#null		;if not a
	bne	*+3		;null continue
	rts			;else done
	pha			;save char
	lda	invert		;get invert
	cmp	#' '		;see if printing
	bcc	noinc		;branch if not
	jsr	sndinc		;else send with bump
	jmp	cout		;and continue
noinc	jsr	cnsout		;send it
cout	pla			;get char
	ora	#'A'-1		;convert to ascii
	jsr	sndinc		;and send
	lda	normal		;get normal
	jmp	cnsout		;and send it
tabblk	lda	#blank		;send a
	jsr	sndinc		;space
	lda	column		;get column
	and	#7		;if not mod 8
	bne	tabblk		;the loop
	rts			;else done
clrcol	lda	#255		;set column
	sta	column		;to -1
	lda	#cr		;get cr back
sndinc	inc	column		;bump column
cnsout	bit	outflg		;test flag
	bpl	*+3		;print if clear
	rts
	ldx	#2		;and send
	jmp	pem		;through pem
;read character from console
cnsin	ldx	#1
	jmp	pem
;print string
prtbuf	ldx	#9
	jmp	pem
;print cr and lf and then string
prcrbf	pha			;save
	tya			;string
	pha			;pointer
	jsr	crlf		;do cr and lf
	pla			;restore
	tay			;string
	pla			;pointer
	jmp	prtbuf		;and print
;open file (z=1 if error)
opnfle	ldx	#15
	jsr	pem		;execute
	cmp	#255		;see if bad
	rts
;close file (z=1 if error)
clsfle	ldx	#16
	jsr	pem		;execute
	cmp	#255		;see if bad
	rts
;delete file
dltfle	ldx	#19
	jmp	pem
;read record
rdercr	ldx	#20
	jmp	pem
;write record
wrtrcr	ldx	#21
	jmp	pem
;create file (z=1 if error)
crtfle	ldx	#22
	jsr	pem		;execute
	cmp	#255		;see if bad
	rts
;rename file
rnmfle	ldx	#23
	jmp	pem
;check console status (z=1 if none)
consts	ldx	#11
	jsr	pem		;check for key
	bne	*+3		;branch if ready
	rts			;else done
	jsr	cnsin		;clear input
	lda	#255		;and set z=0
	rts
;read current drive
rdecur	ldx	#25
	jmp	pem
;set drive
setdrv	ldx	#14
	jmp	pem
;set buffer address
setbuf	ldx	#26
	jmp	pem
;delete x$$$$$$$.lib and boot
dlxlex	lda	curdrv		;set drive
	jsr	setdrv		;to current
	lda	#<xlbfcb	;point to
	ldy	#>xlbfcb	;fcb
	jsr	dltfle		;delete it
	lda	dfldrv		;set drive to default
	jsr	setdrv
	jmp	boot		;and boot
;dos/65 error exit
doserr	jsr	crlf		;send a cr and lf
	lda	#<pemerr	;then send
	ldy	#>pemerr	;another cr and lf
	jsr	prcrbf		;and message
	lda	#<dstfcb	;close
	ldy	#>dstfcb	;output
	jsr	clsfle		;file
	jsr	crlf		;another cr and lf
	jmp	dlxlex		;and delete x$$$$$$$.lib and boot
;initialize x$$$$$$$.lib
intxlb	lda	#0		;clear
	sta	xlbfcb+12	;extent
	sta	xlbfcb+13
	sta	xlbfcb+32	;record
	sta	xlbind		;and index
	rts
;set up for x$$$$$$$.lib transfer
stupxl	lda	curdrv		;set drive
	jsr	setdrv		;to current
	lda	#<xlbbuf	;then point
	ldy	#>xlbbuf	;buffer
	jmp	setbuf		;to correct
;clear source index to start
clsind	lda	#<source	;get
	ldy	#>source	;start
	sta	srcind		;then set
	sty	srcind+1	;index
	rts
;set current drive and default buffer
curdfl	lda	curdrv		;set
	jsr	setdrv		;drive
	lda	#<dflbuf	;then
	ldy	#>dflbuf	;do
	jmp	setbuf		;buffer
;get char from .lib file
getlib	ldx	libind		;get index
	bpl	lbinok		;use if <128
	jsr	curdfl		;else setup
	lda	#<libfcb	;then
	ldy	#>libfcb	;read
	jsr	rdercr		;a record
	beq	*+5		;use if ok
	lda	#eof		;else get eof
	rts			;and return
	tax			;set index
	stx	libind		;and save
lbinok	inc	libind		;bump fo next
	lda	dflbuf,x	;get char
	rts
;test for number = zero (z=1 if zero)
tstnm0	lda	number		;see if
	ora	number+1	;both zero
	rts
;set number to zero
stnm0	lda	#0		;clear
	sta	number		;both
	sta	number+1
	rts
;set number to max
stnmmx	lda	#$ff		;set
	sta	number		;both
	sta	number+1	;to $ff
	rts
;test for zero and if not drop number (z=1 if zero)
tstadj	jsr	tstnm0		;test for zero
	bne	*+3		;jump if not
	rts
	jsr	drnumb		;drop number
	lda	#$ff		;set z
	rts			;to 0
;drop number by one
drnumb	lda	number		;get low
	bne	*+4		;if not zero
	dec	number+1	;skip high drop
	dec	number		;always drop low
	rts
;bump next pointer by one
bpnxtx	inc	nxttxt		;bump low
	bne	*+4		;done if not zero
	inc	nxttxt+1	;bump high
	rts
;drop next text pointer by one
drnxtx	lda	nxttxt		;get low
	bne	*+4		;if not zero skip
	dec	nxttxt+1	;drop of high
	dec	nxttxt		;always drop low
	rts
;bump upper text pointer by one
bpuptx	inc	uprtxt		;bump low
	bne	*+4		;done if not zero
	inc	uprtxt+1	;bump high
	rts
;drop upper text pointer by one
druptx	lda	uprtxt		;get low
	bne	*+4		;if not zero skip
	dec	uprtxt+1	;drop of high
	dec	uprtxt		;always drop low
	rts
;set default parm values
dflprm	lda	#plus		;set sign
	sta	prmsgn		;to plus
	ldy	#1		;and
	sty	number		;number
	dey			;to
	sty	number+1	;1
	rts
;test uprtxt against uprlmt (c=0 if uprtxt < uprlmt)
tsupup	lda	uprtxt		;compare upper
	cmp	uprlmt		;to upper limit
	lda	uprtxt+1	;and set
	sbc	uprlmt+1	;carry
	rts			;accordingly
;test nxttxt against lwrlmt (c=0 if nxttxt > lwrlmt)
tsnxlw	lda	lwrlmt		;compare next
	cmp	nxttxt		;to lower limit
	lda	lwrlmt+1	;and set
	sbc	nxttxt+1	;carry
	rts			;accordingly
;get next byte from source
getsrc	lda	srcind		;compare
	cmp	#source+srclng*256/256	;pointer
	lda	srcind+1	;to
	sbc	#source+srclng/256	;maximum
	bcc	*+5		;use if less
	jsr	rdesrc		;else read more
	ldy	#0		;clear index
	lda	(srcind),y	;get char
	cmp	#eof		;if not eof
	bne	*+3		;go bump pointer
	rts			;else done
	inc	srcind		;bump low
	bne	*+4		;done if not zero
	inc	srcind+1	;bump high
	rts
;insert char into .lib fcb
chtolf	lda	nxtchr		;get char
	jsr	cnvlwr		;convert to upper
	ldx	libind		;get index
	inc	libind		;bump for next
	sta	libfcb,x	;store char
	rts
;move to limits in direction of sign
movonl	ldy	#0		;clear index
	bit	prmsgn		;test sign
	bpl	movomi		;if minus go do it
movopl	jsr	tsupup		;compare upper to upper limit
	bcc	*+3		;continue if less
	rts			;else done
	jsr	bpuptx		;bump upper pointer
	lda	(uprtxt),y	;get byte
	sta	(nxttxt),y	;store char
	jsr	bpnxtx		;then bump next
	jmp	movopl		;and loop
movomi	jsr	tsnxlw		;compare lower limit to next
	bcc	*+3		;continue if less
	rts			;else done
	jsr	drnxtx		;drop next pointer
	lda	(nxttxt),y	;get char
	sta	(uprtxt),y	;store
	jsr	druptx		;drop upper pointer
	jmp	movomi		;and loop
;move to limits in direction of sign and delete
movdlt	ldy	#0		;clear index
	bit	prmsgn		;test sign
	bpl	movdmi		;if minus go do it
movdpl	jsr	tsupup		;test upper against upper limit
	bcc	*+3		;continue if less
	rts			;else done
	jsr	bpuptx		;bump upper pointer
	jmp	movdpl		;and loop
movdmi	jsr	tsnxlw		;compare lower to next
	bcc	*+3		;continue if less
	rts			;else done
	jsr	drnxtx		;drop next pointer
	jmp	movdmi		;and loop
;read source to fill buffer
rdesrc	jsr	clsind		;set index to start
	lda	curdrv		;set
	jsr	setdrv		;drive
	lda	#srclng/128	;and set sector
	sta	rdsccn		;count
rdeslp	lda	srcind		;get current
	ldy	srcind+1	;pointer
	jsr	setbuf		;and set as buffer
	lda	#<dflfcb	;point
	ldy	#>dflfcb	;to fcb
	jsr	rdercr		;read record
	beq	rdesok		;branch if ok
	bpl	*+5		;eof if positive
	jmp	doserr		;else error
	ldy	#0		;clear index
	lda	#eof		;get an eof
	sta	(srcind),y	;put into buffer
	jmp	clsind		;exit with index set
rdesok	clc			;add
	lda	srcind		;128 to
	adc	#128		;low part
	sta	srcind		;of pointer
	bcc	*+4		;if no carry skip
	inc	srcind+1	;bump of high
	dec	rdsccn		;drop count
	bne	rdeslp		;loop for more
	jmp	clsind		;then set index to start
;put char into x$$$$$$$.lib buffer
putxlb	ldx	xlbind		;get index
	bpl	gdxlbi		;if <128 use it
	pha			;else save char
	jsr	stupxl		;set up for write
	lda	#<xlbfcb	;point
	ldy	#>xlbfcb	;to fcb
	jsr	wrtrcr		;write a record
	beq	*+5		;continue if ok
	jmp	doserr		;else error
	tax			;clear index
	stx	xlbind		;and save
	pla			;get char
gdxlbi	inc	xlbind		;bump for next
	sta	xlbbuf,x	;insert char
	rts
;set destination index to start
cldind	lda	#<dest		;set
	ldy	#>dest		;index
	sta	dstind		;to start
	sty	dstind+1	;of buffer
	rts
;move primary name to second half of fcb
movnme	ldx	#15		;move all
	lda	dstfcb,x	;of first half
	sta	dstfcb+16,x	;to second
	dex			;half
	bpl	movnme+2	;then
	rts			;exit
;test char for first and only command and not macro
; z=1 if true
tstfon	cmp	nxtchr		;if char not
	bne	tstfex		;same is false
	lda	cnslng		;if console length
	cmp	#1		;not one
	bne	tstfex		;is false
	lda	macflg		;is true if not macro
tstfex	rts
;test for first and only and verify
tstvrf	pha			;save char
	jsr	tstfon		;test for first
	beq	*+4		;continue if it is
	pla			;clear stack
	rts			;done
	jsr	crlf		;send a cr and lf
	pla			;get char
	jsr	cnsout		;and send it
	lda	#<qusmsg	;send
	ldy	#>qusmsg	;-(y/n)?
	jsr	prtbuf		;message
	jsr	cnsin		;get answer
	jsr	cnvlwr		;convert to upper case
	pha			;save answer
	jsr	crlf		;echo a cr and lf
	pla			;get char
	cmp	#'Y'		;see if y
	rts
;test for decimal (if decimal then c=1 else c=0)
tstdec	lda	nxtchr		;get char
	cmp	#'0'		;if "0" or more
	bcs	*+3		;may be decimal
	rts			;else is not
	cmp	#'9'+1		;if > "9"
	bcs	*+6		;is not decimal
	and	#$f		;make a nibble
	sec			;and set flag
	rts
	clc			;is not decimal
	rts
;build decimal number from input
bldnum	jsr	stnm0		;clear number
	jsr	tstdec		;get next digit
	bcs	*+3		;if 0-9 use
	rts			;else done
	pha			;save digit
	lda	number		;get low number
	asl	a		;mult by two
	sta	point		;and save
	lda	number+1	;get high number
	rol	a		;mult it by two
	sta	point+1		;and save
	ldx	#3		;then
muln2	asl	number		;multiply
	rol	number+1	;number
	dex			;by
	bne	muln2		;eight
	clc			;add
	lda	number		;8x
	adc	point		;to
	sta	number		;2x
	lda	number+1	;to
	adc	point+1		;get
	sta	number+1	;10x
	clc			;then
	pla			;get digit
	adc	number		;add it
	sta	number		;and save
	bcc	*+4		;then propogate
	inc	number+1	;carry
	jsr	gtnxch		;get next char
	jmp	bldnum+3	;and loop
;fill string buffer until end
flstbf	jsr	gttsen		;get char and test
	bne	*+3		;continue if not end
	rts			;else done
	cmp	#ctll		;if not a ctl-l
	bne	flstnc		;then check for null
	lda	#cr		;else
	sta	nxtchr		;insert
	jsr	stbfin		;a cr
	lda	#lf		;then a
	sta	nxtchr		;lf
flstnc	cmp	#null		;if not a null
	bne	*+5		;use it
	jmp	unrccm		;else is error
	jsr	stbfin		;insert
	jmp	flstbf		;and loop
;insert a char into string buffer
stbfin	ldx	strind		;get index
	lda	nxtchr		;and char
	sta	strbuf,x	;store it
	inx			;bump index
	stx	strind		;and save
	cpx	#strmax		;if less than max
	bcc	*+5		;is ok
	jmp	mmbffl		;else is too long
	rts
;insert char into text buffer
instch	lda	nxttxt		;if next
	cmp	uprtxt		;less than
	lda	nxttxt+1	;upper
	sbc	uprtxt+1	;then
	bcc	*+5		;use it
	jmp	mmbffl		;else buffer full
	lda	nxtchr		;get char
	ldy	#0		;clear index
	sta	(nxttxt),y	;store char
	jmp	bpnxtx		;bump pointer
;get char and test for end of string
; if end then z=1 else z=0
gttsen	jsr	getchr		;get char
	sta	nxtchr		;save it
	cmp	#eof		;if not an eof
	bne	*+3		;then try cr
	rts			;else done
	cmp	#cr		;if a cr
	beq	*+3		;may be ok
	rts			;else is not
	ldx	insflg		;if not insert
	rts			;then is end
;add line to text buffer
addlne	lda	nxttxt		;if next
	cmp	uprtxt		;less
	lda	nxttxt+1	;than
	sbc	uprtxt+1	;upper
	bcc	*+5		;use
	jmp	mmbffl		;else send full message
	jsr	getsrc		;get byte
	cmp	#eof		;if not eof
	bne	*+5		;continue
	jmp	stnm0		;else exit with n=0
	ldy	#0		;clear index
	sta	(nxttxt),y	;store byte
	jsr	bpnxtx		;bump next pointer
	cmp	#lf		;if not a lf
	bne	addlne		;loop for more
	rts
;write destination buffer
wrtdst	lda	dstdrv		;set drive
	jsr	setdrv		;to destination
	sec			;then
	lda	dstind		;calculate
	sbc	#<dest		;length
	sta	point		;of
	lda	dstind+1	;buffer
	sbc	#>dest		;in
	sta	point+1		;bytes
	ldx	#7		;divide
wrtdv	lsr	point+1		;by 128
	ror	point		;to get
	dex			;number
	bne	wrtdv		;records
	cpx	point		;if number
	bne	*+3		;non-zero ok
	rts			;else empty file
	jsr	cldind		;set index to start
wrtdlp	lda	dstind		;then
	ldy	dstind+1	;set buffer
	jsr	setbuf		;address
	lda	#<dstfcb	;point to
	ldy	#>dstfcb	;fcb and
	jsr	wrtrcr		;write
	beq	*+5		;ok if zero
	jmp	doserr		;else error
	clc			;add
	lda	dstind		;128
	adc	#128		;to
	sta	dstind		;buffer
	bcc	*+4		;address
	inc	dstind+1	;for next write
	dec	point		;drop sector count
	bne	wrtdlp		;loop if more
	jmp	cldind		;else set index
;put byte in destination buffer
putdst	ldx	dstind		;if low
	cpx	#dest+dstlng*256/256	;not at max
	bne	nodswr		;then ok
	ldx	dstind+1	;or if high
	cpx	#dest+dstlng/256	;not at max
	bne	nodswr		;is also ok
	pha			;save char
	jsr	wrtdst		;write buffer
	pla			;get char
nodswr	ldy	#0		;then insert
	sta	(dstind),y	;char
	inc	dstind		;and
	bne	*+4		;bump
	inc	dstind+1	;index
	rts
;close destination file
clsdst	sec			;get low
	lda	dstind		;byte
	sbc	#<dest		;of offset
	and	#127		;see if mod 128
	beq	whlrec		;if so ok
	lda	#eof		;else insert
	jsr	putdst		;an eof
	jmp	clsdst		;and loop
whlrec	jsr	wrtdst		;write it all
	lda	#<dstfcb	;then
	ldy	#>dstfcb	;close
	jsr	clsfle		;.$$$
	bne	*+5		;continue if ok
	jmp	doserr		;else error
	lda	#<bakstr	;change
	ldy	#>bakstr	;.$$$
	jsr	chgtyp		;to .bak
	jsr	movnme		;then move
	lda	curdrv		;set current
	jsr	setdrv		;drive
	ldx	#15		;then
dfdsmv	lda	dflfcb,x	;move source
	sta	dstfcb,x	;name to dest
	dex			;fcb
	bpl	dfdsmv
	lda	#<dstfcb	;point
	ldy	#>dstfcb	;to it
	jsr	rnmfle		;and name it .bak
	jsr	movnme		;put it in second
	lda	#<dlrstr	;change
	ldy	#>dlrstr	;type
	jsr	chgtyp		;to .$$$
	lda	dstdrv		;go to
	jsr	setdrv		;destination
	lda	#<dstfcb	;and end
	ldy	#>dstfcb	;with
	jmp	rnmfle		;it renamed
;test for lower case (if lower case then c=1 else c=0)
tstlwr	cmp	#'a'		;if less than "a"
	bcc	ntlwr		;is not lower case
	cmp	#'z'+1		;if z+1 or more
	bcs	ntlwr		;is not lower
	sec			;is lower
	rts			;case
ntlwr	clc			;not lower
	rts			;case
;convert character to upper case
cnvlwr	jsr	tstlwr		;test for lower
	bcc	*+4		;exit if not
	and	#%01011111	;else convert
	rts
;get input character
getchr	lda	macflg		;get flag
	beq	notmci		;branch if not macro
	jsr	consts		;test for break
	beq	*+5		;continue if none
	jmp	cntdmr		;else do break
	ldx	macind		;get index
	cpx	macflg		;compare to max
	bcc	usmcin		;use if less
	lda	maccnt		;if count
	ora	maccnt+1	;is zero
	beq	clmcin		;clear index
	lda	maccnt		;else
	bne	*+4		;drop
	dec	maccnt+1	;count
	dec	maccnt		;by one
	lda	maccnt		;if result
	ora	maccnt+1	;is not zero
	bne	*+5		;go ahead
	jmp	cntdmr		;else done
clmcin	ldx	#0		;clear
	stx	macind		;index
usmcin	inc	macind		;bump for next
	lda	macbuf,x	;get char
	rts
;not macro
notmci	bit	insflg		;test insert mode
	bpl	ntinmd		;jump if not
	jmp	cnsin		;get char
;command mode
ntinmd	bit	nomore		;test for no input
	bpl	isinpt		;branch if input
	lda	#0		;else change
	sta	nomore		;status
	lda	#'*'		;send prompt
	jsr	chrout		;to console
	lda	#<cnsbuf	;get
	ldy	#>cnsbuf	;input
	ldx	#10		;line
	jsr	pem		;from dos
	lda	#lf		;echo a
	jsr	chrout		;linefeed
	lda	#0		;clear
	sta	column		;column and
	sta	cnsind		;index
isinpt	lda	#0		;clear accum
	ldx	cnsind		;get index
	cpx	cnslng		;compare to length
	php			;save result
	bne	*+4		;jump if not same
	lda	#$ff		;else set
	sta	nomore		;no more input flag
	plp			;get result
	bne	noteql		;jump if not equal
	lda	#cr		;then insert
	sta	cnstxt,x	;a cr
noteql	inc	cnsind		;bump next index
	lda	cnstxt,x	;get char
	rts
;move n lines
movnln	jsr	lmtclc		;calculate limits
	jmp	movonl		;and move
;change type of output to string pointed to by ya
chgtyp	sta	point		;set
	sty	point+1		;pointer
	ldy	#2		;set index
chgtlp	lda	(point),y	;get new value
	sta	dstfcb+9,y	;store in fcb
	dey			;count down
	bpl	chgtlp		;loop for more
	rts
;get next command character
gtnxch	jsr	getchr		;get char
	jsr	cnvlwr		;convert
	sta	nxtchr		;save
	rts
;insert a cr and lf
incrlf	lda	#cr		;insert
	sta	nxtchr		;the
	jsr	instch		;cr
	lda	#lf		;then
	sta	nxtchr		;the
	jmp	instch		;lf
;calculate limits from number characters
chrlmt	bit	prmsgn		;test sign
	bmi	chrpos		;branch if positive
;negative
	lda	uprtxt		;set upper
	ldy	uprtxt+1	;limit
	sta	uprlmt		;to current
	sty	uprlmt+1	;maximum
	sec			;then
	lda	nxttxt		;subtract
	sbc	number		;number
	sta	lwrlmt		;from
	lda	nxttxt+1	;next
	sbc	number+1	;pointer
	sta	lwrlmt+1	;and save
	bcc	chtosm		;jump if borrow
	lda	lwrlmt		;if result
	cmp	#txtbuf+1*256/256	;is
	lda	lwrlmt+1	;txtbuf+1
	sbc	#txtbuf+1/256	;or more
	bcs	usclpt		;use it
chtosm	lda	#txtbuf+1*256/256	;else
	ldy	#txtbuf+1/256	;use
	sta	lwrlmt		;txtbuf+1
	sty	lwrlmt+1	;as lower limit
usclpt	rts
;positive
chrpos	lda	nxttxt		;set lower
	ldy	nxttxt+1	;limit
	sta	lwrlmt		;to next
	sty	lwrlmt+1	;position
	clc			;calculate
	lda	uprtxt		;upper
	adc	number		;limit
	sta	uprlmt		;as
	lda	uprtxt+1	;upper
	adc	number+1	;plus
	sta	uprlmt+1	;number
	bcs	chtobg		;if carry too big
	lda	uprlmt		;compare
	cmp	txtlmt		;result
	lda	uprlmt+1	;to text
	sbc	txtlmt+1	;limit
	bcc	nttobg		;use if less
chtobg	lda	maxtxt		;else
	ldy	maxtxt+1	;set
	sta	uprlmt		;upper to
	sty	uprlmt+1	;maximum
nttobg	rts
;calculate move/delete limits as function of lines
lmtclc	bit	prmsgn		;test sign
	bpl	lmtcmi		;branch if minus
;positive
	ldx	uprtxt		;get upper low
	ldy	uprtxt+1	;and high
	stx	uprlmt		;set
	sty	uprlmt+1	;pointer
	inx			;bump lower
	bne	*+3		;if not zero skip
	iny			;bump of high
	stx	lwrlmt		;save
	sty	lwrlmt+1	;always
	ldy	#1		;set index
lmtplp	lda	uprlmt		;compare upper
	cmp	maxtxt		;limit to maximum
	bne	lmtpne		;branch if not equal
	lda	uprlmt+1	;do same for
	cmp	maxtxt+1	;high bytes
	bne	lmtpne		;branch if not same
	lda	number		;drop
	bne	*+4		;number
	dec	number+1	;by
	dec	number		;one
	rts			;and exit
lmtpne	lda	(uprlmt),y	;get char
	cmp	#lf		;if a lf
	beq	lmtple		;branch
lmtpad	inc	uprlmt		;else
	bne	lmtplp		;bump
	inc	uprlmt+1	;upper limit
	jmp	lmtplp		;and loop
lmtple	lda	number		;drop number
	bne	*+4		;for
	dec	number+1	;linefeed
	dec	number		;by one
	bne	lmtpad		;loop if not zero
	lda	number+1	;test high
	bne	lmtpad		;loop if it not zero
	inc	uprlmt		;bump
	bne	*+4		;limit
	inc	uprlmt+1	;and
	rts			;exit
;negative
lmtcmi	ldx	nxttxt		;get next
	ldy	nxttxt+1	;position
	stx	lwrlmt		;set lower
	sty	lwrlmt+1	;limit
	cpx	#0		;if low not zero
	bne	*+3		;do not
	dey			;drop high
	dex			;drop low always
	stx	uprlmt		;set upper
	sty	uprlmt+1	;limit
	inc	number		;bump
	bne	*+4		;number
	inc	number+1	;by one
	ldy	#0		;clear index
lmtmlp	lda	lwrlmt		;compare lower
	cmp	#<txtbuf	;to start
	bne	lmtmne		;branch if different
	lda	lwrlmt+1	;do same
	cmp	#>txtbuf	;for high
	bne	lmtmne		;branch if not same
	lda	number		;drop
	bne	*+4		;number
	dec	number+1	;by
	dec	number		;one
	inc	lwrlmt		;bump
	bne	*+4		;lower
	inc	lwrlmt+1	;back up
	rts			;and exit
lmtmne	lda	lwrlmt		;drop
	bne	*+4		;limit
	dec	lwrlmt+1	;by
	dec	lwrlmt		;one
	lda	(lwrlmt),y	;get char
	cmp	#lf		;if not a lf
	bne	lmtmlp		;then branch
	lda	number		;else
	bne	*+4		;drop
	dec	number+1	;number
	dec	number		;by one
	bne	lmtmlp		;loop if not zero
	lda	number+1	;if high not zero
	bne	lmtmlp		;then loop
	inc	lwrlmt		;else bump
	bne	*+4		;back to
	inc	lwrlmt+1	;char after
	rts			;the lf
;write n lines to destination
; if n=0 then n <-- 1
write	lda	#minus		;set sign
	sta	prmsgn		;to minus
	lda	#txtbuf+1*256/256	;then set
	ldy	#txtbuf+1/256	;pointer
	sta	lwrlmt		;for
	sty	lwrlmt+1	;move
	lda	uprtxt		;to beginning
	ldy	uprtxt+1	;of the
	sta	uprlmt		;text
	sty	uprlmt+1	;buffer
	jsr	movonl		;do the move
	jsr	tstnm0		;test for zero
	bne	*+4		;jump if not
	inc	number		;else make it one
wrlnlp	jsr	tstadj		;test for end
	beq	wrlnen		;jump if done
wrchlp	lda	uprtxt		;compare
	cmp	maxtxt		;upper
	lda	uprtxt+1	;pointer
	sbc	maxtxt+1	;to limit
	bcc	*+7		;branch if less
	jsr	stnm0		;else clear number
	beq	wrlnen		;and exit
	jsr	bpuptx		;bump upper pointer
	ldy	#0		;clear index
	lda	(uprtxt),y	;get char
	pha			;save it
	jsr	putdst		;insert in dest
	pla			;restore char
	cmp	#lf		;if not a lf
	bne	wrchlp		;loop for more char
	beq	wrlnlp		;else loop for line
wrlnen	lda	uprtxt		;if upper
	cmp	uprlmt		;pointer
	lda	uprtxt+1	;is not
	sbc	uprlmt+1	;at limit
	bcc	*+3		;then move
	rts			;else done
	lda	#plus		;set sign
	sta	prmsgn		;to plus
	jmp	movonl		;and move
;match strings
match	jsr	compre		;do comparison
	bne	*+3		;jump if none
	rts			;else ok
	jmp	cntdmr		;break for none
;type n lines
type	jsr	lmtclc		;calculate limits
	lda	#$ff		;set insert
	sta	insflg		;mode
	bit	prmsgn		;test sign
	bpl	typemi		;jump if negative
	lda	nxttxt		;else set
	ldy	nxttxt+1	;type pointer
	sta	typpnt		;to next
	sty	typpnt+1	;char pointer
	jmp	typeit		;and continue
typemi	lda	lwrlmt		;for negative
	ldy	lwrlmt+1	;set pointer
	sta	typpnt		;to lower
	sty	typpnt+1	;limit of text
typeit	lda	typpnt		;backup
	bne	*+4		;pointer
	dec	typpnt+1	;by
	dec	typpnt		;one
	ldy	#0		;clear index
	lda	(typpnt),y	;get char
	cmp	#lf		;if not a lf
	bne	ntlnbg		;then skip ahead
	lda	column		;get column
	beq	ntlnbg		;jump if zero
	jsr	crlf		;else send cr and lf
ntlnbg	lda	lwrlmt		;set type
	ldy	lwrlmt+1	;pointer
	sta	typpnt		;to lower
	sty	typpnt+1	;limit
typelp	lda	uprlmt		;if limit
	cmp	typpnt		;greater than
	lda	uprlmt+1	;or equal
	sbc	typpnt+1	;pointer then
	bcs	typemr		;continue
	rts
typemr	ldy	#0		;clear index
	lda	(typpnt),y	;get char
	pha			;save it
	jsr	chrout		;send it
	pla			;then get it back
	inc	typpnt		;bump
	bne	*+4		;poinper
	inc	typpnt+1	;by one
	cmp	#lf		;if not a lf
	bne	typelp		;then loop for more
	jsr	consts		;else see if break
	beq	typelp		;loop if not
	jmp	cntdmr		;else do halt
;compare string to buffer contents
; z=1 if compare else z=0
compre	lda	uprtxt		;set compare
	ldy	uprtxt+1	;pointer to
	sta	cmppnt		;start of
	sty	cmppnt+1	;upper
complp	lda	cmppnt		;if compare
	cmp	maxtxt		;pointer
	lda	cmppnt+1	;is less
	sbc	maxtxt+1	;than max
	bcc	*+5		;then continue
	jmp	nocomp		;else no compare
	inc	cmppnt		;bump
	bne	*+4		;pointer
	inc	cmppnt+1	;by one
	lda	cmppnt		;and
	ldy	cmppnt+1	;also
	sta	uprlmt		;set
	sty	uprlmt+1	;limit
	ldy	#0		;clear index
compnx	lda	strbuf,y	;get string
	cmp	(cmppnt),y	;compare to text
	bne	complp		;restart if no match
	inc	uprlmt		;bump upper
	bne	*+4		;limit
	inc	uprlmt+1	;and
	iny			;bump index
	cpy	endstr		;compare to end + 1
	bne	compnx		;loop if more
	lda	uprlmt		;drop
	bne	*+4		;upper
	dec	uprlmt+1	;limit
	dec	uprlmt		;by one
	jsr	movonl		;and move
	lda	#0		;return with
	rts			;z=1
nocomp	lda	#$ff		;return with
	rts			;z=0
;clear string buffer index and fill
clstfl	lda	#0		;clear
	sta	strind		;index
	jsr	flstbf		;fill buffer
	lda	strind		;then set
	sta	endstr		;end
	rts
;strings and messages
bakstr	.byte	"BAK"
dlrstr	.byte	"$$$"
nmemsg	.byte	"INVALID FILE NAME - ABORTING$"
opnmsg	.byte	"DOS/65 EDIT V2.05-S"
	.byte	cr,lf,"$"
help0	.byte	"COMMAND SUMMARY - s is sign"
	.byte	" - n is number "
	.byte	"[type # for max]"
	.byte	cr,lf,"  sn to move right [s=+]"
	.byte	" or left [s=-] n lines"
	.byte	" and type line"
	.byte	cr,lf,"  nA to Append n lines"
	.byte	cr,lf,"  sB to move to Beginning"
	.byte	" [s=+] or end [s=-]"
	.byte	cr,lf,"  snC to move n Characters"
	.byte	" right or left"
	.byte	"$"
help1	.byte	cr,lf,"  snD to Delete n "
	.byte	"characters right or left"
	.byte	cr,lf,"  E to Exit"
	.byte	cr,lf,"  nFstring to Find nth "
	.byte	"occurence of string"
	.byte	cr,lf,"  H to return to Head of file"
	.byte	cr,lf,"  I to Insert text"
	.byte	cr,lf,"  snK to Kill n lines right"
	.byte	" or left"
	.byte	cr,lf,"  snL to move n lines right"
	.byte	" or left"
	.byte	"$"
help2	.byte	cr,lf,"  nM to do Macro n times"
	.byte	cr,lf,"  O to restart with "
	.byte	"Original file"
	.byte	cr,lf,"  Q to Quit without "
	.byte	"altering file"
	.byte	cr,lf,"  Rname to Read library file"
	.byte	cr,lf,"  nSstring1[ctl-z]string2"
	.byte	" to Substitute"
	.byte	" string2 for string1"
	.byte	cr,lf,"  snT to type n lines right"
	.byte	" or left"
	.byte	"$"
help3	.byte	cr,lf,"  nW to Write n lines"
	.byte	cr,lf,"  nX to store n lines in"
	.byte	" temp buffer"
	.byte	cr,lf,"$"
nwfmsg	.byte	"NEW FILE$"
qusmsg	.byte	"-(Y/N)?$"
pemerr	.byte	"PEM FILE ERROR (FULL?)$"
atmsg	.byte	" AT $"
brkmsg	.byte	"BREAK - $"
flxmsg	.byte	"DESTINATION FILE EXISTS$"
mflmsg	.byte	"MEMORY BUFFER FULL$"
lfemsg	.byte	"LIBRARY FILE ERROR$"
cncmsg	.byte	"CAN NOT DO COMMAND "
	.byte	"SPECIFIED TIMES$"
urcmsg	.byte	"UNRECOGNIZED COMMAND$"
;error table
errtbl	.word	cncmsg
	.word	urcmsg
	.word	mflmsg
	.word	lfemsg
;buffers and fcbs
;console buffer
cnsbuf	.byte	128
cnslng	.byte	0
cnstxt
	*=	*+128
;.lib file fcb
libfcb
	*=	*+9
	.byte	"LIB"
	*=	*+21
;x$$$$$$$.lib file fcb
xlbfcb
	*=	*+1
	.byte	"X$$$$$$$LIB"
	*=	*+21
;destination file fcb
dstfcb
	*=	*+33
;string buffer
strbuf
	*=	*+strmax
;macro buffer
macbuf
	*=	*+128
;x$$$$$$$.lib buffer
xlbbuf
	*=	*+128
;source buffer
source
	*=	*+srclng
;destination buffer
dest
	*=	*+dstlng
;text buffer
txtbuf
	.end
