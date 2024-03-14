program cpascalm2k1 ;

  { Compiles Pascal-M program to Px record object }

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

(* V1.0 Compiler based upon portable P2 compiler
    written by N.Wirth et al Zurich E.T.H.            *)

(* Additions for version 1.1 :

    - restructured
    - documented
    - upper- and lowercase accepted in identifiers
    - tab-characters accepted and expanded
    - form-feed character accepted and replaced with blank
    - listing file output
    - HALT and EXIT standard procedure added
    - compile time boundary check on sets
      in types and constants
    - beside else also OTHERWISE in CASE added
    - Error numbers renumbered and messages added
    - error in generating ENT instructions with parameter
      list corrected
    - error in generating correct code for set inclusion
      corrected in EXPRESSION and in CONDGEN
    - error in generating code for Read procedure if
      undeclared identifier used corrected

    Additions for version 1.2 :

    - filetype text added in standard names and read and write
    - standard procedures reset and rewriteadded including
      file-open non-standard extension
    - standard function status added for file-variables
    - standard procedure CLOSE added for file-variables
    - standard input file keyboard(not buffered, no echo)added
    - error in generating access to 1 byte parameters lod1
    - error in WriteProc checking types with Comptypes corrected
    - error in handling constant string array of char in
      procedure/function call in CallNonStandard corrected

    Additions for version 1.3 :

    - standard functions SUCC and PRED added
    - array of character constants and variables of any length
      may be assigned to variables of type(packed)array of char
      if length is less or more than nr of characters in array
      The result is padded with blanks or truncated
    - character may be assigned to array of char,
      result padded with blanks
    - bug in body(complex structures formal type corrected

    Additions for V1.4

    Turbo/Borland Pascal file open/close hacked in
    Corrected P4 -> P2 origin

   Additions for V2k1

    - Converted to Include file Pascal-M 2k1
    - no more direct console message, error file instead
    - lowercase syntax, bulk of extra empty lines removed
    - all file open/close removed
    - now a function, expecting files open
    - new function/procedure READMEM and WRITEMEM
      *)

{$RangeChecks ON$}

const
  displimit  =    15 ;
  maxlevel   =    12 ;
  (* size of store accessible by code *)
  maxaddr    = 32767 ;
  (* size in byte in core of variables *)
  (* 8 bytes for set, gives 64 possible members *)
  intsize          =     2 ;(* integer   *)
  charsize         =     1 ;(* character *)
  boolsize         =     1 ;(* boolean   *)
  setsize          =     8 ;(* set       *)
  ptrsize          =     2 ;(* pointer   *)
  strglgth         =     8 ;(* strings stored in blocks of 8 char's *)
  pathlen          =    80 ;(* filename length *)
  alphalen         =    40 ;(* general purpose string length *)
  lcaftermarkstack =     6 ;(* stack frame for interpreter *)
  maxint           = 32767 ;(* 16-bit's two's complement machine *)
  setmax           =    63 ;(* set has maximal 63 members *)
  maxstandrd       =    14 ;(* number of standard functions/procedures *)
  maxcode          =    29 ;(* codebuffer maximum 30 bytes *)
  maxpage          =    56 ;(* maximum number of lines on listing file *)
  maxfiles         =     7 ;(* maximum number of files in use total *)
  maxchcnt         =   120 ;(* maximum input line-length *)
  maxerlines       =    10 ;(* maximum number of errors in a line *)
  maxermsg         =   200 ;(* maximum number of error messages *)
  maxops           =    33 ;(* maximum number of operators *)
  maxopsp1         =    34 ;(* maximum number of operators plus one... *)
  (* ASCII character Control Constants *)
  atab     = 9   ;(* tab-character  *)
type
  (* basic symbols *)
  symbol  = (
    ident,
    intconst,
    realconst,
    stringconst,
    notsy,
    mulop,
    addop,
    relop,
    lparent,
    rparent,
    lbrack,
    rbrack,
    comma,
    semicolon,
    period,
    arrow,
    colon,
    becomes,
    constsy,
    typesy,
    varsy,
    funcsy,
    progsy,
    procsy,
    setsy,
    packedsy,
    arraysy,
    recordsy,
    externsy,
    forwardsy,
    beginsy,
    ifsy,
    casesy,
    repeatsy,
    whilesy,
    forsy,
    endsy,
    elsesy,
    untilsy,
    ofsy,
    dosy,
    tosy,
    downtosy,
    thensy,
    othersy        );
  operatortype =(  mul,
    andop,
    idiv,
    imod,
    shrop,
    shlop,
    plus,
    minus,
    orop,
    ltop,
    leop,
    geop,
    gtop,
    neop,
    eqop,
    inop,
    noop);
  setofsys  =  set of symbol      ;
  intset    =  set of 0 .. setmax ;
  strng = packed array[1 .. strglgth] of 0 .. 127  ;
  (* Constant type descriptor *)
  constptr = ^Constant ;
  Constant = record
    case integer of
      (* set *)
      0 :(pval   : intset);
      (* String *)
      1 :(slgth : 0 .. strglgth ;
        (* linked list pointer *)
        sptr  : constptr ;
        sval  : strng)
  end ;
  (* value of constant, can be simple integer or complex *)
  valu  =  record
    case integer of
      0 :(ival : integer);
      1 :(valp : constptr    )
  end ;
  (* data structures *)
  levrange  = -1 .. maxlevel ;
  addrrange = 0 .. maxaddr  ;
  structform =(  scalar,
    subrange,
    pointer,
    power,
    arrays,
    records,
    files     );
  declkind  = (  standard,
    declared   );
  (* identifier description *)
  identptr= ^identifier ;
  structptr = ^structure  ;
  structure = packed record
    size  : addrrange ;
    stype : structptr ;
    case form : structform of
      subrange :(min, max   : valu      );
      arrays   :(indextype  : structptr );
      records  :(fstfld     : identptr  )
  end ;
  (* names, identifier-classes  *)
  idclass =(types,
    konst,
    vars,
    field,
    proc,
    func  );
  setofids = set of idclass ;
  idkind =( actual,
    formal     );
  alpha = packed array[1 .. strglgth] of char ;
  pathstring = packed array[1 .. pathlen] of char ;
  alphastring = packed array[1 .. alphalen] of char ;
  identifier = packed record
    name   : alpha ;
    llink,
    rlink  : identptr  ;  (* to build binary tree *)
    idtype : structptr ;
    next   : identptr  ;  (* to build linked list *)
    case klass : idclass of
      konst :(values : valu)  ;
      vars  :(vkind : idkind    ;
        vlev  : levrange  ;
        vaddr : addrrange);
      proc, func :
      (case pfdeckind : declkind of
          standard :(key : 1 .. maxstandrd);
          declared :(pflev   : levrange ;
          pfname  : integer  ;
          forwdecl ,
          externl : boolean ))
  end ;
  disprange = 0 .. displimit ;
  (* Expressions *)
  attrkind = (  cst,
    varbl,
    expr  );
  vaccess = (  drct,
    indrct );
  (* result of expression evaluation *)
  attr    =  record
    typtr : structptr ;
    case kind : attrkind of
      cst   :(cval : valu);
      varbl :(access : vaccess  ;
        level  : levrange ;
        dplmt  : addrrange )
  end ;

var
  (* Variables returned by source program scanner InSymbol *)
  sy   : symbol     ;         (* Last symbol found *)
  op   : operatortype   ;         (* Classification of last symbol *)
  val  : valu       ;         (* Value of last symbol *)
  lgth : integer    ;         (* Length of last string constant *)
  id   : alpha      ;         (* Last identifier,possibly truncated *)
  kk   : 0  .. 8    ;         (* Nr's of chars in last identifier *)
  ch   : char       ;         (* Last character read *)
  ich  : integer    ;         (* ASCII value of last character *)
  (*  Line Variables *)
  linelength,
  chcnt        : 0 .. maxchcnt ;
  linpos       : integer ;
  line         : packed array[1 .. maxchcnt] of char ;
  linecount    : integer ;
  sourcename, destname : pathstring ;
  (* Counters *)
  lc,
  ic   : addrrange   ;    (* Data location and instruction counters *)
  icn,
  sumcheck : integer ;    (* Checksum *)
  codebuf  : array[0 .. maxcode] of 0 .. 255 ;
  nproc    : integer ;    (* Next procedure number *)
  mxintio  : integer ;
  (* Switches *)
  prterr  : boolean ;     (* To allow forward reference in pointer
                              type declaration by suppressing error
                              message    *)
  pfcttest : boolean ;    (* Detect function Calls in
                              parameter lists *)
  errflag  : boolean ;    (* Compiler Error flag *)
  (* Pointers *)
  intptr,
  charptr,
  boolptr,
  nilptr,
  fileptr  : structptr  ;    (* Pointers to standard identifiers *)
  utypptr,
  ucsptr,
  uvarptr,
  ufldptr,
  uprcptr,
  ufctptr  : identptr ;      (* Pointers for undeclared identifiers *)
  fwptr    : identptr ;      (* Head of chain of forw decl type ids *)
  progptr  : identptr ;       (* Pointer to program *)
  (* Bookkeeping of declaration levels *)
  level   : levrange  ;   (* Current static level *)
  disx    : disprange ;   (* Level of last ID searched by Searchid*)
  top     : disprange ;   (* Top of display *)
  savetop : disprange ;   (* Save top of display *)
 (* Symbol-table is organized as binary tree's per level.
     Each entry in display-array points to unbalanced binary tree,
     array-index is level of current procedure/function       *)
  display : array[disprange] of identptr;
  (* Error messages *)
  errinx : 0 .. 10 ;      (* Number of errors
                              in current source line *)
  errtot : integer ;      (* total number of errors *)
  errlist :
  array[1 .. maxerlines] of
  packed record
    pos : 1 .. maxchcnt  ;(* position of error found *)
    nmr : 1 .. maxermsg  (* number of error found   *)
  end ;
  (* Expression compilation *)
  gattr : attr  ;   (* Describes the expression being compiled *)
  (* Structured Constants *)
  constbegsys,
  simptypebegsys,
  typebegsys,
  blockbegsys,
  selectsys,
  facbegsys,
  statbegsys,
  typedels         : setofsys ;
  rw  : array[0 .. maxops]  of alpha    ;(* Reserved words       *)
  rop : array[0 .. maxops]  of operatortype ;(* Reserved             *)
  rsy : array[0 .. maxops]  of symbol   ;(* Reserved symbols     *)
  frw : array[0 .. 8 ]  of 0 .. maxopsp1  ;(* no res wrds          *)
  ssy : array[0 .. 127] of symbol   ;(* Not reserved symbols *)
  sop : array[0 .. 127] of operatortype ;
  nap : array[0 .. 15]  of alpha    ;(* Standard procedures *)
  naf : array[0 .. 8 ]  of alpha    ;(* Standard functions *)
  
  (* Used by the compiler driver itself. *)
  sourcefile, objectfile, errorfile : ^text ;
  ShowErrors : boolean ;

procedure WriteErrorMessage(var fp: text; err: integer);
begin
  case err of
    2: write(fp, 'Syntax: identifier expected');
    3: write(fp, 'Syntax: Program expected');
    4: write(fp, 'Syntax: ")" expected');
    5: write(fp, 'Syntax: ":" exepected');
    6: write(fp, 'Syntax: illegal symbol');
    7: write(fp, 'Syntax: actual parameter list');
    8: write(fp, 'Syntax: OF expected');
    9: write(fp, 'Syntax: "(" expected');
    10: write(fp, 'Syntax: type specfication expected');
    11: write(fp, 'Syntax: "[" expected');
    12: write(fp, 'Syntax: "]" expected');
    13: write(fp, 'Syntax: end expected');
    14: write(fp, 'Syntax: ";" expected');
    15: write(fp, 'Syntax: integer expected');
    16: write(fp, 'Syntax: "-" expected');
    17: write(fp, 'Syntax: begin expected');
    18: write(fp, 'Syntax: error in declaration part');
    19: write(fp, 'Syntax: error in field list');
    20: write(fp, 'Syntax: "," expected');
    21: write(fp, 'Syntax: "*" expected');
    50: write(fp, 'Syntax: "error in constant');
    51: write(fp, 'Syntax: ":=" expected');
    52: write(fp, 'Syntax: then expected');
    53: write(fp, 'Syntax: until expected');
    54: write(fp, 'Syntax: do expected');
    55: write(fp, 'Syntax: to/downto expected');
    56: write(fp, 'Syntax: if expected');
    58: write(fp, 'Syntax: ill-formed expression');
    59: write(fp, 'Syntax: error in variable');
    101: write(fp, 'Identifier declared twice');
    102: write(fp, 'Low bound exceeds high-bound');
    103: write(fp, 'Identifier is not a type identifier');
    104: write(fp, 'Identifier not declared');
    105: write(fp, 'Sign not allowed');
    106: write(fp, 'Number expected');
    107: write(fp, 'Incompatible subrange types');
    110: write(fp, 'Tag type must be an ordinal type');
    111: write(fp, 'Incompatible with tag type');
    113: write(fp, 'Index type must be an ordinal type');
    115: write(fp, 'Base type must be scalar or subrange');
    116: write(fp, 'Error in type of procedure parameter');
    117: write(fp, 'Unsatisfied forward reference');
    118: write(fp, 'Forward reference type identifier');
    119: write(fp, 'Forward declared : repetition par. list');
    120: write(fp, 'Function result: scalar,subrange,pointer');
    122: write(fp, 'Forward declared: repetition result type');
    123: write(fp, 'Missing result type in function declar.');
    125: write(fp, 'Error in type of standard function par.');
    126: write(fp, 'Number of parameters disagrees with decl');
    129: write(fp, 'Incompatible operands');
    130: write(fp, 'Expression is not of SET type');
    131: write(fp, 'Test on equality allowed only');
    132: write(fp, 'Inclusion not allowed in set comparisons');
    134: write(fp, 'Illegal type of operands');
    135: write(fp, 'Boolean operands required');
    136: write(fp, 'Set element must be scalar or subrange');
    137: write(fp, 'Set element types not compatible');
    138: write(fp, 'Type must be array');
    139: write(fp, 'Index type is not compatible with decl.');
    140: write(fp, 'Type must be record');
    141: write(fp, 'Type must be pointer');
    142: write(fp, 'Illegal parameter substitution');
    143: write(fp, 'Illegal type of loop control variable');
    144: write(fp, 'Illegal type of expression');
    145: write(fp, 'Type conflict');
    147: write(fp, 'Case label and case expression not comp.');
    148: write(fp, 'Subrange bounds must be scalar');
    149: write(fp, 'Index type must not be an integer');
    150: write(fp, 'Assignment to standard function illegal');
    152: write(fp, 'No such field in this record');
    154: write(fp, 'Actual parameter must be a variable');
    155: write(fp, 'Control variable declared interm. level');
    156: write(fp, 'Value already as a label in CASE');
    157: write(fp, 'Too many cases in CASE statement');
    160: write(fp, 'Previous declaration was not forward');
    161: write(fp, 'Again forward declared');
    169: write(fp, 'SET element not in range 0 .. 63');
    170: write(fp, 'String constant must not exceed one line');
    171: write(fp, 'Integer constant exceeds range(32767)');
    172: write(fp, 'Too many nested scopes of identifiers');
    173: write(fp, 'Too many nested procedures/functions');
    174: write(fp, 'Index expression out of bounds');
    175: write(fp, 'Internal compiler error : standard funct');
    176: write(fp, 'Illegal character found');
    177: write(fp, 'Error in type');
    178: write(fp, 'Illegal reference to variable');
    179: write(fp, 'Internal error : wrong size variable');
    180: write(fp, 'Maximum number of files exceeded');
  else
    write(fp, 'Unknown error ', err)
  end;
end ;(* FillErrorMessages *)

procedure BeginLine ;
var
  kar : char ;
  (* reads line from source into line *)
begin
  if eof(sourcefile^)
  then
  begin
    writeln(errorfile^) ;
    writeln(errorfile^,'Premature end of source file');
    writeln(objectfile^,'P1010000');
    errflag := true ;
  end
  else
  begin
    linelength := 0 ;
    linecount := linecount + 1 ;
    while(not eoln(sourcefile^))and
      (linelength < maxchcnt)do
    begin
      linelength := linelength + 1 ;
      read(sourcefile^, kar);
      line[linelength] := kar ;
    end ;
    readln(sourcefile^);
    chcnt := 0 ;
    linpos := 0;
  end ;
end ;(* BeginLine *)

procedure EndLine ;
 (* writes line to listing-file and reports errors if any
    on terminal and in listing *)
var
  lastpos,
  freepos,
  currpos,
  currnmr,
  f, k     : integer ;
begin
  (* Output Error-messages *)
  if errinx > 0
  then
  begin
    writeln(errorfile^) ;
    write(errorfile^, ' Errors at ', linecount:4, ': ' ) ;
    for k := 1 to linelength do
      write(errorfile^, line [ k ] ) ;
    writeln(errorfile^) ;
    write(errorfile^,' **** ') ;
    lastpos := 0 ;
    freepos := 1 ;
    for k :=1 to errinx do
    begin
      currpos := errlist[k].pos ;
      currnmr := errlist[k].nmr ;
      if currpos <= lastpos
      then
        write(errorfile^,',')
      else
      begin
        while  freepos < currpos do
        begin
          write(errorfile^,' ') ;
          freepos := freepos + 1 ;
        end ;
        write(errorfile^,'^') ;
        lastpos := currpos ;
      end ;
      if currnmr < 10
      then
        f := 1
      else
      if currnmr < 100
      then
        f := 2
      else
        f := 3 ;
      write(errorfile^, currnmr:f) ;
      freepos := freepos + f + 1 ;
    end ;
    writeln(errorfile^) ;
    (* Display the meaning of the error-numbers *)
    for k := 1 to errinx do
    begin
      currnmr := errlist[k].nmr ;
      write(errorfile^, ' ':11, currnmr:3, ' = ');
      WriteErrorMessage(errorfile^, currnmr);
      writeln(errorfile^);
    end ;
    errinx := 0 ;
  end;
end ; (* EndLine *)

procedure Error(ferrnr : integer);
(* adds error to errors for current line *)
begin
  errflag := true ;
  errtot := errtot + 1 ;
  if errinx >= 9
  then
  begin
    errlist[10].nmr := maxermsg ;
    errinx := 10;
  end
  else
  begin
    errinx := errinx + 1 ;
    errlist[errinx].nmr := ferrnr;
  end ;
  errlist[errinx].pos := linpos;
end ;(* Error *)

function StringSize(lvp : constptr): integer ;
  (* calculates length of string, build up of linked list
      of constptr's cells, lvp points at list-head  *)
var
  n : integer ;(* length counter *)
begin
  n := 0 ;
  (* walk through linked list until end *)
  while lvp <> nil do
  begin
    n := n + lvp^.slgth ;
    lvp := lvp^.sptr;      (* next cell *)
  end ;
  StringSize := n;         (* return result *)
end ;(* StringSize *)

procedure InSymbol ;
(* Read next basic symbol of source program and return its
    description in the global variables
    sy   = symbol found
    op   = operatortype if any
    id   = name if identifier
    val  = value if constant
    lgth = number of characters if string

    Symbols parsed :

    - identifier, reserved or declared
    - integer-constant
    - string-constant
    - colon or becomes
    - period or double period(=colon)
    - operator-symbols less, less or equal, greater, greater or equal,
                     not equal
    - hex-constant, returned as integer-constant
    - single character symbols as found in table ssy

    - Comments, new lines  skipped, illegal symbols and
      characters flagged                                  *)

var
  i, k : integer ;
  chstring : strng ;
  lvp, lvp1 : constptr ;
  test, comnt : boolean ;
  quotechar : char ;

  procedure NextChar ;
    (* returns next character from input in
          ch  = character,
          ich = ordinal value of character,
        translates tab in one space
        keeps count of position in line and real incl tabs *)
  begin
    (* new line from input necessary ? *)
    if chcnt > linelength
    then
    begin
      EndLine ;
      BeginLine;
    end ;
    chcnt := chcnt + 1 ;
    linpos := linpos + 1 ;
    if chcnt > linelength
    then
      ch := ' '    (* return blank if end of line reached *)
    else
      ch := line[chcnt] ;
    (* get ordinal value *)
    ich := ord(ch);
    (* correct for  tab-characters *)
    if ich = atab
    then
    begin
      ch := ' ' ;
      ich := ord(ch);
      linpos := linpos + 7;
    end;
  end ;(* NextChar *)

begin (* InSymbol *)
  chstring[1] := 0 ;
  repeat(* until symbol found, skip comments *)
    comnt := true ;
    (* skip blanks *)
    while ch = ' ' do
      NextChar ;
    if((ch >= 'A')and(ch <= 'Z')or
      (ch >= 'a')and(ch <= 'z'))
    then
       (* identifier found, starts with upper- or lowercase :

                          --------
         ident -->-------! letter !----------->--
                    ^     --------      v
                    !     --------      !
                     --<-! letter !-----
                    !     --------      !
                    !     --------      v
                     --<-! digit  !-----
                         --------             *)

    begin
      kk := 0 ;
      id := '        ' ;
      repeat
        (* only 8 characters significant in name, skip rest *)
        if kk < 8
        then
        begin
          kk := kk + 1 ;
          (* translate uppercase to lowercase in identifier *)
          if(ch >= 'A')and(ch <= 'Z')
          then
          begin
            ich := ich + 32 ;
            ch := chr(ich);
          end ;
          id[kk]  := ch;
        end ;
        NextChar
      until not(((ch >= '0')and(ch <= '9'))or
          ((ch >= 'a')and(ch <= 'z'))or
          ((ch >= 'A')and(ch <= 'Z')));
      sy := ident ;
      op := noop  ;
         (* search for reserved name, fast search by using
             length as index with table kk                  *)
      i := frw[kk-1] ;

      while i <= frw[kk] -1 do
      begin
        if rw[i] = id
        then
        begin
          sy := rsy[i] ;
          op := rop[i];
        end ;
        i := i + 1;
      end;
    end

    else if(ch >= '0')and(ch <= '9')
    then
           (* Integer constant, only digits expected :

                              --------
     integer-constant ->-----! digit  !----------->--
                        ^     --------      v
                        !     --------      !
                         --<-! digit  !-----
                              --------             *)

    begin
      op := noop ;
      test := false ;
      k := 0 ;
      repeat
        if k <= mxintio
        then
          k := k * 10 + ich - ord('0')
        else
          test := true ;
        NextChar
      until(ch < '0')or(ch > '9');
      if test
      then
        Error(171);(* number too large *)
      val.ival := k ;
      sy := intconst;
    end

    else if(ch = '''')or(ch = '"')
    then
      (* String, starts with and ends with(d)quote *)
         (* Put string from input in linked list of
             constants, each constant containing max 8 char's *)
    begin
      lgth := 0 ;
      sy := stringconst ;
      op := noop ;
      lvp := nil ;
      quotechar := ch ;(* start and end with same quote *)
      val.valp := nil;
      repeat
        repeat
          if(chcnt > linelength)
          then
            Error(170);(* string must be on one line *)
          NextChar ;
          lgth := lgth + 1 ;
          if lgth > strglgth
          then
          begin
            new(lvp1);
            if lvp <> nil
            then
              lvp^.sptr := lvp1 (* link to list *)
            else
              val.valp := lvp1 ;(* new list *)
            lvp := lvp1 ;
            lvp^.sval := chstring ;
            lvp^.slgth := strglgth ;
            lvp^.sptr := nil ;
            lgth := 1;
          end ;
          chstring[lgth] := ich
        until ch = quotechar ;
        NextChar
      until ch <> quotechar ;
      lgth := lgth - 1 ;     (* nr of char's in string *)
      if(lgth = 1)and(lvp = nil)
      then
        val.ival := chstring[1](* only one character *)
      else
      (* create list-head pointer describing string *)
      if lgth <> 0 then
      begin
        new(lvp1);
        if lvp <> nil
        then
          lvp^.sptr := lvp1
        else
          val.valp := lvp1 ;
        lvp1^.sval := chstring ;
        lvp1^.slgth := lgth  ;
        lvp1^.sptr := nil ;
        lgth := StringSize(val.valp);
      end;
    end

    else if ch = ':'
    then
    begin
      op := noop ;
      NextChar ;
      if ch = '='
      then
      begin
        sy := becomes ;
        NextChar;
      end
      else
        sy := colon;
    end

    else if ch = '.'
    then
    begin
      op := noop ;
      NextChar ;
      if ch = '.'
      then
      begin
        sy := colon ;
        NextChar;
      end
      else
        sy := period;
    end

    else if ch = '<'
    then
    begin
      NextChar ;
      sy := relop ;
      if ch = '='
      then
      begin
        op := leop ;
        NextChar;
      end
      else
      if ch = '>'
      then
      begin
        op := neop ;
        NextChar;
      end
      else
        op := ltop;
    end

    else if ch = '>'
    then
    begin
      NextChar ;
      sy := relop ;
      if ch = '='
      then
      begin
        op := geop ;
        NextChar;
      end
      else
        op := gtop;
    end

    else if ch = '('
    then
    begin
      NextChar ;
      if ch = '*'(* skip comment *)
      then
      begin
        NextChar ;
        repeat
          while ch <> '*' do
            NextChar ;
          NextChar ;
        until ch = ')' ;
        NextChar ;
        comnt := false;
      end
      else
      begin
        sy := lparent ;
        op := noop;
      end;
    end

    else if ch = '{'(* comment *)
    then
    begin
      (* Skip until right acculade found *)
      while ch <> '}' do
        NextChar ;
      NextChar ;
      comnt := false;
    end


    else if ch = '$'(* hex constant, 0 .. 9, A .. F *)
    then
    begin
      op := noop ;
      k := 0 ;
      repeat
        NextChar ;
        if(ch >= '0')and(ch <= '9')
        then
          i := ich - ord('0')
        else if(ch >= 'A')and(ch <= 'F')
        then
          i := ich - ord('A')+ 10
        else if(ch >= 'a')and(ch <= 'f')
        then
          i := ich - ord('a')+ 10
        else
          i := -1 ;
        if i >= 0
        then
          k := 16*k + i ;
      until i < 0 ;
      val.ival := k ;
      sy := intconst;
    end

    else (* other single character symbols *)
    begin
      sy := ssy[ich] ;
      op := sop[ich] ;
      NextChar ;
      if sy = othersy
      then
        Error(176); (* illegal character found *)
    end ;

  until comnt ;

(* debug
write('Symbol found = ');

CASE sy OF

ident : writeln('ident ');
intconst : writeln('intconst ');
realconst : writeln('realconst ');
stringconst : writeln('stringconst ');
notsy : writeln('notsy ');
mulop : writeln('mulop ');
addop : writeln('addop ');
relop : writeln('relop ');
lparent : writeln('lparent ');
rparent : writeln('rparent ');
lbrack : writeln('lbrack ');
rbrack : writeln('rbrack ');
comma : writeln('comma ');
semicolon : writeln('semicolon ');
period : writeln('period ');
colon : writeln('colon ');
becomes : writeln('becomes ');
constsy : writeln('constsy ');
typesy : writeln('typesy ');
varsy : writeln('varsy ');
funcsy : writeln('funcsy ');
progsy : writeln('progsy ');
procsy : writeln('procsy ');
setsy : writeln('setsy ');
packedsy : writeln('packedsy ');
arraysy : writeln('arraysy ');
recordsy : writeln('recordsy ');
externsy : writeln('externsy ');
forwardsy : writeln('forwardsy ');
beginsy : writeln('beginsy ');
ifsy : writeln('ifsy ');
casesy : writeln('casesy ');
repeatsy : writeln('repeatsy ');
whilesy : writeln('whilesy ');
forsy : writeln('forsy ');
endsy : writeln('endsy ');
elsesy : writeln('elsesy ');
untilsy : writeln('untilsy ');
ofsy : writeln('ofsy ');
dosy : writeln('dosy ');
tosy : writeln('tosy ');
downtosy : writeln('downtosy ');
thensy : writeln('thensy ');
othersy : writeln('othersy ');
otherwise writeln('unknown symbol found');
end;

write('operatortype = ');
CASE op OF
mul : writeln('mul');
andop : writeln('andop ');
idiv : writeln('idiv ');
imod : writeln('imod ');
plus : writeln('plus ');
minus : writeln('minus ');
orop : writeln(' orop ');
ltop : writeln('ltop ');
leop : writeln('leop ');
geop : writeln('geop ');
gtop : writeln('gtop ');
neop : writeln('neop ');
eqop : writeln('eqop ');
inop : writeln('inop ');
noop : writeln('noop ');
otherwise writeln('unknown operator');

 end;

write('id = ');
for i := 1 to 8 do
write(id[i]);
writeln ;
 debug *)

end ;(* InSymbol *)

procedure Enterid(fcp : identptr);
(* Enter ID pointed at by FCP into the name-table,
    which on each declaration level is organized as
    an unbalanced binary tree                       *)
var
  nam : alpha ;
  lcp, lcp1 : identptr;
  lleft : boolean ;
begin
  nam := fcp^.name ;
  lcp := display[top] ;
  if lcp = nil
  then
    (* empty tree , enter at root *)
    display[top] := fcp
  else
  begin
    (* find place in tree where to put identifier *)
    repeat
      lcp1 := lcp ;
          (* Decide if left or right to go, if
              name conflict follow right link *)
      if lcp^.name = nam
      then
      begin
        (* already present *)
        Error(101);
        lcp := lcp^.rlink ;
        lleft := false;
      end
      else if lcp^.name < nam
      then
      begin
        (* go right *)
        lcp := lcp^.rlink ;
        lleft := false;
      end
      else
      begin
        (* go left *)
        lcp := lcp^.llink ;
        lleft := true;
      end
    until lcp = nil ;

    (* place found, link identifier in tree *)
    if lleft
    then
      lcp1^.llink := fcp
    else
      lcp1^.rlink := fcp;
  end ;
  (* identifier is new leave, no left or right pointers yet *)
  fcp^.llink := nil ;
  fcp^.rlink := nil;
end ; (* Enterid *)

procedure SearchSection(fcp : identptr; var fcp1 : identptr);
(* To find record fields and forward declared
    procedure id's
    called by
       - procedure ProcedureDeclaration
       - procedure Selector
    search starts in tree at identifier pointed by fcp,
    searched for identifier with same name as id        *)
begin
  (* indicate not found yet *)
  fcp1 := nil ;
  while(fcp <> nil)and(fcp1 = nil)do
    if fcp^.name = id
    then
      (* found, stop search and return pointer *)
      fcp1 := fcp
    else
    (* not found, descend down right or left *)
    if fcp^.name < id
    then
      fcp := fcp^.rlink
    else
      fcp := fcp^.llink;
end ;(* SearchSection *)
procedure Searchid(fidcls : setofids ; var fcp : identptr);
(* Search identifier in symbol-table, start at display-level
    top and go down to bottom display. Search based on name id.
    If found then type is checked with types in fidcls.
    If not found then return unknown type-description *)
var
  lcp : identptr;
begin

  (* search starts at top and identifier is not found yet *)
  disx := top + 1 ;
  fcp := nil ;

  while(disx > 0)and(fcp = nil)do
  begin
    disx := disx - 1 ;

    (* new root *)
    lcp := display[disx] ;

    (* search tree *)
    while(lcp <> nil)and(fcp = nil)do
      (* decide if found or go down right or left *)
      if lcp^.name = id
      then
        (* check if type is in fidcls *)
        if lcp^.klass in fidcls
        then
          fcp := lcp
        else
        begin
          (* not appropiate class *)
          if prterr
          then
            Error(103);
          (* go right, maybe double declaration *)
          lcp := lcp^.rlink;
        end
      else if lcp^.name < id
      then
        (* go right *)
        lcp := lcp^.rlink
      else
        (* go left *)
        lcp := lcp^.llink;

  end ;

  (* Search not successful, suppress Error message
      in case of forward referenced type id in pointer type
      definition --> procedure SimpleType                  *)

  if prterr and(fcp = nil)
  then
  begin
    Error(104);
        (* To avoid returning nil, reference an entry
            for undeclared ID of appropiate class
            ---> procedure Enterundecl                     *)
    if types in fidcls
    then
      fcp := utypptr
    else if vars in fidcls
    then
      fcp := uvarptr
    else if field in fidcls
    then
      fcp := ufldptr
    else if konst in fidcls
    then
      fcp := ucsptr
    else if proc in fidcls
    then
      fcp := uprcptr
    else
      fcp := ufctptr ;
  end;

end ;(* Searchid *)

procedure GetBounds(fsp : structptr ; var fmin, fmax : integer);
(* Get internal bounds of subrange or scaler type ,
    Assume FSP <> nil and fsp^.form <= subrange and fsp <> intptr,
    returns bounds in fmin and fmax *)
begin
  if fsp^.form = subrange
  then
  begin
    fmin := fsp^.min.ival ;
    fmax := fsp^.max.ival;
  end
  else  (* scalar *)
  begin
    fmin := 0 ;
    if fsp = charptr
    then
      (* characters *)
      fmax := 127
    else
      (* other scalars *)
      fmax := 0;
  end;
end ;(* GetBounds *)

procedure HexOut(word : integer);
(* writeword as four hex characters *)
var
  k : integer ;
begin
  sumcheck := sumcheck + word ;
  while word < 0 do
    word := word + 256 ;
  k := word div 16 ;
  word := word mod 16 ;
  if k < 10
  then
    write(objectfile^, chr(ord('0')+ k))
  else
    write(objectfile^, chr(ord('A')+ k - 10));
  if word < 10
  then
    write(objectfile^, chr(ord('0')+ word))
  else
    write(objectfile^, chr(ord('A')+ word  - 10));
end ;(* HexOut *)

procedure WriteOut ;
(* write P1-record with code buffer and checksum,
   codebuffer empty and instruction-counter is updated *)
var
  i : integer ;
begin
  if icn <> 0
  then
  begin
    write(objectfile^, 'P1');
    sumcheck := 0 ;
    HexOut(icn + 1);
    for i := 0 to icn - 1 do
      HexOut(codebuf[i]);
    HexOut((16383 - sumcheck)mod 256);
    writeln(objectfile^);
  end ;
  ic := ic + icn ;
  icn := 0;
end ;(* WriteOut *)

procedure Block(fsys : setofsys ; fsy : symbol ; fprocp : identptr);
(* compiles block *)
type
  oprange = 0 .. 255 ;
var
  lsy : symbol ;
  test : boolean ;

  procedure ByteGen (byte : integer);
  (* add byte to codebuffer, empty codebuffer if necessary *)
  begin
    if icn = maxcode + 1
    then
      WriteOut ;
    codebuf[icn] := byte ;
    icn := icn + 1;
  end ;(* ByteGen *)

  procedure WordGen(word : integer);
  (* put word as two bytes in codebuffer *)
  begin
    ByteGen(word shr 8);
    ByteGen(word mod 256);
  end ;(* WordGen *)

  procedure GenUJPent(fop : oprange ; word : integer);
  (* generate fop instruction, followed by fp2 as word *)
  begin
    ByteGen(fop);
    WordGen(word);
  end ;(* GenUJPent *)

  procedure PlantWord(location, value : integer);
  (* plant value at location in code ,
      generate P2-record if loc not in codebuffer *)
  begin
    if value <> 0 then
      if (location >= ic) and (location - ic < icn) then
      begin
        (* place in codebuffer *)
        (* correct for offset in codebuffer *)
        location := location - ic ;
        codebuf[location] := value shr 8 ;
        codebuf[location + 1] := value mod 256;
      end
      else
      begin
        (* Generate P2-record with location and value *)
        WriteOut ;
        write(objectfile^, 'P2');
        sumcheck := 0 ;
        (* first location *)
        HexOut(location shr 8);
        HexOut(location mod 256);
        (* next value to be planted *)
        HexOut(value shr 8);
        HexOut(value mod 256);
        HexOut((16383 - sumcheck)mod 256);
        writeln(objectfile^);
      end;
  end ;

  procedure Skip(fsys : setofsys);
  (* Skip input chstring until relevant symbol found *)
  begin
    while(not(sy in fsys))do
      InSymbol;
  end ;(* Skip *)

  procedure Test1(fsys : setofsys ; errornr : integer);
  (* Test if current symbol sy in set fsys, if not generate
      error with number errornr and skip until sy in fsys *)
  begin
    if not(sy in fsys)
    then
    begin
      Error(errornr);
      Skip(fsys);
    end;
  end ;(* Test1 *)

  procedure Test2(fsys : setofsys; errornr : integer; s2 : setofsys);
  (* Test if current symbol sy in set fsys, if not generate
      error with number errornr and skip until sy in fsys + s2 *)
  begin
    if not(sy in fsys)
    then
    begin
      Error(errornr);
      Skip(fsys + s2);
    end;
  end ;(* Test2 *)

  procedure Intest(sym : symbol ; errornr : integer);
  (* Test if current symbol sy is sym, if not generate
      error with number errornr , get next symbol from input *)
  begin
    if sy = sym
    then
      InSymbol
    else
      Error(errornr);
  end ;(* Intest *)

  procedure Constant(fsys : setofsys    ;
    var fsp : structptr      ;
    var fvalu : valu);
  (* checks if constant, declared or string-constant or integer,
      returns decsription in fsp , value in fvalu *)
  type
    signs =(none, pos, neg);
  var
    lsp  : structptr ;
    lcp  : identptr;
    sign : signs ;
  begin
    (* not a constant, value zero *)
    lsp := nil ; lcp := nil ;
    fvalu.ival := 0 ;
    Test2(constbegsys, 50, fsys);
    if sy in constbegsys
    then
    begin
      if sy = stringconst
      then
      begin
        if lgth = 1
        then
          lsp := charptr
        else
        begin
          new(lsp);
          lsp^.stype := charptr ;
          lsp^.indextype := nil ;
          lsp^.size := StringSize(val.valp);
          lsp^.form := arrays ;
        end ;
        fvalu := val ;
        InSymbol;
      end
      else
        (* other than string-constant, first check if sign *)
      begin
        sign := none ;
        if(sy = addop)and(op in[plus, minus])
        then
        begin
          if op = plus
          then
            sign := pos
          else
            sign := neg ;
          InSymbol;
        end ;

        (* constant can be declared identifier or declared constant *)
        if sy = ident
        then
        begin
          Searchid([konst],lcp);
          lsp := lcp^.idtype ;
          fvalu := lcp^.values ;
          if sign <> none
          then
            if lsp = intptr
            then
            begin
              if sign = neg
              then
                fvalu.ival := - fvalu.ival ;
            end
            else
              (* sign not allowed *)
              Error(105);
          InSymbol;
        end
        else if sy = intconst
        then
        begin
          if sign = neg
          then
            val.ival := -val.ival ;
          lsp := intptr ;
          fvalu := val ;
          InSymbol;
        end
        else
        begin
          (* number expected *)
          Error(106);
          Skip(fsys);
        end;
      end ;
      Test1(fsys,6);
    end ;
    fsp := lsp;
  end ;(* Constant *)

  function CompTypes(fsp1 , fsp2 : structptr): boolean ;
  (* Decide whether structures pointed at by FSP1 and
      FSP2 are compatible                              *)
  begin
    if fsp1 = fsp2
    then
      CompTypes := true
    else
    if(fsp1 <> nil)and(fsp2 <> nil)
    then
    begin
      if fsp1^.form = fsp2^.form
      then
        case fsp1^.form of
          scalar , records          :
            CompTypes := false ;
          subrange, pointer, power  :
            CompTypes :=
              CompTypes(fsp1^.stype,fsp2^.stype);
          arrays                    :
            CompTypes :=
              CompTypes(fsp1^.stype,fsp2^.stype)
              and
              (fsp1^.size = fsp2^.size)
        end
      (* fsp1^.form <> fsp2^.form)*)
      else if fsp1^.form = subrange
      then
        CompTypes := CompTypes(fsp1^.stype, fsp2)
      else if fsp2^.form = subrange
      then
        CompTypes := CompTypes(fsp1, fsp2^.stype)
      else
        CompTypes := false;
    end
    else
      CompTypes := true;
  end ;(* CompTypes *)

  function IsString(fsp : structptr): boolean ;
    (* Tests if structure pointed by with fsp is string *)
  begin
    IsString := false ;
    if fsp <> nil
    then
      if fsp^.form = arrays
      then
        if CompTypes(fsp^.stype, charptr)
        then
          IsString := true;
  end ;(* IsString *)

  procedure Typ(fsys : setofsys ;
    var fsp : structptr ;
    var fsize : addrrange );
  var
    lsp, lsp1, lsp2 : structptr ;
    oldtop : disprange ;
    lcp : identptr;
    lsize, displ : addrrange ;
    lmin, lmax : integer ;

    procedure simpletype(fsys : setofsys ;
      var fsp : structptr ;
      var fsize : addrrange);
  (* parses and returns description and size of simple type
      structure parsed :
                         -----------------
      --------->--------! type identifier !--------------->
            !            -----------------            !
            v                                         ^
            !       ---     ------------     ---      !
            !-->---( ( )---! identifier !---( ) )-----!
            !       ---  !  ------------     ---      !
            !            !              !             !
            !            !      ---     !             !
            !             -----( , )----              !
            !                   ---                   !
            !                                         !
            !     ----------    ----    ----------    !
             ----! constant !--( .. )--! constant !---
                  ----------    ----    ----------           *)
    var
      lsp, lsp1 : structptr ;
      lcp, lcp1 : identptr;
      ttop : disprange ;
      lcnt : integer ;         (* keeps track of enumerated constants *)
      lvalu : valu ;
    begin
      fsize := 1 ;

      lsp1 := nil ;
      Test2(simptypebegsys, 1, fsys);
      if not(sy in simptypebegsys)
      then
        fsp := nil
      else
      begin
        if sy = lparent
        then
          (* enumeration type *)
        begin
          ttop := top ;
          top := savetop ;
          new(lsp);
          lsp^.form := scalar ;
          lcp1 := nil ;
          lcnt := 0 ;
          repeat
            InSymbol ;
            (* enumeration must be list of constant idents *)
            if sy <> ident
            then
              Error(2)
            else
            begin
              new(lcp);
              lcp^.name := id ;
              lcp^.idtype := lsp ;
              lcp^.next := lcp1 ;
              lcp^.values.ival := lcnt ;
              lcp^.klass := konst ;
              Enterid(lcp);
              lcnt := lcnt + 1 ;
              lcp1 := lcp ;
              InSymbol ;
            end ;
            Test1(fsys+[comma,rparent],6);
          until sy <> comma ;
          lsp^.fstfld := lcp1 ;
          top := ttop ;
          (* check if enumeration-type fits in one byte *)
          if lcnt < 257
          then
            lsp^.size := 1
          else
            lsp^.size := intsize ;
          Intest(rparent, 4);
        end
        else if sy = ident
        then
          (* type-identifier or declared constant *)
        begin
          Searchid([types,konst], lcp);
          InSymbol ;
          if lcp^.klass = types
          then
            lsp := lcp^.idtype
          else
            (* subrange starts with constant *)
          begin
            new(lsp);
            lsp^.stype := lcp^.idtype ;
            lsp^.form := subrange ;
            if IsString(lsp^.stype)
            then
            begin
              Error(148);
              lsp^.stype := nil;
            end ;
            lsp^.min := lcp^.values ;
            lsp^.size  := lcp^.idtype^.size ;
            Intest(colon, 5);
            lvalu.ival := 0 ;
            Constant(fsys, lsp1, lvalu);
            lsp^.max := lvalu ;
            if lsp^.stype <> lsp1
            then
              Error(107);
          end;
        end(* sy is ident *)
        else(* must be subrange starting with a constant *)
        begin
          new(lsp);
          lsp^.form := subrange ;
          Constant(fsys +[colon], lsp1, lvalu);
          if IsString(lsp1)
          then
          begin
            Error(148);
            lsp1 := nil;
          end ;
          lsp^.stype := lsp1 ;
          lsp^.min := lvalu ;
          lsp^.size := intsize ;
          Intest(colon, 5);
          Constant(fsys, lsp1 , lvalu);
          lsp^.max := lvalu ;
          if lsp^.stype <> lsp1
          then
            Error(107);
        end ;
        if lsp <> nil
        then
          if lsp^.form = subrange
          then
            if lsp^.min.ival > lsp^.max.ival
            then
                     (* startvalue of subrange must be smaller
                         than endvalue *)
              Error(102);
        fsp := lsp ;
        Test1(fsys, 6);
      end ;
      if lsp <> nil
      then
        fsize := lsp^.size ;
    end ;(* simpletype *)

    procedure fieldlist(fsys : setofsys);
  (* Parses field-list,
      returns displ = total space needed to store field-list in record
      uses nxt^ as linked list, see Jensen & wirth page 116
      for syntax diagram *)
    var
      lcp , lcp1, nxt, nxt1 : identptr;
      lsp, lsp3 : structptr ;
      minsize, maxsize, lsize : addrrange ;
      lvalu : valu ;
    begin
      nxt1 := nil ;
      lsp := nil ;
      lcp := nil ;
      lcp1 := nil ;

      lsp3 := nil ;
      lsize := 0 ;

      Test2([ident, casesy], 19, fsys );
      while sy = ident do
      begin
        nxt := nxt1 ;
        repeat
          if sy <> ident
          then
            Error(2)
          else
          begin
            new(lcp);
            lcp^.name := id ;
            lcp^.idtype := nil ;
            (* link to list *)
            lcp^.next := nxt ;
            lcp^.klass := field ;
            nxt := lcp ;
            Enterid(lcp);
            InSymbol;
          end ;
          Test2([comma,colon],6,fsys +[semicolon, casesy]);
          test := sy <> comma ;
          if not test
          then
            InSymbol
        until test ;
        Intest(colon, 5);
        Typ(fsys +[casesy,semicolon] , lsp, lsize);
        while nxt <> nxt1 do
        begin
          nxt^.idtype := lsp ;
          nxt^.vaddr := displ ;
          nxt := nxt^.next ;
          displ := displ + lsize;
        end ;
        nxt1 := lcp ;
        if sy = semicolon
        then
        begin
          InSymbol ;
          Test2([ident, casesy, semicolon], 19, fsys);
        end;
      end ;(* while *)
      nxt := nil ;
      while nxt1 <> nil do
      begin
        lcp := nxt1^.next ;
        nxt1^.next := nxt ;
        nxt := nxt1 ;
        nxt1 := lcp;
      end ;
      (* field-list may contain a variant part *)
      if sy = casesy
      then
      begin
        InSymbol ;
        if sy = ident
        then
        begin
          (* suppress error messages if forward ref pointer *)
          prterr := false ;
          Searchid([types] , lcp1);
          prterr := true ;
          if lcp1 = nil
          then
          begin
            new(lcp);
            lcp^.name := id ;
            lcp^.idtype := nil ;
            lcp^.klass := field ;
            lcp^.next := nil ;
            lcp^.vaddr := displ ;
            Enterid(lcp);
            InSymbol ;
            Intest(colon, 5);
            if sy = ident
            then
            begin
              Searchid([types], lcp1);
              lsp1 := lcp1^.idtype ;
              if lsp1 <> nil
              then
              begin
                displ := displ + lsp1^.size ;
                if(lsp1^.form <= subrange)or
                  (IsString(lsp1))
                then
                begin
                  if IsString(lsp1)
                  then
                    Error(177);
                  lcp^.idtype := lsp1;
                end
                else
                  Error(110);
              end ;
              InSymbol;
            end
            else
            begin
              Error(2);
              Skip(fsys +[ofsy, lparent]);
            end;
          end
          else
          begin
            InSymbol ;
            lsp1 := lcp1^.idtype;
          end;
        end
        else
        begin
          Error(2);
          Skip(fsys+[ofsy,lparent]);
        end ;

        Intest(ofsy, 8);
        minsize := displ ;
        maxsize := displ ;
        repeat
          lsp2 := nil ;
          repeat
            lvalu.ival := 0 ;
            Constant(fsys +[comma,colon,lparent],lsp3,lvalu);
            if not CompTypes(lsp1, lsp3)
            then
              Error(111);
            test := sy <> comma ;
            if not test
            then
              InSymbol
          until test ;
          Intest(colon, 5);
          Intest(lparent, 9);
          fieldlist(fsys +[rparent,semicolon]);
          if displ > maxsize
          then
            maxsize := displ ;
          if sy = rparent
          then
          begin
            InSymbol ;
            Test1(fsys +[semicolon],6);
          end
          else
            Error(4);
          test := sy <> semicolon ;
          if not test
          then
          begin
            displ := minsize ;
            InSymbol;
          end
        until test ;
        displ := maxsize ;
      end; (* case symbol *)
    end ;(* fieldlist *)

  begin(* Typ *)
  (* syntax diagram parsed:
             ------------
------------! simpletype !-------------->------------------------------>-
   !         ------------                                             !
   v                                                                  ^
   !                     ---                        ------------      !
   !--------------------( ^ )----------->----------! type-ident !->---!
   !                     ---                        ------------      !
   v  --->------                  ------<-------                      ^
   ! !          !                !              !                     !
   ! !  ------  !  -----    ---  !  ----------  !  ---    --    ----  !
   !---(packed)---(array)--( [ )---!simpletype!---( ] )--(of)--!type!-!
   !    ------     -----    ---     ----------     ---    --    ----  !
   v                                                                  ^
   !              ------           ------------                       !
   !-------------(record)---------! field-list !--------->------------!
   !              ------           ------------                       !
   v                                                                  ^
   !              ------           ------------                       !
    -------------( set  )---------! simpletype !--------->------------
                  ------           ------------                         *)
    Test2(typebegsys , 10, fsys);
    lsize := 0 ;
    lcp := nil ;
    lmin := 0 ;
    lmax := 0 ;
    if not(sy in typebegsys)
    then
      fsp := nil
    else
    begin
      if sy in simptypebegsys
      then
        simpletype(fsys, fsp, fsize)
      else if sy = arrow
      then
      begin
        (* pointer *)
        new(lsp);
        fsp := lsp ;
        lsp^.stype := nil ;
        lsp^.size  := ptrsize ;
        lsp^.form  := pointer ;
        InSymbol ;
        if sy <> ident
        then
          Error(2)
        else
        begin
          (* suppress error message *)
          prterr := false ;
          Searchid([types], lcp);
          prterr := true ;
          if lcp = nil
          then
            (* forward referenced type id *)
          begin
            new(lcp);
            lcp^.name := id ;
            lcp^.idtype := lsp ;
            lcp^.next := fwptr ;
            lcp^.klass := types ;
            fwptr := lcp;
          end
          else
            lsp^.stype := lcp^.idtype ;
          InSymbol ;
        end ;
      end
      else
      begin
        if sy = packedsy
        then
        begin
          (* skip packed symbol *)
          InSymbol ;
          Test2(typedels, 10, fsys);
        end ;
        case sy of
          arraysy :        (* array *)
          begin
            InSymbol ;
            (* '[' expected next *)
            Intest(lbrack, 11);
            lsp1 := nil ;
            repeat
              new(lsp);
              lsp^.stype := lsp1 ;
              lsp^.indextype := nil ;
              lsp^.form := arrays ;
              lsp1 := lsp ;
              simpletype(fsys +[comma,rbrack,ofsy],
                lsp2 , lsize);
              lsp1^.size := lsize ;
              if lsp2 <> nil
              then
                if lsp2^.form <= subrange
                then
                begin
                  if lsp2 = intptr
                  then
                  begin
                                         (* indextype must not
                                             be integer *)
                    Error(149);
                    lsp2 := nil;
                  end ;
                  lsp^.indextype := lsp2;
                end
                else
                begin
                                   (* indextype must be scalar
                                       or subrange *)
                  Error(113);
                  lsp2 := nil;
                end ;
              test := sy <> comma ;
              if not test
              then
                InSymbol
            until test ;
            (* next '] of ' expected *)
            Intest(rbrack, 12);
            Intest(ofsy, 8);
            Typ(fsys, lsp, lsize);
            (* calculate length of array *)
            repeat
              lsp2 := lsp1^.stype ;
              lsp1^.stype := lsp ;
              if lsp1^.indextype <> nil
              then
              begin
                GetBounds(lsp1^.indextype,
                  lmin, lmax);
                lsize := lsize *(lmax - lmin + 1);
                lsp1^.size := lsize;
              end ;
              lsp := lsp1 ;
              lsp1 := lsp2
            until lsp1 = nil;
          end ;
          recordsy :       (* record *)
          begin
            InSymbol ;
            oldtop := top ;
            if top < displimit
            then
            begin
              top := top + 1 ;
              display[top] := nil;
            end
            else
              Error(172);(* too many nested *)
            (* get all fields of record as tree *)
            displ := 0 ;
            fieldlist(fsys -[semicolon] +[endsy]);
            new(lsp);
            lsp^.fstfld := display[top] ;
            lsp^.size := displ ;
            lsp^.form := records ;
            top := oldtop ;
            Intest(endsy, 13);
          end ;
          setsy :          (* set *)
          begin
            InSymbol ;
            (* set of *)
            Intest(ofsy, 8);
            simpletype(fsys, lsp1, lsize);
            if lsp1 <> nil
            then
              if lsp1^.form > subrange
              then
              begin
                (* base-type scalar or subrange *)
                Error(115);
                lsp1 := nil ;
              end
              else
                (* check set limits *)
                GetBounds(lsp1, lmin, lmax);
            if (lmin < 0)or
              (lmax > setmax)
            then
              error(169);
            new(lsp);
            lsp^.stype := lsp1 ;
            lsp^.size := setsize ;
            lsp^.form := power;
          end
        end ;(* case *)
        (* return description *)
        fsp := lsp; (* XXX *)
      end ;
      Test1(fsys, 6);
    end ;
    if fsp = nil
    then
      fsize := 1
    else
      fsize := fsp^.size;
  end ;(* Typ *)

  procedure ConstDeclaration ;
  (* compiles constant declaration part.
      Syntax diagram checked(reserved keyword CONST already parsed):

            --------------------<---------------------------------
           !                                                      !
           v                                                      ^
           !  -------          ---      ----------         ---    !
CONST --->---! ident !--------( = )----! constant !--->---( ; )-->
              -------          ---      ----------         ---     *)
  var
    lcp : identptr;
    lsp : structptr ;
    lvalu : valu ;
  begin
    lcp := nil ;
    lsp := nil ;
    Test2([ident],2, fsys);
    while sy = ident  do
    begin
      new(lcp);
      lcp^.name := id ;
      lcp^.idtype := nil ;
      lcp^.next := nil ;
      lcp^.klass := konst ;
      InSymbol ;
      if(sy = relop)and(op = eqop)
      then
        InSymbol
      else
        Error(16);
      lvalu.ival := 0 ;
      Constant(fsys +[semicolon], lsp, lvalu);
      Enterid(lcp);
      lcp^.idtype := lsp ;
      lcp^.values := lvalu ;
      if sy = semicolon
      then
      begin
        InSymbol ;
        Test1(fsys +[ident], 6);
      end
      else
        Error(14);
    end;
  end ;(* ConstDeclaration *)

  procedure TypeDeclaration ;
  (* compiles type-declaration
      Syntax-diagram checked(reserved keyword type already parsed):

          ------------------------<-----------------------------
         v                                                      ^
         !    -------          ---      ------------      ---   !
  type ------! ident !--------( = )----! type-ident !----( ; )-->
          !   -------        ! ---      ------------      ---
          ^                  v
          !  -----    ---    !
           -!ident!--( , )---
             -----    ---                                      *)
  var
    lcp , lcp1, lcp2 : identptr;
    lsp : structptr ;
    lsize : addrrange ;
  begin
    lcp := nil ;
    lcp1 := nil ;
    lcp2 := nil ;
    lsp := nil ;

    Test2([ident], 2 , fsys);
    while sy = ident do
    begin
      new(lcp);
      lcp^.name := id ;
      lcp^.idtype := nil ;
      lcp^.klass := types ;
      InSymbol ;
      if(sy = relop)and(op = eqop)
      then
        InSymbol
      else
        Error(16);
      lsize := 0 ;
      Typ(fsys +[semicolon], lsp, lsize);
      Enterid(lcp);
      lcp^.idtype := lsp ;
      (* Has any forward reference been satisfied *)
      lcp1 := fwptr ;
      while lcp1 <> nil do
      begin
        if lcp1^.name = lcp^.name
        then
        begin
          lcp1^.idtype^.stype := lcp^.idtype ;
          if lcp1 <> fwptr
          then
            lcp2^.next := lcp1^.next
          else
            fwptr := lcp1^.next;
        end ;
        lcp2 := lcp1 ;
        lcp1 := lcp1^.next;
      end ;
      if sy = semicolon
      then
      begin
        InSymbol ;
        Test1(fsys +[ident], 6);
      end
      else
        Error(14);
    end ;(* while *)
    if fwptr <> nil
    then
    begin
      Error(117);
      writeln(errorfile^) ;
      repeat
        writeln(errorfile^,' type-id ', fwptr^.name);
        fwptr := fwptr^.next
      until fwptr = nil ;
    end;
  end ;(* TypeDeclaration *)

  procedure VarDeclaration ;
  (* compiles type-declaration
      Syntax-diagram checked(reserved keyword var already parsed):

          ------------------------<----------------------------
         v                                                     ^
         !   -------           ---      ------------   ---     !
  var ------! ident !---------(:)----! type-ident !----(;)--->-
          !  -------        !  ---      ------------      ---
          ^                 v
          !  -----    ---   !
           -!ident!-- (,) --
             -----    ---                                      *)
  var
    lcp, nxt : identptr;
    lsp : structptr ;
    lsize : addrrange ;
  begin
    lcp := nil ;
    lsp := nil ;
    nxt := nil ;
    repeat
      repeat
        if sy = ident
        then
        begin
          new(lcp);
          lcp^.name := id ;
          lcp^.next := nxt ;
          lcp^.klass := vars ;
          lcp^.idtype := nil ;
          lcp^.vkind := actual ;
          lcp^.vlev := level ;
          Enterid(lcp);
          nxt := lcp ;
          InSymbol;
        end
        else
          Error(2);
        Test2(fsys + typedels +[comma,colon],6,[semicolon]);
        test := sy <> comma ;
        if not test
        then
          InSymbol ;
      until test ;
      Intest(colon , 5);
      lsize := 0 ;
      Typ(fsys +[semicolon] + typedels, lsp, lsize);
      while nxt <> nil do
      begin
        nxt^.idtype := lsp ;
        if (lsp <> nil)
        then
        begin
          lc := lc + lsize ;
          nxt^.vaddr := lc ;
        end ;
        nxt := nxt^.next;
      end ;
      if sy = semicolon
      then
      begin
        InSymbol ;
        Test1(fsys +[ident], 6);
      end
      else
        Error(14)
    until(sy <> ident)and(not(sy in typedels));
    if fwptr <> nil
    then
    begin
      Error(118);
      writeln(errorfile^) ;
      repeat
        writeln(errorfile^, 'type-id ', fwptr^.name);
        fwptr := fwptr^.next ;
      until fwptr = nil ;
    end;
  end ;(* varDECLARATION *)

  procedure ProcDeclaration(fsy : symbol);
  var
    oldlev : 0 .. maxlevel ;
    {     lsy : symbol ;  }
    lcp, lcp1 : identptr;
    lsp : structptr ;
    forw : boolean ;
    oldtop : disprange ;
    llc,lcm : addrrange ;
    markp : ^char ;       (* used for mark/release *)   

    procedure ParameterList(fsy  : setofsys ; var fpar : identptr);
   (* compiles parameter-list in a procedure or function
       declaration.
       All variables found are entered in the symbol-tree
       and the nxt^-field is used to link them together. *)
    var
      lcp, lcp1, lcp2, lcp3  : identptr;
      lsp : structptr ;
      lkind : idkind ;
      llc, len : addrrange ;
      count, offset : integer ;
    begin
      lcp1 := nil ;
      Test1(fsy +[lparent], 7);
      if sy <> lparent
      then
        fpar := nil
      else
      begin
        if forw
        then
          Error(119);
        InSymbol ;
        if(not(sy in[ident, varsy]))
        then
        begin
          Error(7);
          Skip(fsys +[ident, rparent]);
        end ;
        while sy in[ident, varsy] do
        begin
          if sy = varsy
          then
          begin
            lkind := formal ;
            InSymbol;
          end
          else
            lkind := actual ;
          lcp2 := nil ;
          count := 0 ;
                (* enter variables in paramterlist in symbol-tree
                    and link var of same type with lcp.next *)
          repeat
            if sy = ident
            then
            begin
              new(lcp);
              lcp^.name := id ;
              lcp^.idtype := nil ;
              lcp^.klass := vars ;
              lcp^.vkind := lkind ;
              (* link var of same type *)
              lcp^.next := lcp2 ;
              lcp^.vlev := level ;
              Enterid(lcp);
              lcp2 := lcp ;
              count := count + 1 ;
              InSymbol;
            end ;
            if not(sy in[comma,colon] + fsys)
            then
            begin
              Error(7);
              Skip(fsys +[comma, semicolon, rparent]);
            end ;
            test := sy <> comma ;
            if not test
            then
              InSymbol
          until test ;
          if sy = colon
          then
          begin
            InSymbol ;
            if sy = ident
            then
            begin
              Searchid([types],lcp);
              lsp := lcp^.idtype ;
              lcp3 := lcp2 ;
              offset := 0 ;
              len := ptrsize ;
              if(lkind = actual)and
                (lsp^.form < arrays)
              then
                if lsp^.size = 1
                then
                  offset := 0
                else
                  len := lsp^.size ;
              lc :=lc + count * len ;
              llc := lc ;
              while lcp2 <> nil do
              begin
                lcp := lcp2 ;
                lcp2^.idtype := lsp ;
                lcp2^.vaddr := llc - offset ;
                llc := llc- len ;
                lcp2 := lcp2^.next;
              end ;
              lcp^.next := lcp1 ;
              lcp1 := lcp3 ;
              InSymbol;
            end
            else
              Error(2);
            Test1(fsys +[semicolon,rparent] , 7);
          end
          else
            Error(5);
          if sy = semicolon
          then
          begin
            InSymbol ;
            if not(sy in[ident,varsy])
            then
            begin
              Error(7);
              Skip(fsys +[ident, rparent]);
            end;
          end;

        end ;(* while *)
        if sy = rparent
        then
        begin
          InSymbol ;
          Test1(fsy + fsys , 6);
        end
        else
          Error(4);
        lcp3 := nil ;
            (* Reverse pointers and reserve local cells
                for copies of multiple values  *)
        while lcp1 <> nil do
        begin
          lcp2 := lcp1^.next ;
          lcp1^.next := lcp3 ;
          if lcp1^.klass = vars
          then
            if lcp1^.idtype <> nil
            then
              if(lcp1^.vkind = actual)and
                (lcp1^.idtype^.form > power)
              then
              begin
                lc := lc + lcp1^.idtype^.size ;
                lcp1^.vaddr := lc;
              end ;
          lcp3 := lcp1 ;
          lcp1 := lcp2;
        end ;(* while *)
        fpar := lcp3;
      end  ;
    end ;(* ParameterList *)

  begin(* ProcDeclaration *)
    (* Procedure to compile a procedure or a function
        declaration.
        Note that symbols procsy or funcsy already parsed.
        Entered with current symbol is proc/func identifier.
        Syntax diagram parsed :

    --------    -------    -    ----------     -
->-!funct-id!--!parlist!--(:)--!type-ident!---(;)------
   --------    -------    -    ----------     -  ^    !
                                                 !    v
   --------    -------     -                     !    !
->-!proc-id !--!parlist!--(;)--------------------     !
   --------    -------    -                           !
                                                      !
  -----------------------<----------------------------
 !
 v
 !        -------             -
  --->---! block !-----------(;)------>----------->-
 !        -------             -           !
 v                                        ^
 !        ---------                       !
  --->---(forward)------------------>---
 !        ---------                       !
 v                                        ^
 !        --------  -     --------        !
  --->---(extern)--(=)-- ! number !-->---
          --------  -     --------                  *)
    llc := lc ;
    lcp := nil ;
    lc := lcaftermarkstack ;
    if sy <> ident
    then
      (* identifier of proc/func expected *)
      Error(2)
    else
    begin
           (* Decide if forward by searching for proc/func
              identifier in symboltable at current level.
              If not found there it can not be forward *)
      lcp := nil ;
      SearchSection(display[top] , lcp);
      if lcp <> nil
      then
      begin
        if lcp^.klass = proc
        then
          forw :=(lcp^.forwdecl)and(fsy = procsy)
        else if lcp^.klass = func
        then
          forw :=(lcp^.forwdecl)and(fsy = funcsy)
        else
          forw := false ;
        if not forw
        then
          Error(160);
        (* previous declaration was not forward *)
      end
      else
        forw := false ;
      if not forw
      then
        (* new procedure or function description *)
      begin
        new(lcp);
        lcp^.name := id ;
        lcp^.idtype := nil ;
        lcp^.pflev := level ;
        lcp^.pfname := nproc ;
        nproc := nproc + 1 ;
        lcp^.externl := false ;
        lcp^.pfdeckind := declared ;
        if fsy = procsy
        then
          lcp^.klass := proc
        else
          lcp^.klass := func ;
        (* enter description at current level *)
        Enterid(lcp);
      end
      else
      begin
                (* description of proc/func already present
                    including fieldlist as linked list pointed
                    at by next^ in forward declaration     *)

        (* walk through linked list for space to reserve *)
        lcp1 := lcp^.next ;
        while lcp1 <> nil do
        begin
          if lcp1^.klass = vars
          then
            if lcp1^.idtype <> nil
            then
            begin
              lcm := lcp1^.vaddr ;
              if lcm > lc
              then
                lc := lcm;
            end ;
          (* next field in linked list *)
          lcp1 := lcp1^.next;
        end ;
      end ;
      InSymbol;
    end ;(* symbol is ident *)
    (* remember current level *)
    oldlev := level ;
    oldtop := top ;
    if level < maxlevel
    then
      level := level + 1
    else
      Error(173);
    (* remember current display *)
    if top < displimit
    then
    begin
      top := top + 1 ;
      savetop := top ;
      if forw
      then
        (* already fieldlist present in tree *)
        display[top] := lcp^.next
      else
        (* create empty tree *)
        display[top] := nil;
    end
    else
      Error(172);
    if fsy = procsy
    then
    begin
      ParameterList([semicolon], lcp1);
      if not forw
      then
        (* link linked list to proc description *)
        lcp^.next := lcp1;
    end
    else
      (* function *)
    begin
      ParameterList([semicolon,colon],lcp1);
      if not forw
      then
        (* link linked list to func description *)
        lcp^.next := lcp1 ;
      if sy <> colon
      then
      begin
        if not forw
        then
          (* colon expected with function-type*)
          Error(123);
      end
      else
      begin
        (* determine type of function-result *)
        InSymbol ;
        if sy <> ident
        then
        begin
          (* identifier expected *)
          Error(2);
          Skip(fsys +[semicolon]);
        end
        else
        begin
          if forw
          then
            (* function-type again declared *)
            Error(122);
          Searchid([types],lcp1);
          lsp := lcp1^.idtype ;
          lcp^.idtype := lsp ;
          if lsp <> nil
          then
            if lsp^.form >= power
            then
            begin
              (* function-type must be simple *)
              Error(120);
              lcp^.idtype := nil;
            end ;
          InSymbol;
        end;
      end;
    end ;
    Intest(semicolon , 14);
    if sy = forwardsy
    then
    begin
      if forw
      then
        Error(161)
      else
        lcp^.forwdecl := true ;
      InSymbol ;
      Intest(semicolon, 14);
      Test1(fsys, 6);
    end
    else if sy = externsy
    then
    begin
      if forw
      then Error(161);
      InSymbol ;
      lcp^.externl := true ;
      if(sy = relop)and(op = eqop)
      then
      begin
        InSymbol ;
        if sy = intconst
        then
          lcp^.pfname := val.ival
        else
          Error(106);
      end
      else
        Error(51);
      repeat
        InSymbol
      until sy = semicolon ;
      InSymbol ;
      Test1(fsys, 6);
    end
    else
      (* block *)
    begin
      lcp^.forwdecl := false ;
      (* remember heap with markpointer for release *)
      new(markp);
      repeat
        Block(fsys, semicolon ,lcp);
        if sy <> semicolon
        then
          Error(14)
        else
        begin
          InSymbol ;
          if not(sy in[beginsy, procsy, funcsy])
          then
          begin
            Error(6);
            Skip(fsys);
          end;
        end ;
      until sy in[beginsy, procsy, funcsy] ;
      (* release heap from markpointer *)
      release(markp);
    end ;
    (* restore to old level and display *)
    level := oldlev ;
    top := oldtop ;
    lc := llc;
  end ;(* ProcDeclaration *)

  procedure Body(fsys : setofsys);
  var
    i, entname, segsize : integer ;
    lcmax, llc1 : addrrange ;
    lcp : identptr;

    procedure LDCIgen(value : integer);
      (* Generate instructions to load constant
          16 bit value on stack *)
    begin
      if(value < 16)and(value >= 0)
      then
        ByteGen(value)
      else if value < 0
      then
      begin
        ByteGen(176);              (* LNC *)
        WordGen(-value);
      end
      else
      begin
        ByteGen(160);                (* LDC *)
        WordGen(value);
      end;
    end ;(* LDCIgen *)

    procedure LDAgen (thislevel, varlevel : integer ; dplmt : addrrange);
    (* generate instructions to load offset address dplmt
        for level on stack, optimize if short range *)
    var
      level: integer;

    begin
      if varlevel = -1 then
        LDCIgen(dplmt)
      else
      begin
        level := thislevel - varlevel;
        if dplmt < 256
        then                          (* ldas *)
        begin
          ByteGen(16 + level);
          ByteGen(dplmt);
        end
        else                          (* lda  *)
        begin
          ByteGen(32 + level);
          WordGen(dplmt);
        end;
      end;
    end ;(* LDAgen *)

    procedure LODgen(thislevel, varlevel : integer ; var fattr : attr);
    (* load variable value on stack of level *)
    begin
      (* short range and small variable *)
      if (fattr.typtr^.size <= 2) and (fattr.dplmt < 256)
      then
      begin
        (* LOD1, LOD2 or LOD8 byte instructions *)
        ByteGen(64 + 16 * fattr.typtr^.size + thislevel - varlevel);
        ByteGen(fattr.dplmt);
      end
      else
      begin
        (* put address on stack of data item from level *)
        LDAgen(thislevel, varlevel, fattr.dplmt);
        (* Indirectly load data on stack *)
        case fattr.typtr^.size of
          1 : ByteGen(154); (* IND1 *)
          2 : ByteGen(155); (* IND2 *)
          3 : ByteGen(156)  (* IND8 *)
        end;
      end;
    end ;(* LODgen *)

    procedure Condgen(fop : oprange ; var fattr : attr);
    (* generate conditional opererators,
        called with operators for 2-byte items,
        for other items calculate operator-code *)
    begin
      if fattr.typtr^.form > power
      then
      begin
        (* arrays and records *)
        (* LEQ2(= $90)to LEQM(= $92)*)
        (* LES2(= $93)to LESM(= $95)*)
        (* EQU2(= $96)to EQUM(= $98)*)
        ByteGen(fop + 2);
        WordGen(fattr.typtr^.size);
      end
      else if fattr.typtr^.size = 1
      then
        (* correct to 16 bit *)
        (* LEQ2(= $90)*)
        (* LES2(= $93)*)
        (* EQU2(= $96)*)
        ByteGen(fop)
      else if fattr.typtr^.size = 2
      then
        (* LEQ2(= $90)*)
        (* LES2(= $93)*)
        (* EQU2(= $96)*)
        ByteGen(fop)
      else if fattr.typtr^.size = 8
      then
        (* sets, only equal operatortype *)
        (* EQU2(= $96)to EQUM(= $99)*)
        ByteGen(fop + 3)
      else
        Error(179);         (* wrong size *)
    end ;(* Condgen *)

    procedure LoadSetConstant(setconst : intset);
    (* generate instruction to
        load constant set setconst on stack *)
    var
      i, k, l , n : integer ;
      b : boolean ;
    begin
      n := 0 ;
      b := false ;
      for i := 0 to setmax do
        if i in setconst
        then
          n := n + 1 ;
      if n = 0
      then
        ByteGen(193)          (* Load empty set lns *)
      else if n < 4
      then
      begin
        for i := 0 to setmax do
          if i in setconst
          then
          begin
            LDCIgen(i);
            ByteGen(174);     (* sgs *)
            if b
            then
              ByteGen(175); (* uni *)
            b := true;
          end;
      end
      else        (* n >= 4 *)
      begin
        ByteGen(186);               (* LDCS *)
        l := 0 ;
        k := 128 ;
        for i := 0 to setmax do
        begin
          if k < 1
          then
          begin
            k := 128 ;
            ByteGen(l);
            l := 0;
          end ;
          if i in setconst
          then
            l := l + k ;
          (* shift *)
          k := k div 2;
        end ;
        ByteGen(l);
      end;
    end ;(* LoadSetConstant *)

    procedure CSPgen(stpr : integer);
    (* generate instruction to call standard procedure stpr *)
    begin
      ByteGen(189 );
      ByteGen(stpr);
    end ;(* CSPgen *)

    procedure INCgen(inc : integer);
    (* Generate instructions to increment or
        decrement integer on stack with inc *)
    begin
      if inc <> 0
      then
        if inc = 1
        then
          ByteGen(185)               (* inc1 *)
        else if inc = -1
        then
          ByteGen(184)               (* dec1 *)
        else
        if inc > 0
        then
        begin
          ByteGen(180);          (* inc *)
          WordGen(inc);
        end
        else
        begin
          ByteGen(179);          (* dec *)
          WordGen(- inc);
        end;
    end ;(* INCgen *)

    procedure Load ;
    (* generate instruction to load data on stack *)
    begin
      if gattr.typtr <>  nil
      then
      begin
        (* constant *)
        if gattr.kind = cst
        then
        begin
          if(gattr.typtr^.form = scalar)
          then
            (* load constant on stack *)
            LDCIgen(gattr.cval.ival)
          else if gattr.typtr = nilptr
          then
            (* load zero on stack *)
            ByteGen(0)
          else
            (* load constant set on stack *)
            LoadSetConstant(gattr.cval.valp^.pval);
        end
        else if gattr.kind = varbl
        then
          if gattr.access = drct
          then
            LODgen(level, gattr.level,gattr)
          else
          begin
            (* put address of data item on stack *)
            INCgen(gattr.dplmt);
            (* Indirectly load data item on stack *)
            case gattr.typtr^.size of
              1 : ByteGen(154);   (* IND1 *)
              2 : ByteGen(155);   (* IND2 *)
              8 : ByteGen(156);   (* IND8 *)
            end;
          end ;
        gattr.kind := expr;
      end;
    end ;(* Load *)

    procedure Store(var fattr : attr);
    (* generate instruction to store data item in memory *)
    begin
      if fattr.typtr <> nil
      then
        if fattr.access = drct
        then
        begin
          (* STR1 or LOD2 *)
          ByteGen(96 + 16 * fattr.typtr^.size
            + level - fattr.level);
          ByteGen(fattr.dplmt);
        end
        else
        if fattr.dplmt <> 0
        then
          Error(178)
        else
        begin
          if fattr.typtr^.form = files then
            Error(178);
          case fattr.typtr^.size of
            1 : ByteGen(157);         (* Sto1 *)
            2 : ByteGen(158);         (* Sto2 *)
            8 : ByteGen(159);         (* Sto8 *)
          end;
        end;
    end ;(* Store *)

    procedure LoadAddress ;
    (* Generate instructions to load address of variable
        or constant on stack *)
    var
      lvp : constptr ;
      i : integer ;
    begin
      if gattr.typtr <> nil
      then
      begin
        if gattr.kind = cst
        then
          if IsString(gattr.typtr)
          then
          begin
            (* Put address of string on stack *)
            ByteGen(188);        (* LCA *)
            ByteGen(StringSize(gattr.cval.valp));
            lvp := gattr.cval.valp ;
            (* Put string following opcode *)
            while lvp <> nil do
            begin
              for i := 1 to lvp^.slgth do
                ByteGen(lvp^.sval[i]);
              (* walk through linked list of string parts *)
              lvp := lvp^.sptr;
            end;
          end
          else
            Error(178)
        else
        if gattr.kind = varbl
        then
          if gattr.access = drct
          then
            LDAgen(level, gattr.level, gattr.dplmt)
          else
            INCgen(gattr.dplmt)
        else
          Error(178);
        gattr.kind := varbl ;
        (* address on stack, so mark as indirect *)
        gattr.access := indrct ;
        gattr.dplmt := 0;
      end;
    end ;(* LoadAddress *)

    procedure FalseJumpGen (faddr : integer);
    (* Generate instruction jump conditional
        if false value on stack jump to faddr *)
    begin
      Load ;
      if gattr.typtr <> nil
      then
        if gattr.typtr <> boolptr
        then
          (* must have boolean result on stack *)
          Error(144);
      ByteGen(177)  ;          (* FJP *)
      WordGen(faddr);
    end ;(* FalseJumpGen *)

    procedure CallUserProcGen(fp1, fp2 : integer);
    (* Generate call to user procedure *)
    begin
      (* proc/func in parameter list ? *)
      if pfcttest
      then
      begin
        ByteGen(fp1);
        ByteGen(191);       (* CUP2 *)
      end
      else
        ByteGen(190);        (* CUP1 *)
      ByteGen(fp2);
    end ;(* CallUserProcGen *)

    procedure Statement(fsys : setofsys);
    var lcp : identptr;

      procedure Expression(fsys : setofsys); forward ;

      procedure Selector(fsys : setofsys ; fcp : identptr);
        (* deals with complex identifiers such as pointers,
           fields of records and indexes in arrays and
           combinations, result returned in gattr         *)
        (* structures parsed , first identifier already parsed :
                                   ---
                     -------------( ^ )-------------------
                    !              ---                    !
                    ^                                     !
     ------------   !   ---     ------------     ---      v
->---! identifier !--!--(()---! expression !---( ) )------>
  ^  ------------   !   ---  ^  ------------  !  ---   ^  !
  !                 !        !                !        !  v
  !                 v         -------<--------         !  !
  !                 !                                  !  !
  !                 !               ---                !  !
  !                  --------------( . )---------------   !
  !                                 ---                   !
  !                                                       !
   ----------------------------------<--------------------   *)
      var
        lattr : attr ;
        lcp : identptr;
        lmin, lmax : integer ;
      begin
        lmin := 0 ;
        lmax := 0 ;
        lcp := nil ;
        gattr.typtr := fcp^.idtype ;
        gattr.kind := varbl ;
        if fcp^.klass = vars
        then
        begin
          (* decide if direct or indirect access *)
          if gattr.typtr <> nil
          then
            if(fcp^.vkind = actual)and
              (fcp^.vaddr < 256)and
              (gattr.typtr^.size <= 2)
            then
            begin
              gattr.access := drct ;
              gattr.level := fcp^.vlev ;
              gattr.dplmt := fcp^.vaddr;
            end
            else
            begin
              gattr.access := indrct ;
              gattr.dplmt := 0 ;
              if fcp^.vkind = formal
              then
              begin
                if (fcp^.vlev = -1) then
                  Error(178);
                ByteGen($60 + level - fcp^.vlev);
                ByteGen(fcp^.vaddr);
              end
              else
                LDAgen(level, fcp^.vlev, fcp^.vaddr);
            end;
        end
        else if fcp^.klass = func
        then
          if fcp^.pfdeckind = standard
          then
            (* assignment to standard function not allowed *)
            Error(150)
          else
          begin
            (* Implied relative address of function result *)
            gattr.access := drct ;
            gattr.level := fcp^.pflev + 1 ;
            gattr.dplmt := 0;
          end ;
        (* test if not error in variable, must be '^', '(' or '.' *)
        Test1(selectsys + fsys, 59);
        while sy in selectsys do
        begin
          if sy = lbrack
          then
          begin
            (* array element *)
            repeat
              (* all indexes separated by comma's *)
              lattr := gattr ;
              (* save expression result *)
              if lattr.typtr <> nil
              then
                if lattr.typtr^.form <> arrays
                then
                begin
                  (* type of variable is not array *)
                  Error(138);
                  lattr.typtr := nil;
                end ;
              (* complex structure, remember address *)
              LoadAddress ;
              InSymbol ;
              (* index is expression followed by ',' or ']' *)
              Expression(fsys +[comma, rbrack]);
              if gattr.kind <> cst
              then
                Load ;
              if gattr.typtr <> nil
              then
                if gattr.typtr^.form > subrange
                then
                  (* indextype must be scalar or subrange *)
                  Error(113);
              if lattr.typtr <> nil
              then
              begin
                (* check if index same type as arrayindex *)
                if CompTypes(lattr.typtr^.indextype,
                  gattr.typtr)
                then
                begin
                  if lattr.typtr^.indextype <> nil
                  then
                  begin
                    GetBounds(
                      lattr.typtr^.indextype,
                      lmin, lmax);
                    if gattr.kind = cst
                    then
                    begin
                                            (* check bounds if
                                                constant *)
                      if
                      (gattr.cval.ival < lmin)
                        or
                        (gattr.cval.ival > lmax)
                      then
                        Error(174);
                      gattr.cval.ival :=
                        gattr.cval.ival - lmin;
                    end
                    else
                      INCgen(-lmin);
                                          (* decrement offset with
                                              lmin for actual offset *)
                  end;
                end
                else
                  Error(139);
                gattr.typtr := lattr.typtr^.stype ;
                if gattr.typtr <> nil
                then
                  if gattr.kind = cst
                  then
                  begin
                    gattr.cval.ival :=
                      gattr.cval.ival *
                      gattr.typtr^.size ;
                    LDCIgen(gattr.cval.ival);
                  end
                  else
                  if gattr.typtr^.size <> 1
                  then
                  begin
                    LDCIgen(gattr.typtr^.size);
                    ByteGen(170); (* mpi *)
                  end ;
                ByteGen(162);   (* adi *)
                gattr.kind := varbl ;
                gattr.access := indrct ;
                gattr.dplmt := 0;
              end
            until sy <> comma ;
            (* index-list ends with ']' *)
            Intest(rbrack, 12);
          end  (* array-index *)
          else if sy = period
          then
            (* record-field *)
          begin
            if gattr.typtr <> nil
            then
              if gattr.typtr^.form <> records
              then
              begin
                (* not a record *)
                Error(140);
                gattr.typtr := nil;
              end ;
            InSymbol ;
            if sy <> ident
            then
              Error(2)
            else
            begin
              if gattr.typtr <> nil
              then
              begin
                (* check if known field in record *)
                SearchSection(gattr.typtr^.fstfld,lcp);
                if lcp = nil
                then
                begin
                  Error(152);
                  gattr.typtr := nil;
                end
                else
                begin
                  gattr.typtr := lcp^.idtype ;
                  if gattr.access = indrct
                  then
                    gattr.dplmt :=
                      gattr.dplmt + lcp^.vaddr
                  else
                    gattr.dplmt :=
                      gattr.dplmt - lcp^.vaddr;

                end;
              end ;
              InSymbol;
            end;
          end  (* sy = period . *)
          else
            (* must be ^ of pointer *)
          begin
            if gattr.typtr <> nil
            then
              if gattr.typtr^.form = pointer
              then
              begin
                Load ;
                gattr.typtr := gattr.typtr^.stype ;
                gattr.kind := varbl ;
                gattr.access := indrct ;
                gattr.dplmt := 0;
              end
              else
                Error(141);
            InSymbol;
          end ;  (* sy = arrow ^ *)
          Test1(fsys + selectsys, 6);

        end ;(* while *)

      end ;(* Selector *)

      procedure Call(fsys : setofsys ; fcp : identptr);
      var
        lkey : 1 .. maxstandrd  ;

        procedure Variable(fsys : setofsys);
      (* Search if known variable at current or lower level,
          return complete description by calling selector *)
        var
          lcp : identptr;
        begin
          lcp := nil ;
          if sy = ident
          then
          begin
            (* Look in symbol-tree *)
            Searchid([vars], lcp);
            InSymbol;
          end
          else
          begin
            Error(2);
            (* return unknown variable pointer *)
            lcp := uvarptr;
          end ;
          (* get complete description *)
          Selector(fsys, lcp);
        end ;(* Variable *)

        procedure ReadProc ;
      (* Generate code for standard procedure Read and Readln

          Parsed structure, readln or read already parsed in lkey :

             ----
           -(ln)------------------->-------------------------
          ^  ----  !                                           !
          !        !            ------->----------             !
          !        !           ^                  !            !
          !        v     ---   !  ------------    v            !
read -->----------------( ( )----( file-ident )------          !
                         ---      ------------       !         !
                                                     v         v
         -----------------<------------------------------>-----!
        v                                                      !
        !                     --------------------        ---  v
         --------------------! character-variable !------( ) )---->--
                       !  !   --------------------   ! !  ---
                       ^  v                          ^ v
                       !  !   --------------------   ! !
                       !   --! integer-variable   !--  !
                       !      --------------------     !
                       !                               !
                        --------------<----------------          *)
          procedure ProcessTerms;
          var
            test: boolean;

          begin
            repeat
              begin
                if (gattr.kind <> varbl) then
                  Error(154);
                      (* place address of variable
                          on stack for rdc or rdi *)
                LoadAddress ;
                if (gattr.typtr <> nil)
                then
                begin
                  if CompTypes(intptr, gattr.typtr) then
                    CSPgen(3) (* rdi *)
                  else if CompTypes(charptr, gattr.typtr) then
                    CSPgen(5) (* rdc *)
                  else if IsString(gattr.typtr) then
                    CSPgen(4) (* rdn *)
                  else
                    Error(177);
                end
                else
                  (* error in type of standard procedure *)
                  Error(116);

                test := sy = comma;
                if test then
                begin
                  InSymbol;
                  Expression(fsys +[comma, rparent]);
                end;
              end;
            until (not test);
          end;

        begin
          if sy <> lparent
          then
          begin
            (* no parameters, default to input *)
            LDCIGen(1);
            (* Set file address instruction *)
            ByteGen(194);
          end
          else
          begin
            Intest(lparent, 9);
            Expression(fsys + [comma, rparent]);
            if gattr.typtr^.form <> files then
            begin
                  (* The first expression is not a file type, which means it
                  must be something to write out. Default to output. *)
              LDCIGen(2);
              ByteGen(194); (* SFA *)
              ProcessTerms;
            end
            else
            begin
                  (* The first parameter is a file type, which means it's the
                  destination stream. *)
              LoadAddress;
              ByteGen(194); (* SFA *)
              if sy = comma then
              begin
                InSymbol;
                Expression(fsys + [comma, rparent]);
                ProcessTerms;
              end;
            end;
            Intest(rparent, 4);
          end  ;
          if lkey = 5 then
            CSPgen(4);              (* rln *)
        end;

        procedure WriteProc ;
        (* Generate code for standard procedure Write and Writeln *)
      (* Parsed structure, writeln or write already parsed in lkey :
             ----
           -(ln)------------------->------------------------
          ^  ----  !                                          !
          !        !            ------->----------            !
          !        !           ^                  !           !
          !        v     ---   !  ------------    v           !
write-->----------------( ( )----( file-ident )---------->----!
                         ---      ------------       !        !
                                                     v        v
 -------------------------<--------------------------         !
!                                                             !
v                                                             !
!    -----------------                                        !
!->-! string          !---                                    !
!    -----------------    !   -------------->---------        !
!                         v  ^                        !       !
!    -----------------    !  !  ---    -------------  v  ---  v
!->-! char-expression !->------(:)--! int-express !---- -())---->--
!    -----------------    !     ---    -------------     ---
!                         ^
!    -----------------    !
 ->-! int-expression  !---
     -----------------                                            *)
        var
          lsp : structptr ;
          llkey : 1 .. maxstandrd ;

          procedure ProcessTerms;
          var
            default : boolean ;
            len : addrrange ;

          begin
            repeat
              lsp := gattr.typtr ;
              if lsp <> nil
              then
                (* put variable or address of variable on stack *)
                if lsp^.form <= subrange
                then
                  Load
                else
                  LoadAddress ;
              (* if colon then no default, load expression as nr of characters *)
              if sy = colon
              then
              begin
                InSymbol ;
                Expression(fsys +[comma, rparent]);
                if gattr.typtr <> nil
                then
                begin
                  if not Comptypes(gattr.typtr,intptr)
                  then
                    Error(116);
                end
                else
                  Error(116);
                Load ;
                default := false;
              end
              else
                default := true ;
              if Comptypes(lsp, intptr)
              then
              begin
                if default
                then
                  (* default integer in 6 char field *)
                  LDCIgen(6);
                CSPgen(0);        (* wri *)
              end
              else if Comptypes(lsp, charptr)
              then
              begin
                if default
                then
                  (* default character in 1 char field *)
                  LDCIgen(1);
                CSPgen(1);        (* wrc *)
              end
              else if lsp <> nil
              then
                if lsp^.form = scalar
                then
                  Error(177)
                else if IsString(lsp)
                then
                begin
                  len := lsp^.size ;
                  if default
                  then
                    (* default length of string *)
                    LDCIgen(len);
                  LDCIgen(len);
                  CSPgen(2);   (* wrs *)
                end
                else
                  Error(116) ;
              test := sy <> comma ;
              if not test
              then
              begin
                InSymbol;
                Expression(fsys +[comma, colon, rparent]);
              end;
            until test ;
          end;

        begin
          llkey := lkey ;
          if sy <> lparent
          then
          begin
            (* no parameters, default to output *)
            LDCIGen(2);
            (* Set file address instruction *)
            ByteGen(194);
          end
          else
          begin
            InSymbol ;
            Expression(fsys +[comma, colon, rparent]);
            if gattr.typtr <> nil then
              if gattr.typtr^.form <> files then
              begin
                  (* The first expression is not a file type, which means it
                  must be something to write out. Default to output. *)
                LDCIGen(2);
                ByteGen(194); (* SFA *)
                ProcessTerms;
              end
              else
              begin
                  (* The first parameter is a file type, which means it's the
                  destination stream. *)
                LoadAddress;
                ByteGen(194); (* SFA *)
                if sy <> rparent then
                begin
                  InSymbol;
                  Expression(fsys +[comma, colon, rparent]);
                  ProcessTerms;
                end;
              end;
            Intest(rparent, 4);
          end;
          if llkey = 6
          then
            CSPgen(6);                    (* wln *)
        end ;(* WriteProc *)

        procedure NewStatement ;
        (* generate code for stand procedure New, argument of new is pointer *)
        var
          lsize : addrrange ;
        begin
          Variable(fsys +[rparent]);
          (* pointer is address, put on stack *)
          LoadAddress ;
          lsize := 0 ;
          if gattr.typtr <> nil
          then
            if gattr.typtr^.form = pointer
            then
            begin
              if gattr.typtr^.stype <> nil
              then
                lsize := gattr.typtr^.stype^.size;
            end
            else
              Error(116);
          (* load size of space to allocate in heap *)
          LDCIgen(lsize);
          CSPgen(7);                     (* new *)
        end ;(* NewStatement *)

        procedure ReleaseStatement ;
     (* Generate code to release heap,
         release starting from pointer argument given to Release *)
        begin
          Variable(fsys +[rparent]);
          if gattr.typtr <> nil
          then
            if gattr.typtr^.form = pointer
            then
            begin
              Load ;
              CSPgen(9);              (* rst *)
            end
            else
              Error(125);
        end ;(* ReleaseStatement *)

        procedure ResetRewriteProc ;
     (* Compiles Reset and Rewritestandard procedure,
         syntax checked:
                   ---      ------------     ---     -----------------
     rewrite-->---( ( )----! file-ident !---( , )---! string-constant !--->
                   ---      ------------     ---  !  -----------------   !
                                                  !                      ^
                                                  !  -----------------   !
                                                   -! string-var ident!--
                                                     -----------------      *)
        var
          llkey  : integer ;
        begin
          llkey := lkey ;

          Expression(fsys +[comma, colon, rparent]);
          if gattr.typtr^.form <> files then
            Error(22);
          LoadAddress;

          ByteGen(194);                (* SFA *)

          if llkey = 7
          then
            CSPGEN(13)      (* reset file *)
          else
            CSPGEN(14);     (* rewrite file *)
        end ;(* ResetRewriteProc *)

        procedure CloseProc ;
        (* generate code for standard procedure Close *)
        begin
          Expression(fsys +[comma, colon, rparent]);
          if gattr.typtr^.form <> files then
            Error(22);
          LoadAddress;

          ByteGen(194);                (* SFA *)
          CSPGEN(16);                   (* close file *)
        end ;(* CloseProc *)

        procedure AssignProc ;
        (* generate code for standard procedure Assign *)
        begin
          Expression(fsys +[comma]);
          if gattr.typtr^.form <> files then
            Error(22);
          LoadAddress;
          ByteGen(194);                 (* SFA *)

          InSymbol;
          Expression(fsys +[rparent]);
          if (not IsString(gattr.typtr)) then
            Error(177);
          LoadAddress;

          CSPGEN(17);                    (* assign file *)
        end;

        procedure GetCommandLineProc ;
        (* generate code for standard procedure Assign *)
        begin
          Variable(fsys +[rparent]);
          if (not IsString(gattr.typtr)) then
            Error(138);

          CSPgen(18);                    (* get command line *)
        end;

        procedure OrdFunc ;
     (* generate code for standard function Ord
         result is integer *)
        begin
          if gattr.typtr <> nil
          then
            if gattr.typtr^.form >= power
            then
              Error(125) ;
          gattr.typtr := intptr;
        end ;(* OrdFunc *)

        procedure SuccFunc ;
     (* generate code for standard function Succ
         result is same type *)
        begin
          if gattr.typtr <> nil
          then
            if gattr.typtr^.form >= power
            then
              Error(125)
            else
              ByteGen(185);(* inc1 *)
        end ;(* SuccFunc *)

        procedure PredFunc ;
     (* generate code for standard function Pred
         result is same type *)
        begin
          if gattr.typtr <> nil
          then
            if gattr.typtr^.form >= power
            then
              Error(125)
            else
              ByteGen(184);(* dec1 *)
        end ;(* PredFunc *)

        procedure ChrFunc ;
     (* generate code for standard function Chr
         result is character *)
        begin
          if gattr.typtr <> nil
          then
            if gattr.typtr <> intptr
            then
              Error(125);
          gattr.typtr := charptr;
        end ;(* ChrFunc *)

        procedure OddFunc ;
     (* generate code for standard function Odd
         result is boolean *)
        begin
          if gattr.typtr <> nil
          then
            if gattr.typtr <> intptr
            then
              Error(125);
          CSPgen(12);                (* odd *)
          gattr.typtr := boolptr;
        end ;(* OddFunc *)

        procedure EofEolnStatusFunc ;
     (* generate code for standard function Eof, Eoln and Status,
         result is boolean *)
        begin
          (* default to input *)
          if sy = lparent
          then
          begin
            Insymbol ;
            if sy = rparent then
              LDCIGen(1) (* default to input *)
            else
            begin
              Expression(fsys +[rparent]);
              if gattr.typtr^.form <> files then
                Error(22);
              LoadAddress;
              InTest(rparent,4);
            end;
          end ;
          ByteGen(194);                (* SFA *)
          if lkey = 8
          then
          begin
            gattr.typtr := intptr ;
            CSPGEN(15);             (* get file status *)
          end
          else
          begin
            gattr.typtr := boolptr ;
            if lkey = 6
            then
              CSPgen(10)         (* test if end of line *)
            else
              CSPgen(8);         (* test if end of file *)
          end;
        end ;(* EofEolnStatusFunc *)

        procedure Callnonstandard ;
     (* generate to call user-defined procedure or function,
         fcp is pointer to identifier of procedure/function
         Structure parsed :

                  ------------------>--------------------
                 ^                                       !
                 !   ---       ------------       ---    v
proc/func-ident -----(()-----! expression !-----())------>
                     ---   ^   ------------   !
                           !                  v
                            --------<---------                *)
        var
          nxt {, lcp } : identptr;
          lsp : structptr ;
          locpar, llc : addrrange ;
        begin
          (* locpar is space for local parameters *)
          locpar := 0 ;
          (* parameters linked as linked list to fcp with next^ *)
          nxt := fcp^.next ;
          pfcttest := false ;
          if not fcp^.externl
          then
            if fcp^.klass = proc
            then
              (* procedure needs no space for result *)
              ByteGen(48 + level - fcp^.pflev)     (* msto *)
            else
            begin
              (* function has result mark stack with return-bytes MSTN *)
              ByteGen(64 + level - fcp^.pflev);
              ByteGen(fcp^.idtype^.size);       (* ret value *)
            end ;
          (* parse parameter-list *)
          if sy = lparent
          then
          begin
            (* remember location-counter *)
            llc := lc ;
            repeat
              InSymbol ;
              Expression(fsys +[comma, rparent]);
              if gattr.typtr <> nil
              then
                if nxt <> nil
                then
                begin
                  lsp := nxt^.idtype ;
                  if lsp <> nil
                  then
                  begin
                    if(nxt^.vkind = actual)
                    then
                      if lsp^.form < arrays
                      then
                      begin
                        (* reserve room *)
                        Load ;
                        locpar := locpar+lsp^.size;
                      end
                      else
                      begin
                        if(lsp^.form= arrays)and
                          (gattr.kind = cst)
                        then
                          LoadAddress
                        else if(gattr.kind=expr)or
                          (gattr.kind=cst)
                        then
                        begin
                          Load ;
                          LODgen(0, 0, gattr);
                          lc := lc +
                            gattr.typtr^.size ;
                          LDAgen(0, 0, lc);
                          if lcmax < lc
                          then
                            lcmax := lc ;
                        end
                        else
                          LoadAddress ;
                        locpar := locpar + ptrsize;
                      end
                    else
                    (* formal *)
                    if gattr.kind = varbl
                    then
                    begin
                      LoadAddress ;
                      locpar := locpar + ptrsize;
                    end
                    else
                      (* formal can not be variable *)
                      Error(154);
                    if not CompTypes(lsp,gattr.typtr)
                    then
                      (* arg and par not compatible *)
                      Error(142);
                  end;
                end ;
              if nxt <> nil
              then
                (* more parameters expected *)
                nxt := nxt^.next
            until sy <> comma ;
            lc := llc ;
            Intest(rparent, 4);
          end ;(* sy = lparent *)
          if nxt <> nil
          then
            (* more parameters expected than found *)
            Error(126);
          if fcp^.externl
          then
          begin
            (* external procedure/function *)
            LDCIgen(locpar);
            ByteGen(187);               (* cap *)
            WordGen(fcp^.pfname);
          end
          else
            CallUserProcGen(locpar, fcp^.pfname);
          if fcp^.idtype <> nil
          then
            if fcp^.idtype^.size = 1
            then
              (* result fixed to 2 bytes *)
              ByteGen(192);             (* fix21 *)
          pfcttest := true ;
          gattr.typtr := fcp^.idtype;
        end ;(* Callnonstandard *)

      begin(* Call *)
        if fcp^.pfdeckind <> standard
        then
          CallNonStandard
        else
        begin
          (* standard procedure and functions *)
          lkey := fcp^.key ;
          (* lkey is returned by searchid *)
          if fcp^.klass = proc
          then
            (* standard procedures *)
            case lkey of
              1, 5: ReadProc;
              2, 6: WriteProc;
              9: ByteGen(161); (* retp *)
              10: CSPgen(11); (* HALT standard procedure *)
            else
            begin
              (* arguments for procedure required *)
              Intest(lparent, 9);
              case lkey of
                3: NewStatement;
                4: ReleaseStatement;
                7, 8: ResetRewriteProc;
                11: CloseProc;
                13: AssignProc;
                14: GetCommandLineProc;
              else
                Error(178)
              end;
              Intest(rparent, 4);
            end
            end
          else
          (* standard functions *)
          if(lkey < 6)
          then
          begin
            (* arguments for function required *)
            Intest(lparent, 9);
            Expression(fsys +[rparent]);
            Load ;
            case lkey of
              1 : OrdFunc  ;
              2 : ChrFunc  ;
              3 : OddFunc  ;
              4 : SuccFunc ;
              5 : PredFunc
            end ;
            Intest(rparent, 4);
          end
          else if(lkey = 6)or(lkey = 7)or(lkey = 8)
          then
            EofEolnStatusFunc;
        end; (* standard procedure and functions *)
      end ;(* Call *)

      procedure Expression ;
      var
        lattr : attr ;
        lop : operatortype ;

        procedure SimpleExpression(fsys : setofsys);
        var
          lattr : attr ;
          lop : operatortype ;
          signed : boolean ;

          procedure OPgen(var lattr : attr ; opi, opb, ops : integer);
         (* procedure to compile operations.
             opi, opb, ops are the operations to generate
             for operands of type integer, boolean and set
             respectively. An argument will be zero for
             operand/operatortype pairs which are invalid     *)
          var
            test : boolean ;
          begin
            test := false ;
            if CompTypes(lattr.typtr, intptr)and
              CompTypes(gattr.typtr, intptr)
            then
            begin
              if opi <> 0
              then
              begin
                test := true ;
                ByteGen(opi);
              end;
            end
            else if CompTypes(lattr.typtr, boolptr)and
              CompTypes(gattr.typtr, boolptr)
            then
            begin
              if opb <> 0
              then
              begin
                test := true ;
                ByteGen(opb);
              end;
            end
            else if(lattr.typtr^.form = power)and
              CompTypes(lattr.typtr, gattr.typtr)
            then
              if ops <> 0
              then
              begin
                test := true ;
                ByteGen(ops);
              end ;
            if not test
            then
            begin
              Error(134);
              gattr.typtr := nil;
            end;
          end ;(* OPgen *)

          procedure Term(fsys : setofsys);
          var
            lattr : attr ;
            lop : operatortype ;

            procedure Factor(fsys : setofsys);
            var
              lcp : identptr;
              lvp : constptr ;
              varpart : boolean ;
              cstpart : intset ;
              lsp : structptr ;

              procedure SetExpression ;
             (* structure parsed :
            ---                                  ---
     --->--( [ )--------------------------------( ] )----->
            ---  !                            !  ---
                 v        ------------        ^
                  ---->--! expression !--------
                    ^     ------------    !
                    !          ---        v
                     ---------( , )-------
                               ---                     *)
              var
                i: integer;
              begin
                InSymbol ;
                (* empty set *)
                cstpart :=[] ;
                varpart := false ;
                new(lsp);
                lsp^.stype := nil ;
                lsp^.size := setsize ;
                lsp^.form := power ;
                if sy = rbrack
                then
                begin
                  (* empty set *)
                  gattr.typtr := lsp ;
                  gattr.kind := cst ;
                  InSymbol;
                end
                else
                begin
                  repeat
                    Expression(fsys +[comma,rbrack]);
                    if gattr.typtr <> nil
                    then
                      if gattr.typtr^.form > subrange
                      then
                      begin
                        Error(136);
                        gattr.typtr := nil;
                      end
                      else
                      if CompTypes
                        (lsp^.stype, gattr.typtr)
                      then
                      begin
                        if gattr.kind = cst
                        then
                        begin
                          i := gattr.cval.ival ;
                          if(i < 0)or
                            (i > setmax)
                          then
                            error(169)
                          else
                            cstpart := cstpart +[i];
                        end
                        else
                        begin
                          Load ;
                          ByteGen(174);(* sgs *)
                          if varpart
                          then           (* uni *)
                            ByteGen(175)
                          else
                            varpart := true;
                        end ;
                        lsp^.stype := gattr.typtr ;
                        gattr.typtr := lsp ;
                      end
                      else
                        Error(137);
                    test := sy <> comma ;
                    if not test
                    then
                      InSymbol
                  until test ;
                  Intest(rbrack, 12);
                end ;
                if varpart
                then
                begin
                  if cstpart <>[]
                  then
                  begin
                    LoadSetConstant(cstpart);
                    ByteGen(175);        (* uni *)
                    gattr.kind := expr;
                  end;
                end
                else
                begin
                  new(lvp);
                  lvp^.pval := cstpart ;
                  gattr.cval.valp := lvp;
                end;
              end ;(* SetExpression *)

            begin(* Factor *)
             (* structure parsed :
               ---------------------
->-------------! constant identifier !--------------------->
  !            ---------------------                    !
  !                                                     ^
  !            ---------------------                    !
  !-----------! variable identifier !-------------------!
  !            ---------------------                    !
  !                                                     ^
  !            ---------------------       ----------   !
  !-----------! function identifier !-->--! par-list !--!
  !            ---------------------       ----------   !
  !                                                     ^
  !            ---------------------                    !
  !-----------! integer  constant   !-------------------!
  !            ---------------------                    !
  !                                                     ^
  !            ---------------------                    !
  !-----------! string constant     !-------------------!
  !            ---------------------                    !
  !                                                     ^
  !     ---    ---------------------       ---          !
  !----(()--! expression          !-----())---------!
  !     ---    ---------------------       ---          !
  !                                                     ^
  !   -----    ---------------------                    !
  !--(not)--! factor              !-------------------!
  !   -----    ---------------------                    !
  !                                                     ^
  !    ---     ---------------------                    !
  !---([)---! set expression      !-------------------
       ---     ---------------------                       *)
              lcp := nil ;
              if not(sy in facbegsys)
              then
              begin
                Error(58);
                Skip(fsys + facbegsys);
                gattr.typtr := nil;
              end ;
              while sy in facbegsys do
              begin
                case sy of
                  ident :
                  begin
                    Searchid([konst, vars, func], lcp);
                    InSymbol ;
                    if lcp^.klass = func
                    then
                    begin
                      Call(fsys, lcp);
                      gattr.kind := expr;
                    end
                    else if lcp^.klass = konst
                    then
                    begin
                      gattr.typtr := lcp^.idtype ;
                      gattr.kind := cst ;
                      gattr.cval := lcp^.values;
                    end
                    else
                      Selector(fsys, lcp);
                  end ;
                  intconst :
                  begin
                    gattr.typtr := intptr ;
                    gattr.kind := cst ;
                    gattr.cval := val ;
                    InSymbol;
                  end ;
                  stringconst :
                  begin
                    if lgth = 1
                    then
                      gattr.typtr := charptr
                    else
                    begin
                      new(lsp);
                      lsp^.stype := charptr ;
                      lsp^.form := arrays ;
                      lsp^.indextype := nil ;
                      lsp^.size := StringSize(val.valp);
                      gattr.typtr := lsp;
                    end ;
                    gattr.kind := cst ;
                    gattr.cval := val ;
                    InSymbol;
                  end ;
                  lparent :
                  begin
                    InSymbol ;
                    Expression(fsys +[rparent]);
                    Intest(rparent , 4);
                  end ;
                  notsy :
                  begin
                    InSymbol ;
                    Factor(fsys);
                    Load ;
                    ByteGen(172);     (* not *)
                    if gattr.typtr <> nil
                    then
                      if not CompTypes(gattr.typtr, boolptr)
                      then
                      begin
                                   (* result must be
                                       boolean to be negated *)
                        Error(135);
                        gattr.typtr := nil;
                      end ;
                  end ;
                  lbrack : SetExpression
                end ;
                Test2(fsys, 6, facbegsys);
              end ;(* while *)
            end ;(* Factor *)

          begin(* Term *)
          { structure parsed :

        --------
---->--! factor !-------------------------------------------------->
        --------  ^               !     !      !       !       !
                  !               v     v      v       v       v
                  !              ---   ---   -----   -----   -----
                  !            (*)(/)(div)(mod)(and)
                  !              ---   ---   -----   -----   -----
                  !   --------    !     !      !       !       !
                   <-! factor !-<----<-----<-------<------<----
                      --------                                     }

            Factor(fsys +[mulop]);
            while sy = mulop do
            begin
              Load ;
              lattr := gattr ;
              lop := op ;
              InSymbol ;
              Factor(fsys +[mulop]);
              Load ;
              if(lattr.typtr <> nil)and
                (gattr.typtr <> nil)
              then
              begin
                if lop = mul
                then
                  OPgen(lattr, 170, 0 , 167)(* mpi, int *)
                else if lop = idiv
                then
                  OPgen(lattr, 165, 0 , 0  )(* dvi *)
                else if lop = imod
                then
                  OPgen(lattr, 169, 0 , 0  )(* mod *)
                else if lop = andop
                then
                  OPgen(lattr, 0, 163,  0  )(* and *)
                else if lop = shlop
                then
                  OPgen(lattr, $c5, 0, 0  )(* shl *)
                else if lop = shrop
                then
                  OPgen(lattr, $c6, 0, 0  );(* shr *)
              end
              else
                gattr.typtr := nil;
            end ;(* while *)
          end ;(* Term *)
        begin(* SimpleExpression *)
       (* structure parsed :

           ---
       ---(+)->-
      !    ---    !
      !           v     ------
---->--!------------->--! term !---------------------------------->
      !           ^     ------  ^              !      !        !
      !    ---    !             !              v      v        v
       ---(-)->-              !             ---    ---      ----
           ---                  !           (+)(-)  (or)
                                !             ---    ---      ----
                                !   ------     !      !        !
                                 --! term !--------------------
                                    ------                       *)
          signed := false ;
          if(sy = addop)and
            (op in[plus, minus])
          then
          begin
            signed :=(op = minus);
            InSymbol;
          end ;
          Term(fsys +[addop]);
          if signed
          then
          begin
            Load ;
            if CompTypes(gattr.typtr, intptr)
            then
              ByteGen(171)               (* ngi *)
            else
            begin
              Error(134);
              gattr.typtr := nil;
            end;
          end ;
          while sy = addop do
          begin
            (* save on stack *)
            Load ;
            (* remember previous expression result *)
            lattr := gattr ;
            lop := op ;
            InSymbol ;
            Term(fsys +[addop]);
            Load ;
            if(lattr.typtr <> nil)and
              (gattr.typtr <> nil)
            then
            begin
              if lop = plus
              then
                OPgen(lattr, 162, 0, 175)(* adi, uni *)
              else if lop = minus
              then
                OPgen(lattr, 173, 0, 164)(* sbi, dif *)
              else if lop = orop
              then
                OPgen(lattr, 0, 168 , 0 );(* or *)
            end
            else
              gattr.typtr := nil ;
            gattr.kind := expr;
          end ;(* while sy = addop *)
        end ;(* SimpleExpression *)

      begin(* Expression *)
      (* structure parsed :
  -------------
-! simple expr !------------------------------------------------------->
 -------------  !                                                    !
                v                                                    !
              --------------------------------------                 !
             !     !     !     !      !      !      !                !
             v     v     v     v      v      v      v                !
            ---   ---   ---   ----   ----   ----   ----              !
            (=)   (<)   (>)   (<>)   (>=)   (<=)  (in)               ^
            ---   ---   ---   ----   ----   ----   ----              !
             !     !     !     !      !      !      !                !
             v     v     v     v      v      v      v  ------------  !
              ----------------------------------------! simpl expr !-
                                                       ------------  *)
        SimpleExpression(fsys +[relop]);
        if sy = relop
        then
        begin
          if gattr.typtr <> nil
          then
            if gattr.typtr^.form <= power
            then
              Load
            else
              LoadAddress ;
          lattr := gattr ;
          lop := op ;
          InSymbol ;
          SimpleExpression(fsys);
          if gattr.typtr <> nil
          then
            if gattr.typtr^.form <= power
            then
              Load
            else
              LoadAddress ;
          if(lattr.typtr <> nil)and
            (gattr.typtr <> nil)
          then
            if lop = inop
            then
              if gattr.typtr^.form = power
              then
                if CompTypes(lattr.typtr,
                  gattr.typtr^.stype)
                then
                  ByteGen(166)            (* inn *)
                else
                begin
                  Error(129);
                  gattr.typtr := nil;
                end
              else
              begin
                Error(130);
                gattr.typtr := nil;
              end
            else
            if CompTypes(lattr.typtr, gattr.typtr)
            then
            begin
              if lattr.typtr^.form = pointer
              then
              begin
                (* test on equality allowed only *)
                if lop in[ltop,leop, gtop,geop]
                then
                  Error(131);
              end
              else if lattr.typtr^.form = power
              then
              begin
                (* inclusion not allowed in set comp *)
                if lop in[ltop, gtop]
                then
                  Error(132);
              end
              else if lattr.typtr^.form = arrays
              then
              begin
                (* test on equality allowed only *)
                if not IsString(lattr.typtr)and
                  (lop in[ltop,leop, gtop,geop])
                then
                  Error(131);
              end
              else if lattr.typtr^.form = records
              then
                if lop in[ltop,leop, gtop,geop]
                then
                  Error(131)(* test on equality allowed only *) ;
              if(lattr.typtr^.form = power)and
                (lop = leop)
              then
                CondGen(145 , lattr)(* leq8 *)
              else if(lattr.typtr^.form = power)and
                (lop = geop)
              then
                CondGen(148 , lattr)(* geq8 *)
              else if lop = ltop
              then
                Condgen(147, lattr)(* les *)
              else if lop = leop
              then
                Condgen(144, lattr)(* leq *)
              else if lop = eqop
              then
                Condgen(150, lattr)(* equ *)
              else
              begin
                if lop = gtop
                then
                  Condgen(144,lattr)(* leq *)
                else if lop = geop
                then
                  Condgen(147,lattr)(* les *)
                else if lop = neop
                then
                  Condgen(150,lattr)(* equ *);
                ByteGen(172);       (* not *)
              end;
            end
            else
              Error(129) ;(* lop = inop *)
          gattr.typtr := boolptr ;
          gattr.kind := expr;
        end; (* sy = relop *)
      end ;(* Expression *)

      procedure Assignment(fcp : identptr);
      (* structure parsed :

               ------------       ---      ------------
       ->-----! identifier !-----(=)----! expression !---->
               ------------       ---      ------------        *)
      var
        {        lmax  : integer ;(* dummy for GetBounds *) }
        lattr : attr ;
      begin
        (* determine type of identifier for assignment *)
        Selector(fsys +[becomes], fcp);
        if sy <> becomes
        then
          (* := expected *)
          Error(51)
        else
        begin
          if gattr.typtr <> nil
          then
            if(gattr.access <> drct)or
              (gattr.typtr^.form > power)
            then
              LoadAddress ;
          lattr := gattr ;
          InSymbol ;
          Expression(fsys);
          if gattr.typtr <> nil
          then
            (* complex structure not simple store *)
            if gattr.typtr^.form  <= power
            then
              Load
            else
              LoadAddress ;
          if(lattr.typtr <> nil)and
            (gattr.typtr <> nil)
          then
            if CompTypes(lattr.typtr, gattr.typtr)
            then
            begin
              if lattr.typtr^.form in[arrays, records]
              then
              begin
                ByteGen(183);           (* mov *)
                WordGen(lattr.typtr^.size);
              end
              else
                Store(lattr);
            end
            (* assignment of array of char to array of char *)
            else if(isstring(lattr.typtr))
              and(isstring(gattr.typtr))
            then
            begin
              if lattr.typtr^.size < gattr.typtr^.size
              then
              begin
                ByteGen(183);           (* mov *)
                WordGen(lattr.typtr^.size);
              end
              else
              begin
                (* less to move, add blanks to end *)
                ByteGen(196);          (* mvb *)
                WordGen(gattr.typtr^.size);
                WordGen(lattr.typtr^.size -
                  gattr.typtr^.size);
              end;
            end
            (* assignment of char to array of char *)
            else if(isstring(lattr.typtr))
              and(gattr.typtr = charptr)
            then
            begin
              ByteGen(196);          (* mvb *)
              WordGen(1);
              WordGen(lattr.typtr^.size - 1);
            end
            else
              Error(129);
        end;(* sy = becomes *)
      end ;(* Assignment *)

      procedure CompoundStatement ;
       (* structure parsed :
            -------       -----------        -----
  ---->---(begin)-----! statement !------(end)---->
            -------   ^   -----------   !    -----
                      !                 v
                      !       ---       !
                       ------( ; )------
                              ---                       *)
      begin
        repeat
          repeat
            Statement(fsys +[semicolon, endsy])
          until not(sy in statbegsys);
          test := sy <> semicolon ;
          if not test
          then
            InSymbol
        until test ;
        Intest(endsy, 13);
      end ;(* CompoundStatement *)

      procedure IfStatement ;
       (* Parsed by ifStatement :
         (if symbol already parsed)
                                              ----   ---------
                                           --(else)-!statement!-
                                          !   ----   ---------  !
        ----------    ----    ---------   !                     v
if ->--!expression!--(then)--!statement!--!                     -->
        ----------    ----    ---------   !                     ^
                                          !                     !
                                           ---------------------

                                               *)
      var
        icix1, icix2 : integer ;
      begin
        (* expression must give boolean result for cond. jump *)
        Expression(fsys +[thensy]);
        FalseJumpGen(0);
        (* remember address for jump to plant after statement *)
        icix1 := ic + icn - 2 ;
        (* Then symbol *)
        Intest(thensy, 52);
        (* statement *)
        Statement(fsys +[elsesy]);
        (* maybe else part with statement *)
        if sy = elsesy
        then
        begin
          (* end then part with unconditional jump to end *)
          icix2 := ic + icn ;
          GenUJPent(178 , 0);    (* ujp *)
          (* fill in address of cond jump if result is false *)
          PlantWord( icix1, ic + icn);
          InSymbol ;
          Statement(fsys);
          (* we know now end of else part *)
          PlantWord(icix2 + 1, ic + icn);
        end
        else
          (* no else part, fill in conditional jump address *)
          PlantWord(icix1, ic + icn);
      end ;(* IfStatement *)

      procedure CaseStatement ;
      (* Parsed by CaseStatement :
         (Case symbol already parsed)
            -----------     ----
case->----! expression !---(OF)---->---
          ------------     ----          !
                                         !
   --------------------------------------
  !
  v
  !
   -----------! constant !------( ; )---! statement !---------
    ^     ^    ----------   !    ---      -----------       !  !
    !     !                 v                               v  v
    !     !        ---      !                               !  !
    !      -------( , )-----                                !  !
    !              ---              ---                     !  !
     ------------------------------( ; )--------------------   !
                                    ---                        !
   ------------------------------------------------------------
  !
  v                ------
  !          -----(else)----
  !         !      ------     !
  !         !                 !     -----------
   ---->----!                 !-->-! statement ! -->-------->
  !         !                 !     -----------         !
  !         !   -----------   !                         !
  !          --(ELSE)      --                           ^
  !             -----------                             !
  !                                                     !
   ---->------------------------------------------------  *)
      type
        CasInfoptr = ^caseinfo ;
        caseinfo    = packed record
          casenext : CasInfoptr ;
          csstart,cslab : integer
        end ;
      var
        lsp, lsp1 : structptr ;
        fstptr, lpt1, lpt2, lpt3 : CasInfoptr  ;
        lval : valu ;
        lcix, lcix1, lmin, lmax : integer ;

      begin

        lsp := nil ;
        lsp1 := nil ;

        Expression(fsys +[ofsy, comma, colon]);
        Load ;
        lcix := ic + icn ;
        GenUJPent(178, 0); (* ujp to CAS instruction *)
        GenUJPent(178, 0); (* ujp to exit *)
        lsp := gattr.typtr ;
        if lsp <> nil
        then
          if lsp^.form > subrange
          then
          begin
            Error(144);
            lsp := nil;
          end ;
        Intest(ofsy, 8);

        (* Process case statements *)
        fstptr := nil ;
        repeat
          lpt3 := nil ;
          lcix1 := ic + icn ;
          repeat
            lval.ival := 0 ;
            Constant(fsys +[comma,colon], lsp1, lval);
            if lsp1 <> nil
            then
              if CompTypes(lsp, lsp1)
              then
              begin
                lpt1 := fstptr ;
                lpt2 := nil ;
                test := true ;
                while(lpt1 <> nil)and test do
                  if lpt1^.cslab <= lval.ival
                  then
                  begin
                    if lpt1^.cslab = lval.ival
                    then
                      Error(156);
                    test := false;
                  end
                  else
                  begin
                    lpt2 := lpt1 ;
                    lpt1 := lpt1^.casenext;
                  end ;
                new(lpt3);
                lpt3^.casenext := lpt1 ;
                lpt3^.cslab := lval.ival ;
                lpt3^.csstart := lcix1 ;
                if lpt2 = nil
                then
                  fstptr := lpt3
                else
                  lpt2^.casenext := lpt3;
              end
              else
                Error(147);
            test := sy <> comma ;
            if not test
            then
              InSymbol
          until test ;
          Intest(colon, 5);
          repeat
            Statement(fsys +[semicolon, elsesy])
          until not(sy in statbegsys);
          if lpt3 <> nil
          then
            GenUJPent(178, lcix + 3);   (* ujp *)
          test := sy <> semicolon ;
          if not test
          then
            InSymbol ;
        until test or (sy = endsy) or (sy = elsesy);
        PlantWord(lcix + 1 , ic + icn);
        
        (* Emit CAS instruction and jump table. *)
        if fstptr <> nil
        then
        begin
          lmax := fstptr^.cslab ;
          lpt1 := fstptr ;
          fstptr := nil ;
          (* reverse pointers *)
          repeat
            lpt2 := lpt1^.casenext ;
            lpt1^.casenext := fstptr ;
            fstptr := lpt1 ;
            lpt1 := lpt2
          until lpt1 = nil ;
          lmin := fstptr^.cslab ;
          ByteGen(182) ;         (* CAS *)
          WordGen(lmin);
          WordGen(lmax);
          lcix1 := ic + icn ;
          WordGen(0);
          repeat
            while fstptr ^.cslab > lmin do
            begin
              WordGen(0);
              lmin := lmin + 1 ;
            end ;
            WordGen(fstptr^.csstart);
            fstptr := fstptr^.casenext ;
            lmin := lmin + 1
          until fstptr = nil;
        end(* fstptr <> nil *)
        else
          Error(157);
          
        (* Emit the ELSE clause, if there is one. *)
        if sy = elsesy
        then
        begin
          InSymbol ;
          PlantWord(lcix1, ic + icn);
          repeat
            Statement(fsys +[semicolon])
          until not(sy in statbegsys);
          GenUJPent(178 , lcix + 3);
        end ;
        
        (* And exit. *)
        PlantWord(lcix + 4, ic + icn);
        Intest(endsy, 13);
      end ;(* CaseStatement *)

      procedure RepeatStatement ;
       (* Parsed by RepeatStatement :
          (repeat symbol already parsed)
            -----------         -------       ------------
repeat->----! statement !-------(until)----! expression !--->
        ^   -----------     !   -------       ------------
        !         -         !
         --------(;)--------
                  -                                          *)
      var
        laddr : integer ;
      begin
        (* remember address for false jump at until *)
        laddr := ic + icn ;
        (* one or more statement blocks *)
        repeat
          repeat
            Statement(fsys +[semicolon, untilsy])
          until not(sy in statbegsys);
          test := sy <> semicolon ;
          if not test
          then
            InSymbol
        until test ;
        (* until part *)
        if sy = untilsy
        then
        begin
          InSymbol ;
          (* expression *)
          Expression(fsys);
          (* expression result must be boolean for FJP *)
          FalseJumpGen(laddr);
        end
        else
          (* until expected but not found *)
          Error(53);
      end ;(* RepeatStatement *)

      procedure WhileStatement ;
      (* Parsed by WhileStatement :
         (while symbol already parsed)
              ------------           ----       ----------
while ->----! expression !---------(do)----!statement !--->
             ------------           ----       ----------     *)
      var
        laddr, lcix : integer ;
      begin
        (* remember address for jump at at end of while *)
        laddr := ic + icn ;
        (* parse boolean expression *)
        Expression(fsys +[dosy]);
        (* remember address of conditional jump out of loop *)
        lcix := ic + icn ;
        FalseJumpGen(0);
        (* do symbol expected *)
        Intest(dosy, 54);
        (* parse body of loop *)
        Statement(fsys);
        (* Unconditional jump back to begin of loop *)
        GenUJPent(178, laddr);    (* ujp *)
        (* address for jump out of loop now known *)
        PlantWord(lcix + 1 , ic + icn);
      end ;(* WhileStatement *)

      procedure ForStatement ;
      (* Parsed by ForStatement :
         (for symbol already parsed)
        -----------    ----     ------------
for ->--! var-ident !--(:=)---! expression !--->
        -----------    ----     ------------     !
                                                 !
 ------------------------------------------------
!        -------
!    --(downto)---
!   !   --------    !   ------------    ----    -----------
 ->-!               !--! expression !--(do)--! statement !--->
    !     ----      !   ------------    ----    -----------
     ---( to )-----
          ----                                 *)
      var
        lattr : attr ;
        {         lsp : structptr ; }
        lsy : symbol ;
        lcix, laddr : integer ;
      begin
        (* Variable identifier, find description *)
        if sy = ident
        then
        begin
          Searchid([vars], lcp);
          lattr.typtr := lcp^.idtype ;
          lattr.kind := varbl ;
          if lcp^.vkind = actual
          then
            LDAgen(level, lcp^.vlev, lcp^.vaddr)
          else
          begin
            Error(155);
            lattr.typtr := nil;
          end ;
          if lattr. typtr <> nil
          then
            if(lattr.typtr^.form > subrange)
            then
            begin
              (* illegal type of loop control variable *)
              Error(143);
              lattr.typtr := nil;
            end ;
          InSymbol ;
        end
        else
        begin
          (* identifier expected *)
          Error(2);
          Skip(fsys +[becomes, tosy, downtosy, dosy]);
        end ;
        (* := *)
        if sy = becomes
        then
        begin
          InSymbol ;
          (* expression, must be same type as var. ident *)
          Expression(fsys +[tosy, downtosy, dosy]);
          if gattr.typtr <> nil
          then
            if gattr.typtr^.form > subrange
            then
              (* illegal type of expression *)
              Error(144)
            else
            if CompTypes(lattr.typtr, gattr.typtr)
            then
              (* put beginvalue of loop variable on stack *)
              Load
            else
              (* type conflict *)
              Error(145);
        end
        else
        begin
          (* := expected *)
          Error(51);
          Skip(fsys +[tosy, downtosy, dosy]);
        end ;
        (* parse to or downto *)
        if sy in[tosy, downtosy]
        then
        begin
          lsy := sy ;
          InSymbol ;
          Expression(fsys +[dosy]);
          if gattr.typtr <> nil
          then
            if gattr.typtr^.form > subrange
            then
              Error(144)
            else
            if CompTypes(lattr.typtr, gattr.typtr)
            then
            begin
              (* put end value of loop variable on stack *)
              Load ;
              lcix := lattr.typtr^.size - 1 ;
              if lsy = downtosy
              then
                lcix := lcix + 4 ;
              (* stepsize on stack *)
              ByteGen(lcix);
              laddr := ic + icn ;
              (* generate jump instruction to for statement *)
              GenUJPent(178, 0);    (* ujp *)
            end
            else
              (* type conflict with loop variable *)
              Error(145);
        end
        else
        begin
          (* to/downto expected *)
          Error(55);
          Skip(fsys +[dosy]);
        end ;

        (* skip and test do symbol *)
        Intest(dosy, 54);
        (* statement *)
        Statement(fsys);
        (* now we know address of end of for loop *)
        PlantWord(laddr + 1 , ic + icn);
        GenUJPent(145 , laddr + 3) ;            (* for *)
      end ;(* ForStatement *)

    begin(* Statement *)
      if not(sy in fsys +[ident])
      then
      begin
        Error(6);
        Skip(fsys);
      end ;
      if sy  in(statbegsys +[ident])
      then
      begin
        pfcttest := false ;
        case sy of
          ident :
          begin
            Searchid([vars, func, proc], lcp);
            InSymbol ;
            if lcp^.klass = proc
            then
              Call(fsys, lcp)
            else
              Assignment(lcp);
          end ;
          beginsy :
          begin
            InSymbol ;
            CompoundStatement;
          end ;
          ifsy :
          begin
            InSymbol ;
            IfStatement;
          end ;
          whilesy :
          begin
            InSymbol ;
            WhileStatement;
          end ;
          repeatsy :
          begin
            InSymbol ;
            RepeatStatement;
          end ;
          forsy :
          begin
            InSymbol ;
            ForStatement;
          end ;
          casesy :
          begin
            InSymbol ;
            CaseStatement;
          end
        end ;
        if not(sy in[semicolon,endsy,elsesy,untilsy])
        then
        begin
          Error(6);
          Skip(fsys);
        end;
      end ;
    end ;(* Statement *)

  begin(* body *)
    (* fprocp is pointer to proc/func/program identifier *)
    entname := fprocp^.pfname ;
    (* empty code buffer *)
    WriteOut ;
    sumcheck := 0 ;
    write(objectfile^,'P4');
    HexOut(entname);
    for i := 1 to 8 do
    begin
      write(objectfile^, fprocp^.name[i]);
      sumcheck := sumcheck + ord(fprocp^.name[i]);
    end ;
    writeln('Processing: ', fprocp^.name);
    HexOut((16383 - sumcheck)mod 256);
    writeln(objectfile^);
    (* remember where to put nr of bytes for local variables *)
    segsize := ic + icn ;
    GenUJPent(181, 0);              (* ENT *)
    (* start with 6 bytes on stack *)
    llc1 := lcaftermarkstack ;
    (* parameter-list as linked list on next^ *)
    lcp := fprocp^.next ;
    while lcp <> nil do
    begin
      if lcp^.klass = vars
      then
        if lcp^.idtype <> nil
        then
          if  lcp^.idtype^.form > power
          then
          begin
            llc1 := llc1 + ptrsize ;
            if lcp^.vkind = actual
            then
            begin
              (* copy record or array *)
              LDAgen(0, 0, lcp^.vaddr);
              ByteGen(96);(* LOD *)
              ByteGen(llc1);
              ByteGen(183);    (* mov *)
              WordGen(lcp^.idtype^.size);
            end;
          end
          else
            (* keep track of local space on stack *)
            llc1 := llc1 + lcp^.idtype^.size ;
      lcp:= lcp^.next ;
    end ;(* while *)
    lcmax := lc ;
    repeat
      repeat
        Statement(fsys +[semicolon, endsy])
      until not(sy in statbegsys);
      test := sy <> semicolon ;
      if not test
      then
        InSymbol
    until test ;
    Intest(endsy, 13);
    ByteGen(161);               (* retp *)
    PlantWord(segsize + 1 , lcmax - lcaftermarkstack);
  end ;(* body *)

begin(* Block*)
  repeat
    if sy = constsy
    then
    begin
      InSymbol ;
      ConstDeclaration;
    end  ;
    if sy = typesy
    then
    begin
      InSymbol ;
      TypeDeclaration;
    end  ;
    if sy = varsy
    then
    begin
      InSymbol ;
      VarDeclaration;
    end  ;
    while sy in[procsy, funcsy] do
    begin
      lsy := sy ;
      InSymbol ;
      ProcDeclaration(lsy);
    end ;
    if sy <> beginsy
    then
    begin
      Error(18);
      Skip(fsys);
    end
  until sy in statbegsys ;
  Intest(beginsy,17);
  repeat
    body(fsys);
    Test2([fsy], 6, fsys)
  until(sy = fsy)or(sy in blockbegsys);
end ;(* Block*)

procedure StdNames ;
begin
  (* standard procedures *)
  nap[ 0] := 'false   ' ; nap[ 1] := 'true    ' ; nap[ 2] := 'read    ' ;
  nap[ 3] := 'write   ' ; nap[ 4] := 'new     ' ; nap[ 5] := 'release ' ;
  nap[ 6] := 'readln  ' ; nap[ 7] := 'writeln ' ; nap[ 8] := 'reset   ' ;
  nap[ 9] := 'rewrite ' ; nap[10] := 'exit    ' ; nap[11] := 'halt    ' ;
  nap[12] := 'close   ' ; nap[13] := 'writemem' ; nap[14] := 'assign  ' ;
  nap[15] := 'getcomma' ;
  (* standard functions *)
  naf[ 0] := 'ord     ' ; naf[ 1] := 'chr     ' ; 
  naf[ 2] := 'odd     ' ; naf[ 3] := 'succ    ' ; naf[ 4] := 'pred    ' ; 
  naf[ 5] := 'eoln    ' ; naf[ 6] := 'eof     ' ; naf[ 7] := 'status  ' ;
  naf[ 8] := 'readmem ' ;
end ;(* StdNames *)

procedure Enterstdtypes ;
begin
  (* integer *)
  new(intptr);
  intptr^.size  := intsize ;
  intptr^.form  := scalar  ;
  intptr^.stype := nil     ;
  (* char *)
  new(charptr);
  charptr^.size  := charsize ;
  charptr^.form  := scalar  ;
  charptr^.stype := nil     ;
  (* boolean *)
  new(boolptr);
  boolptr^.size  := boolsize ;
  boolptr^.form  := scalar  ;
  boolptr^.stype := nil     ;
  (* pointer nil *)
  new(nilptr);
  nilptr^.size  := ptrsize ;
  nilptr^.form  := pointer ;
  nilptr^.stype := nil     ;
  (* file *)
  new(fileptr);
  fileptr^.size  := 128 + 36 + 1 + 1; (* buffer + fcb + position byte + status flag *)
  fileptr^.stype := nil     ;
  fileptr^.form  := files   ;
end ;(* Enterstdtypes *)

procedure Enterstnames ;
var
  cp, cp1 : identptr;
  i : integer ;
begin
  (* integer *)
  new(cp);
  cp^.name := 'integer ' ;
  cp^.idtype := intptr ;
  cp^.next := nil ;
  cp^.klass := types ;
  Enterid(cp);
  (* char *)
  new(cp);
  cp^.name := 'char    ' ;
  cp^.idtype := charptr ;
  cp^.next := nil ;
  cp^.klass := types ;
  Enterid(cp);
  (* boolean *)
  new(cp);
  cp^.name := 'boolean ' ;
  cp^.idtype := boolptr ;
  cp^.next := nil ;
  cp^.klass := types ;
  Enterid(cp);
  (* text-file *)
  new(cp);
  cp^.name := 'text    ' ;
  cp^.idtype := fileptr ;
  cp^.next := nil ;
  cp^.klass := types;
  Enterid(cp);
  (* false, true *)
  cp1 := nil ;
  for i := 0 to 1 do
  begin
    new(cp);
    cp^.name := nap[i] ;
    cp^.idtype := boolptr ;
    cp^.next := cp1 ;
    cp^.klass := konst ;
    cp^.values.ival := i ;
    Enterid(cp);
    cp1 := cp;
  end ;
  (* nil pointer *)
  new(cp);
  cp^.name := 'nil     ' ;
  cp^.idtype := nilptr ;
  cp^.next := nil ;
  cp^.klass := konst ;
  cp^.values.ival := 0 ;
  Enterid(cp);
  (* i/o and pointer procedures
      key  1 = read
      key  2 = write
      key  3 = new
      key  4 = release
      key  5 = readln
      key  6 = writeln
      key  7 = reset
      key  8 = rewrite
      key  9 = exit
      key 10 = halt
      key 11 = close
      key 12 = writemem
      key 13 = assign
      key 14 = getcommandline
*)
  for i := 2 to 15 do
  begin
    new(cp);
    cp^.name := nap[i] ;
    cp^.idtype := nil ;
    cp^.next := nil ;
    cp^.klass := proc ;
    cp^.pfdeckind := standard ;
    cp^.key := i - 1 ;
    Enterid(cp);
  end ;
  (* Standard functions :
       key 1 = ord 
       key 2 = chr
       key 3 = odd
       key 4 = succ
       key 5 = pred
       key 6 = eoln
       key 7 = eof 
       key 8 = status 
       key 9 = readmem  *)

  for i := 0 to 8 do
  begin
    new(cp);
    cp^.name := naf[i] ;
    cp^.idtype := nil ;
    cp^.next := nil ;
    cp^.klass := func ;
    cp^.pfdeckind := standard ;
    cp^.key := i + 1 ;
    Enterid(cp);
  end ;
  (* files input and output and keyboard *)
  new(cp);
  cp^.name := 'input   ' ;
  cp^.idtype := fileptr ;
  cp^.next := nil ;
  cp^.klass := vars ;
  cp^.vkind := actual ;
  cp^.vaddr := 1 ;       (* 1 = input *)
  cp^.vlev := -1 ;
  Enterid(cp);
  new(cp);
  cp^.name := 'output  ' ;
  cp^.idtype := fileptr ;
  cp^.next := nil ;
  cp^.klass := vars ;
  cp^.vkind := actual ;
  cp^.vaddr := 2 ;       (* 2 = output *)
  cp^.vlev := -1 ;
  Enterid(cp);
  new(cp);
  cp^.name := 'keyboard' ;
  cp^.idtype := fileptr ;
  cp^.next := nil ;
  cp^.klass := vars ;
  cp^.vkind := actual ;
  cp^.vaddr := 3 ;       (* 3 = keyboard *)
  cp^.vlev := -1 ;
  Enterid(cp);
end ;(* Enterstnames *)

procedure Enterundecl ;
begin
  new(utypptr);
  utypptr^.name := '        ' ;
  utypptr^.idtype := nil ;
  utypptr^.klass := types ;
  new(ucsptr);
  ucsptr^.name := '        ' ;
  ucsptr^.idtype := nil ;
  ucsptr^.next := nil ;
  ucsptr^.klass := konst ;
  ucsptr^.values.ival := 0 ;
  new(uvarptr);
  uvarptr^.name := '        ' ;
  uvarptr^.idtype := nil ;
  uvarptr^.next := nil ;
  uvarptr^.klass := vars ;
  uvarptr^.vkind := actual ;
  uvarptr^.vaddr := 0 ;
  uvarptr^.vlev := 0 ;
  new(ufldptr);
  ufldptr^.name := '        ' ;
  ufldptr^.idtype := nil ;
  ufldptr^.next := nil ;
  ufldptr^.klass := field ;
  ufldptr^.vaddr := 0 ;
  new(uprcptr);
  uprcptr^.name := '        ' ;
  uprcptr^.idtype := nil ;
  uprcptr^.forwdecl := false ;
  uprcptr^.next := nil ;
  uprcptr^.klass := proc ;
  uprcptr^.pfdeckind := declared ;
  uprcptr^.pflev := 0 ;
  uprcptr^.pfname := 0 ;
  uprcptr^.externl := false ;
  new(ufctptr);
  ufctptr^.name := '        ' ;
  ufctptr^.idtype := nil ;
  ufctptr^.next := nil ;
  ufctptr^.forwdecl := false ;
  ufctptr^.klass := func ;
  ufctptr^.pfdeckind := declared ;
  ufctptr^.pflev := 0 ;
  ufctptr^.pfname := 0 ;
  ufctptr^.externl := false ;
end ;(* Enterundecl *)

procedure Initialize ;
(* Fills all tables and counters etc with default values *)
var
  i : integer ;
begin
  errflag   := false ; (* No errors yet *)
  errtot    := 0 ;
  linecount := 0 ;
  fwptr     := nil   ;
  prterr    := true ;
  errinx    := 0 ;
  lc        := lcaftermarkstack ;
  ic        := 0 ;
  icn       := 0 ;
  ch        := ' ' ;
  ich       := 32 ;
  mxintio := maxint ;
  nproc := 1 ;
  (* Initialize sets *)
  constbegsys    :=[addop, intconst, stringconst, ident] ;
  simptypebegsys :=[lparent] + constbegsys ;
  typebegsys     :=[arrow, packedsy, arraysy, recordsy, setsy] +
    simptypebegsys ;
  typedels       :=[arraysy, recordsy, setsy] ;
  blockbegsys    :=[constsy, typesy, varsy, procsy, funcsy, beginsy];
  selectsys      :=[arrow, period, lbrack] ;
  facbegsys      :=[intconst, stringconst, ident, lparent,
    realconst, lbrack, notsy] ;
  statbegsys     :=[beginsy, ifsy, whilesy,
    repeatsy, casesy, forsy] ;

  (* Initialize tables *)
  rw[ 0] := 'if      ' ; rw[ 1] := 'do      ' ;
  rw[ 2] := 'of      ' ; rw[ 3] := 'in      ' ;
  rw[ 4] := 'or      ' ; rw[ 5] := 'to      ' ;
  rw[ 6] := 'end     ' ; rw[ 7] := 'for     ' ;
  rw[ 8] := 'var     ' ; rw[ 9] := 'div     ' ;
  rw[10] := 'mod     ' ; rw[11] := 'set     ' ;
  rw[12] := 'shl     ' ; rw[13] := 'shr     ' ;
  rw[14] := 'and     ' ; rw[15] := 'not     ' ;
  rw[16] := 'then    ' ; rw[17] := 'else    ' ;
  rw[18] := 'type    ' ; rw[19] := 'case    ' ;
  rw[20] := 'begin   ' ; rw[21] := 'until   ' ;
  rw[22] := 'while   ' ; rw[23] := 'array   ' ;
  rw[24] := 'const   ' ; rw[25] := 'repeat  ' ;
  rw[26] := 'record  ' ; rw[27] := 'packed  ' ;
  rw[28] := 'extern  ' ; rw[29] := 'downto  ' ;
  rw[30] := 'forward ' ; rw[31] := 'program ' ;
  rw[32] := 'function' ; rw[33] := 'procedur' ;
  frw[0] := 0   ;
  frw[1] := 0   ;
  frw[2] := 6   ;
  frw[3] := 16  ;
  frw[4] := 20  ;
  frw[5] := 25  ;
  frw[6] := 30  ;
  frw[7] := 32  ;
  frw[8] := 34  ;
  (* Initialize symbols *)
  rsy[ 0] := ifsy      ; rsy[ 1] := dosy     ;
  rsy[ 2] := ofsy      ; rsy[ 3] := relop    ;
  rsy[ 4] := addop     ; rsy[ 5] := tosy     ;
  rsy[ 6] := endsy     ; rsy[ 7] := forsy    ;
  rsy[ 8] := varsy     ; rsy[ 9] := mulop    ;
  rsy[10] := mulop     ; rsy[11] := setsy    ;
  rsy[12] := mulop     ; rsy[13] := mulop    ;
  rsy[14] := mulop     ; rsy[15] := notsy    ;
  rsy[16] := thensy    ; rsy[17] := elsesy   ;
  rsy[18] := typesy    ; rsy[19] := casesy   ;
  rsy[20] := beginsy   ; rsy[21] := untilsy  ;
  rsy[22] := whilesy   ; rsy[23] := arraysy  ;
  rsy[24] := constsy   ; rsy[25] := repeatsy ;
  rsy[26] := recordsy  ; rsy[27] := packedsy ;
  rsy[28] := externsy  ; rsy[29] := downtosy ;
  rsy[30] := forwardsy ; rsy[31] := progsy   ;
  rsy[32] := funcsy    ; rsy[33] := procsy   ;
  for i :=0 to 127 do
  begin
    ssy[i]  := othersy ;
    sop[i]  := noop;
  end ;
  ssy[ord('+')] := addop     ;
  ssy[ord('-')] := addop     ;
  ssy[ord('*')] := mulop     ;
  ssy[ord('/')] := mulop     ;
  ssy[ord('(')] := lparent   ;
  ssy[ord(')')] := rparent   ;
  ssy[ord('$')] := othersy   ;
  ssy[ord('=')] := relop     ;
  ssy[ord(' ')] := othersy   ;
  ssy[ord(',')] := comma     ;
  ssy[ord('.')] := period    ;
  ssy[ord('"')] := othersy   ;
  ssy[ord('[')] := lbrack    ;
  ssy[ord(']')] := rbrack    ;
  ssy[ord(':')] := colon     ;
  ssy[ord('^')] := arrow     ;
  ssy[ord('<')] := relop     ;
  ssy[ord('>')] := relop     ;
  ssy[ord(';')] := semicolon ;
  (* Initialize operators *)
  for i := 0 to 32 do
    rop[i] := noop ;
  rop[ 3] := inop  ;
  rop[ 4] := orop  ;
  rop[ 9] := idiv  ;
  rop[10] := imod  ;
  rop[12] := shlop ;
  rop[13] := shrop ;
  rop[14] := andop ;
  sop[ord('+')] := plus  ;
  sop[ord('-')] := minus ;
  sop[ord('*')] := mul   ;
  sop[ord('=')] := eqop  ;
  sop[ord('/')] := idiv  ;
  sop[ord('<')] := ltop  ;
  sop[ord('>')] := gtop  ;
  (* Enter standard names and standard types *)
  level      := 0   ;
  top        := 0   ;
  for i := 0 to displimit do
    display[i] := nil ;
  Enterstdtypes  ;
  Stdnames ;
  Enterstnames ;
  Enterundecl ;
  top := 1 ;
  level := 1 ;
  savetop := 1 ;
end ;(* Initialize *)


procedure CompileHeading ;
begin
  BeginLine ;
  InSymbol ;
  new(progptr);
  progptr^.idtype := nil ;
  progptr^.next := nil ;
  progptr^.klass := proc ;
  progptr^.pfdeckind := declared ;
  progptr^.pfname := 0 ;
  progptr^.name := '        ' ;
  if sy = progsy then
  begin
    (* program name *)
    InSymbol ;
    if sy <> ident
    then
      Error(2)
    else
      progptr^.name := id ;
    (* Skip input/output after program name *)
    while sy <> semicolon do
      InSymbol ;
    (* Skip semicolon *)
    InSymbol ;
  end ;
end ; (* Compile program heading *)


function CompilePascalM: boolean ;
begin
  Initialize ;
  {
  writeln(errorfile^, 'Compilation of ',filename) ;
  }

  (* Compile program-heading *)
  CompileHeading ;
  (* jump into block until end *)
  Block(blockbegsys + statbegsys, period , progptr);

  EndLine ;
  WriteOut ;
  if errflag
  then
  begin
    writeln(errorfile^,'Compilation errors ', sourcename ) ;
    writeln(errorfile^,' Pascal-M Compilation : ', errtot:4,' errors ');
    writeln(objectfile^,'P1010000');
    CompilePascalM := false ;
  end
  else
  begin
    writeln(errorfile^,'No compilation errors ', sourcename ) ;
    writeln(objectfile^, 'P9');
    CompilePascalM := true ;
  end ;
end ;

procedure OpenFiles ;
var
  parameters : packed array[0..127] of char;
  len, i, j : integer;

  procedure SkipSpaces;
  begin
    while (i <= len) and (parameters[i] = ' ') do
      i := i + 1;
  end;

  procedure GetWord(var s: pathstring);
  begin
    SkipSpaces;
    j := 0;
    s := '';
    while (i <= len) and (parameters[i] <> ' ') and (ord(parameters[i]) <> 0) do
    begin
      s[j+1] := parameters[i];
      i := i + 1;
      j := j + 1;
    end;
  end;

  function FindEnd(var s: pathstring): integer;
  var
    len: integer;
    i: integer;
  begin
    i := pathlen;
    while (i <> -1) and ((s[i] = ' ') or (ord(s[i]) = 0)) do
      i := i - 1;
    FindEnd := i;
  end;
begin
  parameters := '';
  GetCommandLine(parameters);
  len := ord(parameters[0]);

  i := 1;
  GetWord(sourcename);
  GetWord(destname);

  new(sourcefile);
  assign(sourcefile^, sourcename);
  reset(sourcefile^);

  new(objectfile);
  assign(objectfile^, destname);
  rewrite(objectfile^);

  i := FindEnd(destname);
  destname[i-2] := 'e';
  destname[i-1] := 'r';
  destname[i-0] := 'r';
  new(errorfile);
  assign(errorfile^, destname);
  rewrite(errorfile^);
  
  ShowErrors := true;
end ; (* OpenFiles *)

procedure CloseFiles ;
begin
  close(sourcefile^) ;
  write(objectfile^, chr(26));
  close(objectfile^) ;
  write(errorfile^, chr(26));
  close(errorfile^) ;
end  ; (* CloseFiles *)

procedure Dumperrorfile ;
var
  line : alphastring ;
begin
  assign( errorfile^, destname) ;
  reset(errorfile^) ;
  while not eof(errorfile^) do
  begin
    line := '';
    readln(errorfile^, line) ;
    writeln(line);
  end;
  close(errorfile^) ;
end;

begin (* main Mpascal *)
  writeln ( 'Pascal-M compiler V2k1 for CP/M-65') ;
  Openfiles ;
  if CompilePascalM then
    writeln('Compilation successful.')
  else
    writeln('Compile errors, see error file!') ;
  CloseFiles ;
  if ShowErrors then
    Dumperrorfile ;
  if errflag then
    halt;
end.
