; Altirra BASIC - System includes
; Copyright (C) 2014 Avery Lee, All Rights Reserved.
;
; Copying and distribution of this file, with or without modification,
; are permitted in any medium without royalty provided the copyright
; notice and this notice are preserved.  This file is offered as-is,
; without any warranty.

;==========================================================================
; OS INCLUDES (800)
;

CIOCmdOpen			= $03
CIOCmdGetRecord		= $05
CIOCmdGetChars		= $07
CIOCmdPutRecord		= $09
CIOCmdPutChars		= $0B
CIOCmdClose			= $0C
CIOCmdGetStatus		= $0D
CIOCmdSpecial		= $0E	;$0E and up is escape
