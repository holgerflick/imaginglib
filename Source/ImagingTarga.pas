{
  $Id: ImagingTarga.pas,v 1.10 2006/08/31 14:53:33 galfar Exp $
  Vampyre Imaging Library
  by Marek Mauder (pentar@seznam.cz)
  http://imaginglib.sourceforge.net

  The contents of this file are used with permission, subject to the Mozilla
  Public License Version 1.1 (the "License"); you may not use this file except
  in compliance with the License. You may obtain a copy of the License at
  http://www.mozilla.org/MPL/MPL-1.1.html

  Software distributed under the License is distributed on an "AS IS" basis,
  WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for
  the specific language governing rights and limitations under the License.

  Alternatively, the contents of this file may be used under the terms of the
  GNU Lesser General Public License (the  "LGPL License"), in which case the
  provisions of the LGPL License are applicable instead of those above.
  If you wish to allow use of your version of this file only under the terms
  of the LGPL License and not to allow others to use your version of this file
  under the MPL, indicate your decision by deleting  the provisions above and
  replace  them with the notice and other provisions required by the LGPL
  License.  If you do not delete the provisions above, a recipient may use
  your version of this file under either the MPL or the LGPL License.

  For more information about the LGPL: http://www.gnu.org/copyleft/lesser.html
}

{ This unit contains image format loader/saver for Targa images.}
unit ImagingTarga;

{$I ImagingOptions.inc}

interface

uses
  ImagingTypes, Imaging, ImagingFormats, ImagingUtility;

type
  { Class for loading and saving Truevision Targa images.
    It can load/save 8bit indexed or grayscale, 16 bit RGB or grayscale,
    24 bit RGB and 32 bit ARGB images with or without RLE compression.}
  TTargaFileFormat = class(TImageFileFormat)
  protected
    { Controls that RLE compression is used during saving. Accessible trough
      ImagingTargaRLE option.}
    FUseRLE: LongBool;
    function GetSupportedFormats: TImageFormats; override;
    procedure LoadData(Handle: TImagingHandle; var Images: TDynImageDataArray;
      OnlyFirstLevel: Boolean); override;
    procedure SaveData(Handle: TImagingHandle; const Images: TDynImageDataArray;
      Index: LongInt); override;
    function MakeCompatible(const Image: TImageData; var Comp: TImageData): Boolean; override;
  public
    constructor Create; override;
    function TestFormat(Handle: TImagingHandle): Boolean; override;
  end;

const
  STargaExtensions = 'tga';
  STargaFormatName = 'Truevision Targa Image';
  TargaSupportedFormats: TImageFormats = [ifIndex8, ifGray8, ifA1R5G5B5,
    ifR8G8B8, ifA8R8G8B8];
  TargaDefaultRLE = False;  

implementation

const
  STargaSignature = 'TRUEVISION-XFILE';

type
  { Targa file header.}
  TTargaHeader = packed record
    IDLength: Byte;
    ColorMapType: Byte;
    ImageType: Byte;
    ColorMapOff: Word;
    ColorMapLength: Word;
    ColorEntrySize: Byte;
    XOrg: SmallInt;
    YOrg: SmallInt;
    Width: SmallInt;
    Height: SmallInt;
    PixelSize: Byte;
    Desc: Byte;
  end;

  { Footer at the end of TGA file.}
  TTargaFooter = packed record
    ExtOff: LongWord;                 // Extension Area Offset
    DevDirOff: LongWord;              // Developer Directory Offset
    Signature: array[0..15] of Char;  // TRUEVISION-XFILE
    Reserved: Byte;                   // ASCII period '.'
    NullChar: Byte;                   // 0
  end;


{ TTargaFileFormat class implementation }

constructor TTargaFileFormat.Create;
begin
  inherited Create;
  FName := STargaFormatName;
  FCanLoad := True;
  FCanSave := True;
  FIsMultiImageFormat := False;

  FUseRLE := TargaDefaultRLE;

  AddExtensions(STargaExtensions);
  RegisterOption(ImagingTargaRLE, @FUseRLE);
end;

function TTargaFileFormat.GetSupportedFormats: TImageFormats;
begin
  Result := TargaSupportedFormats;
end;

procedure TTargaFileFormat.LoadData(Handle: TImagingHandle;
  var Images: TDynImageDataArray; OnlyFirstLevel: Boolean);
var
  Hdr: TTargaHeader;
  Foo: TTargaFooter;
  FooterFound, ExtFound: Boolean;
  I, PSize, PalSize: LongWord;
  Pal: Pointer;
  FmtInfo: PImageFormatInfo;
  WordValue: Word;

  procedure LoadRLE;
  var
    I, CPixel, Cnt: LongInt;
    Bpp, Rle: Byte;
    Buffer, Dest, Src: PByte;
    BufSize: LongInt;
  begin
    with GetIO, Images[0] do
    begin
      // allocates buffer large enough to hold the worst case
      // RLE compressed data and reads then from input
      BufSize := Width * Height * FmtInfo.BytesPerPixel;
      BufSize := BufSize + BufSize div 2 + 1;
      GetMem(Buffer, BufSize);
      Src := Buffer;
      Dest := Bits;
      BufSize := Read(Handle, Buffer, BufSize);

      Cnt := Width * Height;
      Bpp := FmtInfo.BytesPerPixel;
      CPixel := 0;
      while CPixel < Cnt do
      begin
        Rle := Src^;
        Inc(Src);
        if Rle < 128 then
        begin
          // process uncompressed pixel
          Rle := Rle + 1;
          CPixel := CPixel + Rle;
          for I := 0 to Rle - 1 do
          begin
            // copy pixel from src to dest
            case Bpp of
              1: Dest^ := Src^;
              2: PWord(Dest)^ := PWord(Src)^;
              3: PColor24Rec(Dest)^ := PColor24Rec(Src)^;
              4: PLongWord(Dest)^ := PLongWord(Src)^;
            end;
            Inc(Src, Bpp);
            Inc(Dest, Bpp);
          end;
        end
        else
        begin
          // process compressed pixels
          Rle := Rle - 127;
          CPixel := CPixel + Rle;
          // copy one pixel from src to dest (many times there)
          for I := 0 to Rle - 1 do
          begin
            case Bpp of
              1: Dest^ := Src^;
              2: PWord(Dest)^ := PWord(Src)^;
              3: PColor24Rec(Dest)^ := PColor24Rec(Src)^;
              4: PLongWord(Dest)^ := PLongWord(Src)^;
            end;
            Inc(Dest, Bpp);
          end;
          Inc(Src, Bpp);
        end;
      end;
      // set position in source to real end of compressed data
      Seek(Handle, -(BufSize - LongInt(LongWord(Src) - LongWord(Buffer))),
        smFromCurrent);
      FreeMem(Buffer);
    end;
  end;

begin
  SetLength(Images, 1);
  with GetIO, Images[0] do
  begin
    // read targa header
    Read(Handle, @Hdr, SizeOf(Hdr));
    // skip image ID info
    Seek(Handle, Hdr.IDLength, smFromCurrent);
    // determine image format
    Format := ifUnknown;
    case Hdr.ImageType of
      1, 9: Format := ifIndex8;
      2, 10: case Hdr.PixelSize of
          15: Format := ifX1R5G5B5;
          16: Format := ifA1R5G5B5;
          24: Format := ifR8G8B8;
          32: Format := ifA8R8G8B8;
        end;
      3, 11: Format := ifGray8;
    end;
    // format was not assigned by previous testing (it should be in
    // well formed targas), so formats which reflects bit dept are selected
    if Format = ifUnknown then
      case Hdr.PixelSize of
        8: Format := ifGray8;
        15: Format := ifX1R5G5B5;
        16: Format := ifA1R5G5B5;
        24: Format := ifR8G8B8;
        32: Format := ifA8R8G8B8;
      end;
    NewImage(Hdr.Width, Hdr.Height, Format, Images[0]);
    FmtInfo := GetFormatInfo(Format);

    if (Hdr.ColorMapType = 1) and (Hdr.ImageType in [1, 9]) then
    begin
      // read palette
      PSize := Hdr.ColorMapLength * (Hdr.ColorEntrySize shr 3);
      GetMem(Pal, PSize);
      Read(Handle, Pal, PSize);
      // process palette
      PalSize := Iff(Hdr.ColorMapLength > FmtInfo.PaletteEntries,
        FmtInfo.PaletteEntries, Hdr.ColorMapLength);
      for I := 0 to PalSize - 1 do
        case Hdr.ColorEntrySize of
          24:
            with Palette[I] do
            begin
              A := $FF;
              R := PPalette24(Pal)[I].R;
              G := PPalette24(Pal)[I].G;
              B := PPalette24(Pal)[I].B;
            end;
          // I've never seen tga with these palettes so they are untested
          16:
            with Palette[I] do
            begin
              A := (PWordArray(Pal)[I] and $8000) shr 12;
              R := (PWordArray(Pal)[I] and $FC00) shr 7;
              G := (PWordArray(Pal)[I] and $03E0) shr 2;
              B := (PWordArray(Pal)[I] and $001F) shl 3;
            end;
          32:
            with Palette[I] do
            begin
              A := PPalette32(Pal)[I].A;
              R := PPalette32(Pal)[I].R;
              G := PPalette32(Pal)[I].G;
              B := PPalette32(Pal)[I].B;
            end;
        end;
      FreeMemNil(Pal);
    end;

    case Hdr.ImageType of
      0, 1, 2, 3:
        // load uncompressed mode images
        Read(Handle, Bits, Size);
      9, 10, 11:
        // load RLE compressed mode images
        LoadRLE;
    end;

    // check if there is alpha channel present in A1R5GB5 images, if it is not
    // change format to X1R5G5B5
    if Format = ifA1R5G5B5 then
    begin
      if not Has16BitImageAlpha(Width * Height, Bits) then
        Format := ifX1R5G5B5;
    end;

    // we must find true end of file and set input' position to it
    // paint programs appends extra info at the end of Targas
    // some of them multiple times (PSP Pro 8)
    repeat
      ExtFound := False;
      FooterFound := False;

      if Read(Handle, @WordValue, 2) = 2 then
      begin
        // 495 = size of Extension Area
        if WordValue = 495 then
        begin
          Seek(Handle, 493, smFromCurrent);
          ExtFound := True;
        end
        else
          Seek(Handle, -2, smFromCurrent);
      end;

      if Read(Handle, @Foo, SizeOf(Foo)) = SizeOf(Foo) then
      begin
        if Foo.Signature = STargaSignature then
          FooterFound := True
        else
          Seek(Handle, -SizeOf(Foo), smFromCurrent);
      end;
    until (not ExtFound) and (not FooterFound);

    // some editors save targas flipped
    if Hdr.Desc < 31 then
      FlipImage(Images[0]);
  end;
end;

procedure TTargaFileFormat.SaveData(Handle: TImagingHandle;
  const Images: TDynImageDataArray; Index: Integer);
var
  Len, I: LongInt;
  Hdr: TTargaHeader;
  FmtInfo: PImageFormatInfo;
  Pal: PPalette24;
  ImageToSave: TImageData;

  procedure SaveRLE;
  var
    Dest: PByte;
    WidthBytes, Written, I, Total, DestSize: LongInt;

    function CountDiff(Data: PByte; Bpp, PixelCount: Longint): LongInt;
    var
      Pixel: LongWord;
      NextPixel: LongWord;
      N: LongInt;
    begin
      N := 0;
      Pixel := 0;
      NextPixel := 0;
      if PixelCount = 1 then
      begin
        Result := PixelCount;
        Exit;
      end;
      case Bpp of
        1: Pixel := Data^;
        2: Pixel := PWord(Data)^;
        3: PColor24Rec(@Pixel)^ := PColor24Rec(Data)^;
        4: Pixel := PLongWord(Data)^;
      end;
      while PixelCount > 1 do
      begin
        Inc(Data, Bpp);
        case Bpp of
          1: NextPixel := Data^;
          2: NextPixel := PWord(Data)^;
          3: PColor24Rec(@NextPixel)^ := PColor24Rec(Data)^;
          4: NextPixel := PLongWord(Data)^;
        end;
        if NextPixel = Pixel then
          Break;
        Pixel := NextPixel;
        N := N + 1;
        PixelCount := PixelCount - 1;
      end;
      if NextPixel = Pixel then
        Result := N
      else
        Result := N + 1;
    end;

    function CountSame(Data: PByte; Bpp, PixelCount: LongInt): LongInt;
    var
      Pixel: LongWord;
      NextPixel: LongWord;
      N: LongInt;
    begin
      N := 1;
      Pixel := 0;
      NextPixel := 0;
      case Bpp of
        1: Pixel := Data^;
        2: Pixel := PWord(Data)^;
        3: PColor24Rec(@Pixel)^ := PColor24Rec(Data)^;
        4: Pixel := PLongWord(Data)^;
      end;
      PixelCount := PixelCount - 1;
      while PixelCount > 0 do
      begin
        Inc(Data, Bpp);
        case Bpp of
          1: NextPixel := Data^;
          2: NextPixel := PWord(Data)^;
          3: PColor24Rec(@NextPixel)^ := PColor24Rec(Data)^;
          4: NextPixel := PLongWord(Data)^;
        end;
        if NextPixel <> Pixel then
          Break;
        N := N + 1;
        PixelCount := PixelCount - 1;
      end;
      Result := N;
    end;

    procedure RleCompressLine(Data: PByte; PixelCount, Bpp: LongInt; Dest:
      PByte; var Written: LongInt);
    const
      MaxRun = 128;
    var
      DiffCount: LongInt;
      SameCount: LongInt;
      RleBufSize: LongInt;
    begin
      RleBufSize := 0;
      while PixelCount > 0 do
      begin
        DiffCount := CountDiff(Data, Bpp, PixelCount);
        SameCount := CountSame(Data, Bpp, PixelCount);
        if (DiffCount > MaxRun) then
          DiffCount := MaxRun;
        if (SameCount > MaxRun) then
          SameCount := MaxRun;
        if (DiffCount > 0) then
        begin
          Dest^ := Byte(DiffCount - 1);
          Inc(Dest);
          PixelCount := PixelCount - DiffCount;
          RleBufSize := RleBufSize + (DiffCount * Bpp) + 1;
          Move(Data^, Dest^, DiffCount * Bpp);
          Inc(Data, DiffCount * Bpp);
          Inc(Dest, DiffCount * Bpp);
        end;
        if SameCount > 1 then
        begin
          Dest^ := Byte((SameCount - 1) or $80);
          Inc(Dest);
          PixelCount := PixelCount - SameCount;
          RleBufSize := RleBufSize + Bpp + 1;
          Inc(Data, (SameCount - 1) * Bpp);
          case Bpp of
            1: Dest^ := Data^;
            2: PWord(Dest)^ := PWord(Data)^;
            3: PColor24Rec(Dest)^ := PColor24Rec(Data)^;
            4: PLongWord(Dest)^ := PLongWord(Data)^;
          end;
          Inc(Data, Bpp);
          Inc(Dest, Bpp);
        end;
      end;
      Written := RleBufSize;
    end;

  begin
    with ImageToSave do
    begin
      // allocate enough space to hold the worst case compression
      // result and then compress source's scanlines
      WidthBytes := Width * FmtInfo.BytesPerPixel;
      DestSize := WidthBytes * Height;
      DestSize := DestSize + DestSize div 2 + 1;
      GetMem(Dest, DestSize);
      Total := 0;
      for I := 0 to Height - 1 do
      begin
        RleCompressLine(@PByteArray(Bits)[I * WidthBytes], Width,
          FmtInfo.BytesPerPixel, @PByteArray(Dest)[Total], Written);
        Total := Total + Written;
      end;
      GetIO.Write(Handle, Dest, Total);
      FreeMem(Dest);
    end;
  end;

begin
  Len := Length(Images);
  if Len = 0 then
    Exit;
  if (Index = MaxInt) or (Len = 1) then
    Index := 0;
  if MakeCompatible(Images[Index], ImageToSave) then
  with GetIO, ImageToSave do
  try
    FmtInfo := GetFormatInfo(Format);
    // fill targa header
    FillChar(Hdr, SizeOf(Hdr), 0);
    Hdr.IDLength := 0;
    Hdr.ColorMapType := Iff(FmtInfo.PaletteEntries > 0, 1, 0);
    Hdr.Width := Width;
    Hdr.Height := Height;
    Hdr.PixelSize := FmtInfo.BytesPerPixel * 8;
    Hdr.ColorMapLength := fmtInfo.PaletteEntries;
    Hdr.ColorEntrySize := Iff(FmtInfo.PaletteEntries > 0, 24, 0);
    Hdr.ColorMapOff := 0;
    // this indicates that targa is stored in top-left format
    // as our images -> no flipping is needed.
    Hdr.Desc := 32;

    // choose image type
    if FmtInfo.IsIndexed then
      Hdr.ImageType := Iff(FUseRLE, 9, 1)
    else
      if FmtInfo.HasGrayChannel then
        Hdr.ImageType := Iff(FUseRLE, 11, 3)
      else
        Hdr.ImageType := Iff(FUseRLE, 10, 2);

    Write(Handle, @Hdr, SizeOf(Hdr));

    // write palette
    if FmtInfo.PaletteEntries > 0 then
    begin
      GetMem(Pal, FmtInfo.PaletteEntries * SizeOf(TColor24Rec));
      for I := 0 to FmtInfo.PaletteEntries - 1 do
        with Pal[I] do
        begin
          R := Palette[I].R;
          G := Palette[I].G;
          B := Palette[I].B;
        end;
      Write(Handle, Pal, FmtInfo.PaletteEntries * SizeOf(TColor24Rec));
      FreeMem(Pal);
    end;

    if FUseRLE then
      SaveRLE //save rle compressed mode images
    else
      Write(Handle, Bits, Size); //save uncompressed mode images
  finally
    if Images[Index].Bits <> ImageToSave.Bits then
      FreeImage(ImageToSave);
  end;
end;

function TTargaFileFormat.MakeCompatible(const Image: TImageData;
  var Comp: TImageData): Boolean;
var
  Info: PImageFormatInfo;
  ConvFormat: TImageFormat;
begin
  if not inherited MakeCompatible(Image, Comp) then
  begin
    Info := GetFormatInfo(Comp.Format);
    if Info.HasGrayChannel then
      // convert all grayscale images to Gray8
      ConvFormat := ifGray8
    else
      if Info.IsIndexed then
        // convert all indexed images to Index8
        ConvFormat := ifIndex8
      else
        if Info.HasAlphaChannel then
          // convert images with alpha channel to A8R8G8B8
          ConvFormat := ifA8R8G8B8
        else
          if Info.UsePixelFormat then
            // convert 16bit images (without alpha channel) to A1R5G5B5
            ConvFormat := ifA1R5G5B5
          else
            // convert all other formats to R8G8B8
            ConvFormat := ifR8G8B8;

      ConvertImage(Comp, ConvFormat);
  end;
  Result := Comp.Format in GetSupportedFormats;
end;

function TTargaFileFormat.TestFormat(Handle: TImagingHandle): Boolean;
var
  Hdr: TTargaHeader;
  ReadCount: LongInt;
begin
  Result := False;
  if Handle <> nil then
    with GetIO do
    begin
      ReadCount := Read(Handle, @Hdr, SizeOf(Hdr));
      Seek(Handle, -ReadCount, smFromCurrent);
      Result := (Hdr.ImageType in [0, 1, 2, 3, 9, 10, 11]) and
        (Hdr.PixelSize in [1, 8, 15, 16, 24, 32]);
    end;
end;

initialization
  RegisterImageFileFormat(TTargaFileFormat);

{
  File Notes:

 -- TODOS ----------------------------------------------------
    - nothing now

  -- 0.17 Changes/Bug Fixes -----------------------------------
    - 16 bit images are usually without alpha but some has alpha
      channel and there is no indication of it - so I have added
      a check: if all pixels of image are with alpha = 0 image is treated
      as X1R5G5B5 otherwise as A1R5G5B5
    - fixed problems with some nonstandard 15 bit images
}

end.

