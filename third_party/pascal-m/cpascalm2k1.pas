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

{$APPTYPE CONSOLE}
{$mode DELPHI}

uses
  Classes, SysUtils;
var
   sourcefile, objectfile,listfile, errorfile : text ;
   filename, namefile :  string ;
   ShowErrors : boolean ;

{$i pascalmcompiler.inc}

 procedure OpenFiles ;
   var
     i : integer ;
     filenamepart : string ;
   begin
     if paramcount = 0
       then
         begin
           write('Pascal-M source> ') ;
           readln(namefile)
         end
       else
         namefile := paramstr(1) ;
     if (namefile = '?') or
        (namefile = 'h') or
        (namefile = 'H') or
        (namefile = '/h') or
        (namefile = '-h')
    then
      begin
        writeln('Syntax: cpascalm2k1 <sourcefile> [V]');
        writeln('produces sourcefile.err (status) and sourcefile.obp (object) files') ;
        writeln('V shows errors on console') ;
        halt(1)
      end;
     if FileExists(namefile)
       then
         begin
           filename := namefile ;
           assign (sourcefile, filename);
           reset(sourcefile) ;
         end
       else
          begin
            writeln('No such file ', namefile) ;
            halt(1) ;
          end;
     { extract filename part }
     filenamepart := '' ;
     i := 1 ;
     while filename[i] <> '.' do
       begin
         filenamepart := filenamepart + filename[i] ;
         i := i + 1 ;
       end ;
     namefile := filenamepart + '.obp' ;
     assign (objectfile, namefile) ;
     rewrite(objectfile) ;
     namefile := filenamepart + '.lst' ;
     assign( listfile, namefile) ;
     rewrite(listfile) ;
     namefile := filenamepart + '.err' ;
     assign( errorfile, namefile) ;
     rewrite(errorfile) ;
     ShowErrors := false ;
     if paramcount > 1
       then
         if (paramstr(2) = 'v') or (paramstr(2) = 'V')
           then
             ShowErrors := true ;
   end ; (* OpenFiles *)

procedure CloseFiles ;
  begin
    close(sourcefile) ;
    close(objectfile) ;
    close(listfile) ;
    close(errorfile) ;
  end  ; (* CloseFiles *)

procedure DumpErrorFile ;
var
  line : string ;
begin
  assign( errorfile, namefile) ;
  reset(errorfile) ;
  while not eof(errorfile) do
    begin
      readln(errorfile, line) ;
      writeln(line)
    end;
  close(errorfile) ;
end;

begin (* main Mpascal *)
  writeln ( 'Pascal-M compiler V2k1') ;
  Openfiles ;
  if CompilePascalM(filename)
    then
      writeln('Compile OK')
     else
       writeln('Compile errors, see error file') ;
   CloseFiles ;
  if ShowErrors
    then
      DumpErrorfile ;
end.

