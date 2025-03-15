unit PCDImage;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Description:	Reader for PCD images                                         //
// Version:	0.1                                                           //
// Date:	15-MARC-2025                                                  //
// License:     MIT                                                           //
// Target:	Win64, Free Pascal, Delphi                                    //
// Copyright:	(c) 2025 Xelitan.com.                                         //
//		All rights reserved.                                          //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

interface

uses Classes, Graphics, SysUtils, Math, Types, Dialogs;

  { TPCDImage }
type
  TPCDImage = class(TGraphic)
  private
    FBmp: TBitmap;
    FCompression: Integer;
    procedure DecodeFromStream(Str: TStream);
    procedure EncodeToStream(Str: TStream);
  protected
    procedure Draw(ACanvas: TCanvas; const Rect: TRect); override;
  //    function GetEmpty: Boolean; virtual; abstract;
    function GetHeight: Integer; override;
    function GetTransparent: Boolean; override;
    function GetWidth: Integer; override;
    procedure SetHeight(Value: Integer); override;
    procedure SetTransparent(Value: Boolean); override;
    procedure SetWidth(Value: Integer);override;
  public
    procedure SetLossyCompression(Value: Cardinal);
    procedure SetLosslessCompression;
    procedure Assign(Source: TPersistent); override;
    procedure LoadFromStream(Stream: TStream); override;
    procedure SaveToStream(Stream: TStream); override;
    constructor Create; override;
    destructor Destroy; override;
  end;

implementation

{ TPCDImage }


procedure YUV2RGB(Y, Cb, Cr: Integer; out R, G, B: Byte);

  function Clamp(Value: Double): Integer;
  begin
    Result := Round(Value);
    if Result < 0 then Result := 0
    else if Result > 255 then Result := 255;
  end;

var c11, c12, c13: Double;
    c21, c22, c23: Double;
    c31, c32, c33: Double;
begin
  c11 := 0.0054980  * 256.0;
  c12 := 0.0000001  * 256.0;
  c13 := 0.0051681  * 256.0;

  c21 := 0.0054980  * 256.0;
  c22 := -0.0015446 * 256.0;
  c23 := -0.0026325 * 256.0;

  c31 := 0.0054980  * 256.0;
  c32 := 0.0079533  * 256.0;
  c33 := 0.0000001  * 256.0;

  R := Clamp(c11 * Y + c12 * (Cb - 156) + c13 * (Cr - 137));
  G := Clamp(c21 * Y + c22 * (Cb - 156) + c23 * (Cr - 137));
  B := Clamp(c31 * Y + c32 * (Cb - 156) + c33 * (Cr - 137));
end;

type TRGBTriple = record
      B,G,R,A: Byte;
     end;
     TRGBArray = array[0..0] of TRGBTriple;
     pRGBArray = ^TRGBArray;

procedure Rotate90(Bmp: TBitmap);
var  RowOld, ColOld: Integer;
     LineOld, LineNew: pRGBArray;
     Tmp: TBitmap;
begin
  Tmp := TBitmap.Create;
  Tmp.PixelFormat := pf32bit;
  Tmp.SetSize(Bmp.Height, Bmp.Width);

  for ColOld := 0 to Bmp.Width - 1 do begin
    LineNew := Tmp.ScanLine[ColOld];

    for RowOld := 0 to Bmp.Height - 1 do begin
      LineOld := Bmp.ScanLine[RowOld];
      LineNew[Bmp.Height - RowOld - 1] := LineOld[ColOld];
    end;
  end;

  Bmp.Assign(Tmp);
  Tmp.Free;
end;

procedure Rotate180(Bmp: TBitmap);
var RowOld, ColOld: integer;
    LineOld,LineNew: pRGBArray;
    Tmp: TBitmap;
begin
  Tmp := TBitmap.Create;
  Tmp.PixelFormat := pf32bit;
  Tmp.SetSize(Bmp.Width, Bmp.Height);

  for RowOld:=0 to Bmp.Height-1 do begin
    LineOld := Bmp.ScanLine[RowOld];
    LineNew := Tmp.ScanLine[Bmp.Height - RowOld - 1];

    for ColOld := 0 to Bmp.Width - 1 do
      LineNew[Bmp.Width - ColOld - 1] := LineOld[ColOld];
  end;

  Bmp.Assign(Tmp);
  Tmp.Free;
end;

procedure Rotate270(Bmp: TBitmap);
var RowOld, ColOld: integer;
    LineOld, LineNew: pRGBArray;
    Tmp: TBitmap;
begin
  Tmp := TBitmap.Create;
  Tmp.PixelFormat := pf32bit;
  Tmp.SetSize(Bmp.Height, Bmp.Width);

  for ColOld:=0 to Bmp.Width-1 do begin
    LineNew := Tmp.ScanLine[ColOld];

    for RowOld:=0 to Bmp.Height-1 do begin
      LineOld := Bmp.ScanLine[RowOld];
      LineNew[RowOld] := LineOld[Bmp.Width - ColOld - 1];
    end;
  end;

  Bmp.Assign(Tmp);
  Tmp.Free;
end;

procedure TPCDImage.DecodeFromStream(Str: TStream);
var Buf: TBytes;
    yy: array of array of Byte;
    cbcr: array of Byte;
    R,G,B: Byte;
    P: PByteArray;
    Line: PByte;
    i,x,y: Integer;
    Magic: array[0..2] of Char;
    Rotate: Byte;
begin
 SetLength(Buf, Str.Size);
 Str.Read(Buf[0], Str.Size);

 Line := @Buf[0];

 Inc(Line, $800);
 Move(Line^, Magic[0], 3);
 Dec(Line, $800); //undo set offset

 Rotate := (Line + $0E02)^ and 3;

 Inc(Line, $30000);
 FBmp.SetSize(768, 512);

 for y:=0 to Ceil(FBmp.Height/2)-1 do begin
   SetLength(yy, 2, FBmp.Width);
   SetLength(cbcr, FBmp.Width);

   Move(Line^, yy[0][0], FBmp.Width);
   Inc(Line, FBmp.Width);
   Move(Line^, yy[1][0], FBmp.Width);
   Inc(Line, FBmp.Width);
   Move(Line^, cbcr[0], FBmp.Width);
   Inc(Line, FBmp.Width);

   for i:=0 to 1 do begin
     P := FBmp.Scanline[2*y+i];

     for x:=0 to FBmp.Width-1 do begin

  	YUV2RGB(yy[i][x], cbcr[x div 2], cbcr[(FBmp.width div 2) + (x div 2)], R, G, B);

        P[4*x  ] := B;
        P[4*x+1] := G;
        P[4*x+2] := R;
     end;
   end;
 end;

 case Rotate of
  1: Rotate270(FBmp);
  2: Rotate180(FBmp);
  3: Rotate90(FBmp);
 end;
end;

procedure TPCDImage.EncodeToStream(Str: TStream);
begin
//
end;

procedure TPCDImage.Draw(ACanvas: TCanvas; const Rect: TRect);
begin
  ACanvas.StretchDraw(Rect, FBmp);
end;

function TPCDImage.GetHeight: Integer;
begin
  Result := FBmp.Height;
end;

function TPCDImage.GetTransparent: Boolean;
begin
  Result := False;
end;

function TPCDImage.GetWidth: Integer;
begin
  Result := FBmp.Width;
end;

procedure TPCDImage.SetHeight(Value: Integer);
begin
  FBmp.Height := Value;
end;

procedure TPCDImage.SetTransparent(Value: Boolean);
begin
  //
end;

procedure TPCDImage.SetWidth(Value: Integer);
begin
  FBmp.Width := Value;
end;

procedure TPCDImage.SetLossyCompression(Value: Cardinal);
begin
  FCompression := Value;
end;

procedure TPCDImage.SetLosslessCompression;
begin
  FCompression := 0;
end;

procedure TPCDImage.Assign(Source: TPersistent);
var Src: TGraphic;
begin
  if source is tgraphic then begin
    Src := Source as TGraphic;
    FBmp.SetSize(Src.Width, Src.Height);
    FBmp.Canvas.Draw(0,0, Src);
  end;
end;

procedure TPCDImage.LoadFromStream(Stream: TStream);
begin
  DecodeFromStream(Stream);
end;

procedure TPCDImage.SaveToStream(Stream: TStream);
begin
  EncodeToStream(Stream);
end;

constructor TPCDImage.Create;
begin
  inherited Create;

  FBmp := TBitmap.Create;
  FBmp.PixelFormat := pf32bit;
  FBmp.SetSize(1,1);
  FCompression := 0;
end;

destructor TPCDImage.Destroy;
begin
  FBmp.Free;
  inherited Destroy;
end;

initialization
  TPicture.RegisterFileFormat('PCD','PCD Image', TPCDImage);

finalization
  TPicture.UnregisterGraphicClass(TPCDImage);

end.
