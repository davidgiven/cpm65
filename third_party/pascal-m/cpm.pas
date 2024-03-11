unit cpm;

interface

type
    charp = ^char;

procedure GetCommandLine(var commandLine: packed array of char);
procedure release(p: charp);

implementation
    procedure GetCommandLine(var commandLine: packed array of char);
    var
        s: ShortString;
        i: integer;
    begin
        s := '';
        for i := 1 to ParamCount do
        begin
            if i <> 1 then
                s := s + ' ';
            s := s + ParamStr(i);
        end;

        commandLine[0] := chr(Length(s));
        for i := 0 to Length(s)-1 do
            commandLine[i+1] := s[i+1];
    end;

    procedure release(p: charp);
    begin
    end;
end.

