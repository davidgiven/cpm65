program cpascalmdis ;

(* Written by   : H.J.C. Otten
   Last update  : 13 october 2021
   Version 2k1

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

uses Sysutils ;


var
  objectfilename,
  errorfilename,
  listfilename,
  asmfilename,
  filenamepart: string ;
  loadaddress : integer ;
  objectfile, asmfile, listfile, errorfile : text ;

  {$I pascalmdisassembler.inc }

function HexToDec(Str: string): Integer;
var
    i, M, lResult : Integer;
begin
    lResult := 0;
    M := 1;
    Str := AnsiUpperCase(Str);
    for i:=Length(Str)downto 1 do
    begin
      case Str[i] of
        '1'..'9': lResult:= lResult+(Ord(Str[i])-Ord('0'))*M;
        'A'..'F': lResult:= lResult+(Ord(Str[i])-Ord('A')+10)*M;
      end;
      M:=M shl 4;
    end;
    HexToDec := lResult ;
  end;

procedure OpenFilesDisassembler ;
var
    i : integer ;
begin(* Openfiles *)
  if paramcount = 0
    then
      begin
        write('Pascal-M object file to load> ');
        readln(objectfilename)
      end
    else
      objectfilename := paramstr(1);
  loadaddress := 0 ;
  if paramcount = 2
    then
      loadaddress := HexToDec(paramstr(2));
  if loadaddress > 32767
    then
      loadaddress := 0 ;
  if (objectfilename = '?') or
     (objectfilename = 'h') or
     (objectfilename = 'H') or
     (objectfilename = '/h') or
     (objectfilename = '-h')
    then
      begin
        writeln('cpascalmdis <objectfile>[<loadaddress in hex>]');
        halt(1)
      end;
  if FileExists(objectfilename)
    then
      begin
        assign(objectfile, objectfilename);
        reset(objectfile);
      end
     else
       begin
         writeln(errorfile, 'No such file');
         exit ;
       end;
  { extract filename part }
  filenamepart := '' ;
  i := 1 ;
  while objectfilename[i] <> '.' do
    begin
      filenamepart := filenamepart + objectfilename[i] ;
      i := i + 1 ;
    end ;
  {$I-1}
  asmfilename := filenamepart + '.asm' ;
  assign(asmfile, asmfilename);
  rewrite(asmfile);
  listfilename := filenamepart + '.dlst' ;
  assign(listfile, listfilename);
  rewrite(listfile);
  errorfilename := filenamepart + '.errd' ;
  assign(errorfile, errorfilename);
  rewrite(errorfile);
  {$I+}
  if IOResult <> 0
    then
      begin
        writeln('Error opening files');
        halt(1)
      end ;
end  ;(* OpenFiles *)

procedure CloseFilesDisassembler ;
  begin
    {$I-}
    close(objectfile);
    close(listfile);
    close(asmfile);
    close(errorfile);
   {$I+}
  end  ;(* CloseFiles *)


begin(* main PasDis *)
    writeln('Disassembler for Pascal-M 2K1');
    OpenFilesDisassembler ;
    if PascalmDisassembler
      then
        writeln(objectfilename, ' disassembled for load address ',
                                 hexstr(loadaddress,4))
      else
        writeln(objectfilename, ' disassembly errors, see ', errorfilename);
    CloseFilesDisassembler ;
end .


