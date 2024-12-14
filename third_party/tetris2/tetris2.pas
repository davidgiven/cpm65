(* Simple Tetris in the terminal, for CP/M 2.2 Apple ][ *)
(* A.Baumann, 13.12.2024, 0BSD clause *)

PROGRAM Tetris;

CONST
  Delay = 20;
  BoardHeight = 20;
  BoardWidth = 10;
  NofShapes = 5;
  Shapes : ARRAY[0..4,0..3,0..3] OF Byte =
   (((0,0,0,0),(1,1,1,1),(0,0,0,0),(0,0,0,0)),   (* I *)
    ((0,1,1,0),(0,1,1,0),(0,0,0,0),(0,0,0,0)),   (* O *)
    ((0,1,0,0),(1,1,1,0),(0,0,0,0),(0,0,0,0)),   (* T *)
    ((0,0,1,0),(1,1,1,0),(0,0,0,0),(0,0,0,0)),   (* L *)
    ((1,1,0,0),(0,1,1,0),(0,0,0,0),(0,0,0,0)));  (* Z *)

VAR
  Board : ARRAY[1..BoardHeight,1..BoardWidth] OF Byte;
  GameOver : Boolean;
  CurrentPiece : Integer;
  CurrentRotation : Integer;
  PosX, PosY : Integer;

PROCEDURE InitializeBoard;
BEGIN
  FillChar(Board,SizeOf(Board),0)
END;

PROCEDURE DrawBoard;
VAR
  x, y : Integer;
BEGIN
  FOR y := 1 TO BoardHeight DO
  BEGIN
    FOR x := 1 TO BoardWidth DO
    BEGIN
      GotoXY(x,y);
      IF Board[y,x] = 1 THEN
        Write('#')
      ELSE
        Write('.')
    END
  END
END;

PROCEDURE DrawPiece(Erase : Boolean);
VAR
  x, y : Integer;
BEGIN
  FOR y := 0 TO 3 DO
    FOR x := 0 TO 3 DO
      IF Shapes[CurrentPiece,y,x] = 1 THEN
      BEGIN
        GotoXY(PosX+x,PosY+y);
        IF Erase THEN
          Write('.')
        ELSE
          Write('#')
      END
END;

FUNCTION ReadKey : Char;
BEGIN
  ReadKey := Chr(BDOS(6,$FF))
END;

FUNCTION CanMove(dx, dy : Integer) : Boolean;
VAR
  x, y : Integer;
BEGIN
  CanMove := True;
  FOR y := 0 TO 3 DO
    FOR x := 0 TO 3 DO
      IF Shapes[CurrentPiece,y,x] = 1 THEN
      BEGIN
        IF (PosX+x+dx<1) OR (PosX+x+dx>BoardWidth) OR
           (PosY+y+dy>BoardHeight) OR
           (Board[PosY+y+dy,PosX+x+dx]=1) THEN
           BEGIN
             CanMove := False;
             Exit
           END
      END
END;

PROCEDURE NewPiece;
BEGIN
  CurrentPiece := Random(NofShapes);
  CurrentRotation := 0;
  PosX := (BoardWidth div 2)-2;
  PosY := 1;
  IF NOT CanMove(0,0) THEN
    GameOver := True
END;

PROCEDURE RotatePiece;
VAR
  Temp : ARRAY[0..3,0..3] OF Byte;
  x, y : Integer;
BEGIN
  FOR y := 0 TO 3 DO
    FOR x := 0 TO 3 DO
      Temp[y,x] := Shapes[CurrentPiece,3-x,y];
  IF CanMove(0,0) THEN
    FOR y := 0 TO 3 DO
      FOR x := 0 TO 3 DO
        Shapes[CurrentPiece,y,x] := Temp[y,x];
END;

PROCEDURE PlacePiece;
VAR
  x, y : Integer;
BEGIN
  FOR y := 0 TO 3 DO
    FOR x := 0 TO 3 DO
      IF Shapes[CurrentPiece,y,x] = 1 THEN
        Board[PosY+y,PosX+x] := 1
END;

PROCEDURE ClearLines;
VAR
  x, y, ny : Integer;
  Full : Boolean;
  Redraw : Boolean;
BEGIN
  Redraw := False;
  FOR y := BoardHeight DOWNTO 1 DO
  BEGIN
    Full := True;
    FOR x := 1 TO BoardWidth DO
      IF Board[y,x] = 0 THEN
      BEGIN
        Full := False
      END;
    IF Full THEN
    BEGIN
      FOR ny := y DOWNTO 2 DO
        FOR x := 1 TO BoardWidth DO
          Board[ny,x] := Board[ny-1,x];
      FOR X := 1 TO BoardWidth DO
        Board[1,x] := 0;
      Redraw := True
    END
  END;
  IF Redraw THEN
    DrawBoard
END;

PROCEDURE HandleInput;
VAR
  c : Char;
  i, j : Integer;
BEGIN
  i := 0;
  WHILE NOT KeyPressed AND (i<Delay) DO
    BEGIN
    i := i+1;
    Delay(10)
  END;
  IF KeyPressed THEN
  BEGIN
    c := Upcase(ReadKey);
    CASE c OF
      'A':
        IF CanMove(-1,0) THEN
        BEGIN
          DrawPiece(True);
          PosX := PosX-1;
          DrawPiece(False)
        END;
      'D':
        IF CanMove(1,0) THEN
        BEGIN
          DrawPiece(True);
          PosX := PosX+1;
          DrawPiece(False)
        END;
      'S':
        IF CanMove(0,1) THEN
        BEGIN
          DrawPiece(True);
          PosY := PosY+1;
          DrawPiece(False)
        END;
      ' ':
        WHILE CanMove(0,1) DO
        BEGIN
          DrawPiece(True);
          PosY := PosY+1;
          DrawPiece(False)
        END;
      'W':
        BEGIN
          DrawPiece(True);
          RotatePiece;
          DrawPiece(False)
        END;
      'Q':
        GameOver := True;
    END
  END;
  FOR j := i TO Delay DO
  BEGIN
    j := j+1;
    Delay(10)
  END
END;

BEGIN
  Randomize;
  InitializeBoard;
  CrtInit;
  ClrScr;
  DrawBoard;
  GameOver := False;
  NewPiece;
  WHILE NOT GameOver DO
  BEGIN
    DrawPiece(False);
    HandleInput;
    IF CanMove(0,1) THEN
    BEGIN
      DrawPiece(True);
      PosY := PosY+1;
      DrawPiece(False)
    END
    ELSE
    BEGIN
      PlacePiece;
      ClearLines;
      NewPiece;
    END;
    IF PosY >= BoardHeight THEN
      GameOver := True;
  END;
  ClrScr;
  WriteLn('Thanks for playing.');
  CrtExit;
END.
