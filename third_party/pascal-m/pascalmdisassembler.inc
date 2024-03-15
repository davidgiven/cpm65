(* disassembler for M-pascal object files V2k1 *)
(* Written by   : H.J.C. Otten
   Last update  : 11 aug 2020
   Code cleaned up, no more warnings
   M-code not essentially changed from V1.0
   GFA and SFA and MVB instruction already in V1.0
   As Standard procedures RSET 'REWR ' 'STATE' CLOSE' ;
   Missing MEMRD MEMWR
   Note some instructions commented out *)
{
  MIT License

  Copyright(c)1978, 2021 Hans Otten

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files(the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED to THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, toRT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
}

CONST
  alphalength = 80 ;
  maxstore = 65535 ;
  maxproc  = 99   ;
  maxpage  =  56   ;
  {
  maxlabel = 3000  ;
  }
  maxstandardprocedures = 18 ;
  strglgth = 8 ;(* length of ident, procedure/program name *)

type
{ phasetype =(phase1, phase2)}
  filestatus =(correct, endoffile, overflowbuffer, checkerror);
  alpha = packed array[1 .. 80] of char ;
  procinfo = record
               procaddress : integer ;
               procname    : packed array[1..strglgth] of char ;
              end  ;
  instructname = packed array[1 .. 5] of char ;
  instruct = record
               name : instructname ;
               arg  : integer
             end  ;
var
 (* objectfile Variables *)
  linelength, recnr    : integer ;
  checksum, rchecksum  : integer ;
  fstatus               : filestatus ;
  line  : alpha ;
 (* procedure information buffer *)
  procbuffer : array[0 .. maxproc] of procinfo ;
  procf  : integer ;(* total nr of procedures loaded   *)
{
  labels  : array[1..maxlabel] of integer ;

 (* addresses of label, value > 0 means label used *)
  labelcount : integer ;(* last label added to label array *)
}
 (* p-machine memory *)
  store : array[0 .. maxstore] of byte ;
 (* registers of p-machine *)
  pc     : integer ;(*  nr of code bytes laoded in store *)
 (* disassembler counter *)
  dpc : integer ;
 (* files
  objectfile, asmfile, listfile, errorfile : text ;   *)

 (* instructions with level in instruction byte, 0 - $8F  *)
  grinstruction  : array[0 .. 8] of instruct ;
 (* instructions above $8F , whole byte unique *)
  instruction    : array[$90 .. $FF] of instruct ;
 (* Standard procedures *)
  standardproc   : array[0..maxstandardprocedures] of string;
 (* Standard procedures comment *)
  standardcproc  : array[0..maxstandardprocedures] of string;
 (* listing file counters *)
  listlines,
  listpages      : integer ;
  objectlinepre,
  objectline     : string ;
  assemblerline  : string ;

  procedure EndLinelist  ;
   (* Ends line on listfile takes care of pages, headings etc *)
    begin
      listlines := listlines + 1 ;
     (* new page needed ? *)
      if listlines > maxpage
        then
          begin
           (* write formfeed and header *)
            writeln(listfile);
            write(listfile, 'Pascal-M V1.0 Disassembler   ');
            write(listfile, objectfilename);
            writeln(listfile, '               Page ', listpages:4);
            writeln(listfile);
            writeln(listfile);
            listpages := listpages + 1 ;
            listlines := 3
          end  ;

    end  ;(* EndLineList *)

  procedure FillInstructions  ;
 (* fills instruction table with names
       of number of arguments              *)
  var
    i : integer ;
    procedure FillGrinstruction(index: integer ; name: instructname ; arg: integer);
      begin
        grinstruction[index].name := name ;
        grinstruction[index].arg := arg ;
      end  ;(* Fillgrinstructions *)

    procedure fillinstruct(index: integer ; name: instructname ; arg: integer);
      begin
        instruction[index].name := name ;
        instruction[index].arg := arg ;
      end  ;(* FillInstruct *)

    begin(* FillInstructions *)
       (* instructions 0 -$8F = 143, contain level in instruction *)
	Fillgrinstruction(0,'LDCIS',0)       ;
	Fillgrinstruction(1,'LDAS ',1)       ;
	Fillgrinstruction(2,'LDA  ',2)       ;
	Fillgrinstruction(3,'MST0 ',0)       ;
	Fillgrinstruction(4,'MSTN ',1)       ;
	Fillgrinstruction(5,'LOD1 ',1)       ;
	Fillgrinstruction(6,'LOD2 ',1)       ;
	Fillgrinstruction(7,'STR1 ',1)       ;
	Fillgrinstruction(8,'STR2 ',1)       ;
  fillinstruct($90,'LEQ2 ',0)      ;
	fillinstruct($91,'MFOR ',2)      ;
	fillinstruct($92,'LEQM ',2)      ;
	fillinstruct($93,'LES2 ',0)      ;
	fillinstruct($94,'LEQ8 ',0)      ;
	fillinstruct($95,'LESM ',2)      ;
	fillinstruct($96,'EQU2 ',0)      ;
	fillinstruct($97,'GEQ8 ',0)      ;
	fillinstruct($98,'EQUM ',2)      ;
	fillinstruct($99,'EQU8 ',0)      ;
	fillinstruct($9A,'IND1 ',0)      ;
	fillinstruct($9B,'IND2 ',0)      ;
	fillinstruct($9C,'IND8 ',0)      ;
	fillinstruct($9D,'STO1 ',0)      ;
	fillinstruct($9E,'STO2 ',0)      ;
	fillinstruct($9F,'STO8 ',0)      ;
	fillinstruct($A0,'LDC  ',2)      ;
	fillinstruct($A1,'RETP ',0)      ;
	fillinstruct($A2,'ADI  ',0)      ;
	fillinstruct($A3,'AND  ',0)      ;
	fillinstruct($A4,'Dif  ',0)      ;
	fillinstruct($A5,'DVI  ',0)      ;
	fillinstruct($A6,'INN  ',0)      ;
	fillinstruct($A7,'INT  ',0)      ;
	fillinstruct($A8,'IOR  ',0)      ;
	fillinstruct($A9,'MOD  ',0)      ;
	fillinstruct($AA,'MPI  ',0)      ;
	fillinstruct($AB,'NGI  ',0)      ;
	fillinstruct($AC,'NOT  ',0)      ;
	fillinstruct($AD,'SBI  ',0)      ;
	fillinstruct($AE,'SGS  ',0)      ;
	fillinstruct($AF,'UNI  ',0)      ;
	fillinstruct($B0,'LNC  ',2)      ;
	fillinstruct($B1,'FJP  ',2)      ;
	fillinstruct($B2,'UJP  ',2)      ;
	fillinstruct($B3,'DEC  ',2)      ;
	fillinstruct($B4,'INC  ',2)      ;
	fillinstruct($B5,'ENT  ',2)      ;
	fillinstruct($B6,'CAS  ',5)      ;(* 5 if flag for special handling *)
	fillinstruct($B7,'MOV  ',2)      ;
	fillinstruct($B8,'DEC1 ',0)      ;
	fillinstruct($B9,'INC1 ',0)      ;
	fillinstruct($BA,'LDCS ',8)      ;
	fillinstruct($BB,'CAP  ',2)      ;
	fillinstruct($BC,'LCA  ',5)      ;(* 5 is flag for writing arguments *)
	fillinstruct($BD,'CSP  ',1)      ;
	fillinstruct($BE,'CUP1 ',1)      ;
	fillinstruct($BF,'CUP2 ',1)      ;
	fillinstruct($C0,'FIX21',0)      ;
	fillinstruct($C1,'LNS  ',0)      ;
	fillinstruct($C2,'SFA  ',0)      ;
	fillinstruct($C3,'GFA  ',0)      ;
	fillinstruct($C4,'MVB  ',4)      ;
  fillinstruct($C5,'SHL  ',0)      ;
  fillinstruct($C6,'SHR  ',0)      ;
	for i := $C7 to $FF do
	  begin
	    instruction[i].name := 'NOP  '  ;
            instruction[i].arg  := 0        ;
	  end  ;
        standardproc[0] := 'WRI  ' ;
        standardproc[1] := 'WRC  ' ;
        standardproc[2] := 'WRS  ' ;
        standardproc[3] := 'RDI  ' ;
        standardproc[4] := 'RDL  ' ;
        standardproc[5] := 'RDC  ' ;
        standardproc[6] := 'WLN  ' ;
        standardproc[7] := 'NEW  ' ;
        standardproc[8] := 'EOF  ' ;
        standardproc[9] := 'RST  ' ;
        standardproc[10] := 'ELN  ' ;
        standardproc[11] := 'STP  ' ;
        standardproc[12] := 'ODD  ' ;
        standardproc[13] := 'RSET ' ;
        standardproc[14] := 'REWR ' ;
        standardproc[15] := 'STATE' ;
        standardproc[16] := 'CLOSE' ;
        standardproc[17] := 'ASSIGN' ;
        standardproc[18] := 'GETCLI' ;
        standardcproc[0] := 'write integer'  ;
        standardcproc[1] := 'write character' ;
        standardcproc[2] := 'write string'  ;
        standardcproc[3] := 'read integer'  ;
        standardcproc[4] := 'read to end of line'  ;
        standardcproc[5] := 'read character' ;
        standardcproc[6] := 'write end of line'  ;
        standardcproc[7] := 'new' ;
        standardcproc[8] := 'end of file test'  ;
        standardcproc[9] := 'restore heap' ;
        standardcproc[10] := 'end of line test';
        standardcproc[11] := 'stop execution' ;
        standardcproc[12] := 'test integer for odd' ;
        standardcproc[13] := 'reset file'   ;
        standardcproc[14] := 'rewrite file' ;
        standardcproc[15] := 'status file' ;
        standardcproc[16] := 'close file'  ;
        standardcproc[17] := 'assign file' ;
        standardcproc[18] := 'get command line' ;
    end  ;(* FillInstructions *)

  procedure Loader(loadaddress : integer) ;
 (* loads p-code output from compiler *)
 (* records output as followed by checksum
     P1 = code-bytes
     P2 = address-reference four bytes
     P4 = procedure level + procedure name
     P9 = end  of code(no checksum)      *)
var
  count, i : integer ;
  procedure GetLine(var linelength : integer ;
                      var fstatus : filestatus);
    begin
     if eof(objectfile)
       then
         fstatus := endoffile
       else
         begin
           recnr := recnr + 1 ;
           linelength := 1 ;
           read(objectfile, line[linelength]);
           while not eoln(objectfile)and(linelength < alphalength)do
             begin
               linelength := linelength + 1 ;
               read(objectfile, line[linelength]) ;
             end  ;
           if not eoln(objectfile)
             then
               fstatus := overflowbuffer ;
           readln(objectfile);
         end  ;
    end  ;(* GetLine *)

  FUNCTION PackHex(startposition : integer): integer ;
  var
    hexnumber, chvalue, i, j  : integer ;
  begin
   hexnumber := 0 ;
   for i := 0 to 1 do
     begin
       chvalue := ord(line[startposition + i]);
       if(chvalue >= ord('0'))and
         (chvalue <= ord('9'))
         then
           j := chvalue - ord('0')
         else
           j := chvalue - ord('A')+  10 ;
       hexnumber := hexnumber * 16 + j
      end  ;
    PackHex := hexnumber ;
  end  ;(* PackHex *)

  procedure Loadp1 ;
 (* loads P1 record into procedure buffer *)
  var
    i,nrloadbytes : integer ;
  begin
    nrloadbytes := PackHex(3);
    checksum := nrloadbytes ;
    for i := 1 to nrloadbytes - 1 do
      begin
        store[pc] := PackHex( 2*i - 1 + 4 );
        checksum := checksum + store[pc] ;
        pc := pc + 1 ;
      end  ;
    rchecksum := PackHex(nrloadbytes * 2 - 1 + 4);
    if((16383 - checksum)mod 256)<> rchecksum
      then
        begin
          writeln('Checksum error in P1 record ');
          fstatus := checkerror
        end  ;

  end  ;(* Loadp1 *)

  procedure Loadp2 ;
 (* loads P2 record with address into store buffer *)
  var
     loc, val, i, locl, loch, vall, valh  : integer ;
   begin
     loch := PackHex(3);
     locl := PackHex(5);
     loc := (256* loch +  locl)+ loadaddress   ;
     checksum := loch + locl ;
     valh := PackHex(7);
     vall := Packhex(9);
     val :=(256 * valh + vall) ;
     checksum := checksum +  valh + vall ;
     store[loc  ]  :=  val div 256 ;
     store[loc + 1] := val mod 256  ;
     rchecksum := PackHex(11);
     i :=(16383 - checksum)mod 256 ;
     if i <> rchecksum
       then
         begin
           writeln('Checksum error in P2 record ');
           fstatus := checkerror
         end  ;
  end  ;(* Loadp2 *)

  procedure Loadp4 ;
 (* loads P4 record into procedure buffer   *)
 (* line[3] .. line[4] is procedure number *)
 (* line[5] .. line[5 + strglgth] is procedure name *)
  var
    nrproc, i : integer ;
  begin
    nrproc := PackHex(3);
    if nrproc > procf
      then
        procf := nrproc ;
    checksum := nrproc ;
    for i := 1 to strglgth do
     begin
      procbuffer[nrproc].procname[i] := line[4 + i] ;
      checksum := checksum + ord(line[i+4]);
     end  ;
    procbuffer[nrproc].procaddress := pc  ;
    rchecksum := PackHex(13);
    if((16383 - checksum)mod 256)<> rchecksum
      then
        begin
          writeln('Checksum error in P4 record ');
          fstatus := checkerror
        end  ;
  end  ;(* Loadp4 *)

  begin(* loader *)
    for count := 0 to maxproc do
      begin
        for i := 1 to strglgth do
        procbuffer[count].procname[i] := ' ' ;
        procbuffer[count].procaddress := 0 ;
      end;
    pc := loadaddress ;      (* Store starts at load address  *)
    fstatus := correct ;
    recnr := 0 ;
    procf := 0 ;
    repeat
      getline(linelength, fstatus);
      checksum := 0 ;
      if fstatus <> endoffile
        then
          if(line[1] = 'P')or(line[1] = 'p')
            then
              case line[2] of
               '1' : Loadp1 ;
               '2' : Loadp2 ;
               '4' : Loadp4 ;
               '9' : fstatus := endoffile
              end  ;
     until(fstatus = endoffile)or(fstatus = checkerror);
     if fstatus = checkerror
      then
        begin
          writeln(errorfile,'Loading ended due to checkerror in record : ', recnr);
          exit ;
        end ;
   end  ;(* Loader *)

function WriteHex(hexbyte : integer): string ;
 (* write byte as two hex numbers into hexstring *)
  var
    hexstring: string ;

  function nibbletohex(nibble: integer): char ;
    begin
      if nibble  < 10
        then
          nibbletohex := chr(ord('0')+ nibble)
        else
          nibbletohex := chr(ord('A')+ nibble - 10) ;
     end ;(* nibbletohex *)

  begin
    if(hexbyte >= 0)and(hexbyte <= 256)
       then
         begin
           hexstring := nibbletohex(hexbyte div 16);
           hexstring := hexstring + nibbletohex(hexbyte mod 16);
         end
       else
         hexstring := '  ' ;
    WriteHex := hexstring ;
  end  ;(* WriteHex *)

function WriteHex4(hexword : integer): string;
  begin
    WriteHex4 := WriteHex(hexword shr 8) + WriteHex(hexword mod 256)
  end;

procedure WriteLevelInstruction(opcode  : integer ; var dpc : integer);
   (* Prints instruction mnemonic and if necessary arguments as numbers *)
  var
    i, level : integer ;
  begin
     level := opcode mod 16 ;
     opcode := opcode div 16 ;
     assemblerline := assemblerline + grinstruction[opcode].name +
      ' ' + WriteHex(level);
     for i := 1 to grinstruction[opcode].arg do
       begin
         objectline :=  objectline + ' ' + WriteHex(store[dpc + i]);
         assemblerline := assemblerline +  ' ' + WriteHex(store[dpc + i]);
       end ;
     dpc := dpc + 1 + grinstruction[opcode].arg ;
  end  ;(* WriteLevelInstruction *)

procedure FindProc(var procnr : integer ; pc : integer );
 (* Searches for proc/function in procbuffer with pc-address *)
  var
      i : integer ;
  begin
     procnr := -1 ;(* non-existing proc nr *)
     i := 0 ;
     repeat
       if procbuffer[i].procaddress = pc
        then
          begin
            procnr := i ;
            i := procf + 1
          end
        else
          i := i + 1
     until(i > procf);
  end  ;(* FindProc *)

{
procedure FindLabel(address: integer ;  var labelnr : integer)  ;

 (* Searches if address is a label, index in label table is label number *)
 (* returns label number or -1 if label not found *)

  var
      i : integer ;

  begin

     labelnr := -1 ;(* no label found *)
     i := 1 ;

     while (i <= maxlabel)or(labelnr = -1)do
       begin
         if labels[i] = address
           then
             labelnr := i ;
         i := i + 1
       end  ;

  end  ;

}
procedure WriteInstruction(opcode  : integer ;
                           var dpc : integer);
   (* Prints instruction mnemonic and if necessary
       arguments as numbers or string *)
    var
      i,
      nrargs      : integer ;
    procedure WriteENT(dpc : integer);
      var
        i, procnr : integer ;
      begin
        procnr := -1 ;
        FindProc(procnr, dpc);
        if procnr > -1
          then
            begin
              write(listfile, 'Procedure/Function/Program ');
              for i := 1 to strglgth do
                write(listfile, procbuffer[procnr].procname[i]);
              writeln(listfile)
            end
          else
            writeln(listfile, ' ':16, 'Unknown entry point');
        writeln(listfile);
        EndLineList ;
     end  ;(* WriteENT *)

  procedure PRCASE ;
   (* dump CASE structure in code *)
    var
      i,j,k, nrlabels, startvalue : integer ;
      offset : int16;
    begin
      writeln(listfile);
      EndLineList ;
      write(listfile, WriteHex4(dpc + 1));
      write(listfile, ' : ');
      write(listfile, WriteHex(store[dpc + 1]));
      write(listfile, ' ');
      write(listfile, WriteHex(store[dpc + 2]));
      write(listfile, '    start value case label = ');
      write(listfile,(store[dpc + 1] * 256 + store[dpc + 2]):3);
      writeln(listfile);
      EndLineList ;
      write(listfile, WriteHex4(dpc + 3));
      write(listfile, ' : ');
      write(listfile, WriteHex(store[dpc + 3]));
      write(listfile, ' ');
      write(listfile, WriteHex(store[dpc + 4]));
      write(listfile, '      end value case label = ');
      write(listfile,(store[dpc + 3] * 256 + store[dpc + 4]):3);
      writeln(listfile);
      EndLineList ;
      write(listfile, WriteHex4(dpc + 5));
      write(listfile, ' : ');
      write(listfile, WriteHex(store[dpc + 5]));
      write(listfile, ' ');
      write(listfile, WriteHex(store[dpc + 6]));
      offset := store[dpc + 5] * 256 + store[dpc + 6] ;
      if offset = 0
        then
          write(listfile, '    no otherwise part in case')
        else
          begin
            write(listfile, '    address of otherwise part = ');
            write(listfile, WriteHex4(offset + dpc + loadaddress + 5));
          end  ;
      startvalue := store[dpc + 1] * 256 + store[dpc + 2] ;
      nrlabels := store[dpc + 3] * 256 + store[dpc + 4] -
                  startvalue ;
      for i := 0 to  nrlabels do
        begin
          writeln(listfile);
          j := dpc + 2*i + 7 ;
          EndLineList ;
          write(listfile, WriteHex4(j));
          write(listfile,  ' : ');
          write(listfile, WriteHex(store[j]));
          write(listfile, ' ');
          write(listfile, WriteHex(store[j + 1]));
          write(listfile, '    case label value ');
          write(listfile,(i + startvalue):3);
          offset := (store[j] shl 8) + store[j + 1] ;
          if offset = 0
            then
              write(listfile, ' not used')
            else
              begin
                write(listfile, ' at address = ');
                write(listfile, WriteHex4(j + offset + loadaddress));
              end  ;
        end  ;
      writeln(listfile);
      nrargs := 6 + (nrlabels + 1) * 2 ;
    end  ;(* PRCASE *)

  procedure PrStringLCA ;
   (* Prints contents of string following opcode LCA
       in multiple lines if necessary                  *)
     var
       i, kar: integer ;
     begin
      (* show string as hex bytes in objectfile *)
       for i := 1 to store[dpc + 1] + 1 do
           objectline := objectline + ' ' + WriteHex(store[dpc + i]);
      (* show string as pascal string *)
       assemblerline := assemblerline + '''' ;
       for i:= 2 to  store[dpc + 1] + 1 do
         begin
           kar := store[dpc + i] ;
           if kar < 31
             then
               kar := ord('^');
            assemblerline := assemblerline + chr(kar)
          end  ;
       assemblerline := assemblerline + '''' ;
       nrargs := 1 + store[dpc + 1] ;
    end  ;(* PrStringLCA *)

    begin(* WriteInstruction *)

      nrargs := instruction[opcode].arg ;
      assemblerline := assemblerline + instruction[opcode].name ;
      if nrargs = 5
        then
          case opcode of
            $b6: PrCase;
            $bc: PrStringLCA;
          end
        else
          if opcode <> $BD
            then
              begin
               (* dump arguments *)
                for i := 1 to nrargs do
                  begin
                   assemblerline := assemblerline  + WriteHex(store[dpc + i])+ ' ';
                   objectline := objectline + WriteHex(store[dpc + i])+ ' ' ;
                  end  ;
              end  ;
     (* UJP and FJP *)
      if(opcode = $B1)or(opcode = $B2)(*  FJP or UJP *)
        then
          { should be label, collected in phase 1 }
          begin
            i := store[dpc + 1] * 256 + store[dpc + 2] + loadaddress ;
            objectline := objectline + '(* ' +
                          WriteHex(i div 256)+ WriteHex(i mod 256)+  ' *)'
          end
      else if(opcode = $91)(* for *)
        then
          begin
            write(listfile, ' loop back to body ');
            i := store[dpc + 1] * 256 + store[dpc + 2] + loadaddress ;
            WriteHex(i div 256);
            WriteHex(i mod 256);
            writeln(listfile)
          end
      else if(opcode = $BD)(* CSP *)
       (* should be symbol output for assembler *)
        then
          begin
            assemblerline := assemblerline + standardproc[store[dpc+1]] ;
            objectline := objectline + WriteHex(store[dpc+1])                        ;
          end
      {
      else if(opcode = 47) OR (opcode = 48)
        then
          begin
             procnr := store[dpc + 1] ;
             write(listfile, ' ', 'Procedure/Function/Program ');
             for i := 1 to 8 do
               write(listfile, procbuffer[procnr].procname[i]);
          end  } ;
      dpc := dpc + 1 + nrargs ;
    end ; (* WriteInstruction *)

  procedure DisAssemble {(phase: phasetype)} ;
 (* two phases
     - first one find labels, no output
     - second one, output with labels
     disassemble store upto pc last loaded
     asm file format
     list file format(normal instruction with two arguments max)
     AAAA OP(optional args)XX YY label opcode-menmonic values
     More then two args: line break after binary args
     CASE: special format
     UJP, FJP : label as value
     LCA string: string  *)
  var
    opcode  : integer ;
  begin
    dpc := loadaddress ;
    EndLineList ;
   (* header for assembler file *)
    writeln(asmfile, '      .program ', procbuffer[0].procname);
    writeln(listfile, '     .program ', procbuffer[0].procname);
    repeat
      opcode := store[dpc] ;
     (* write address and opcode in hex *)
      objectlinepre := WriteHex(dpc div 256)+ WriteHex(dpc mod 256)+ ': '
                      + WriteHex(opcode)+ '  ' ;
      objectline := '' ;
     (* label, now empty *)
      assemblerline := '      ' ;
     (* write arguments of opcode, label, values etc,
      increment dpc to next opcode *)
      if(opcode < $90)
        then
          writelevelinstruction(opcode, dpc)
        else
          WriteInstruction(opcode, dpc);
      writeln(listfile, objectlinepre , objectline);
      writeln(listfile, assemblerline);
      writeln(asmfile, assemblerline);
      EndLineList ;
    until dpc >= pc ;
    writeln(asmfile,'end.');
  end  ;(* DisAssemble *)

procedure DumpProcedureBuffer ;
  var
    count : integer ;
begin
  listlines := maxpage + 1 ;
  EndLineList ;
  writeln(listfile, 'Procedure buffer');
  EndLIneList ;
  writeln(listfile, 'Number Address Name');
  EndLIneList ;
  writeln(listfile, '-------------------');
  EndLineList ;
  for count := 0 to procf do
    begin
      write(listfile, ' ',WriteHex(count):3, '    ',
                      hexstr(procbuffer[count].procaddress, 4));
      if procbuffer[count].procname[1] = ' '
        then
          writeln(listfile, '   external routine')
        else
          writeln(listfile,'   ', procbuffer[count].procname);
       EndlineList ;
    end;
end;

function PascalmDisassembler : boolean ;
begin
  listpages := 1 ;
  listlines := maxpage + 1 ;
  FillInstructions ;
  pc := loadaddress ;
  Loader(loadaddress) ;
  if fstatus <> checkerror
    then
      begin
        {
        disassemble(phase1);
        }
       Disassemble {(phase2)} ;
       DumpProcedureBuffer ;
       writeln(errorfile, objectfilename,' disassembled for load address ', hexstr(loadaddress,4)) ;
       PascalmDisassembler := true
      end
    else
      begin
        writeln(errorfile, 'Error in disassembler in loading object file ', objectfilename) ;
        PascalmDisassembler := false
      end;
end ;
