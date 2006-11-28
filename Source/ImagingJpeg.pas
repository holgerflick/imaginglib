{
  $Id$
  Vampyre Imaging Library
  by Marek Mauder 
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

{ This unit contains image format loader/saver for Jpeg images.}
unit ImagingJpeg;

{$I ImagingOptions.inc}

{ You can choose which Pascal JpegLib implementation will be used.
  IMJPEGLIB is version bundled with Imaging which works with all supported
  compilers and platforms.
  PASJPEG is original JpegLib translation or version modified for FPC
  (and shipped with it). You can use PASJPEG if this version is already
  linked with another part of your program and you don't want to have
  two quite large almost the same libraries linked to your exe.
  This is the case with Lazarus applications for example.}

{$DEFINE IMJPEGLIB}
{ $DEFINE PASJPEG}

interface

uses
  SysUtils, ImagingTypes, Imaging,
{$IFDEF IMJPEGLIB}
  imjpeglib, imjmorecfg, imjcomapi, imjdapimin,
  imjdapistd, imjcapimin, imjcapistd, imjdmarker, imjcparam,
{$ENDIF}
{$IFDEF PASJPEG}
  jpeglib, jmorecfg, jcomapi, jdapimin,
  jdapistd, jcapimin, jcapistd, jdmarker, jcparam,
{$ENDIF}
  ImagingUtility;

{$IF Defined(FPC) and Defined(PASJPEG)}
  { When using FPC's pasjpeg in FPC the channel order is BGR instead of RGB}
  {$DEFINE RGBSWAPPED}
{$IFEND}

type
  { Class for loading/saving Jpeg images. Supports load/save of
    8 bit grayscale and 24 bit RGB images.}
  TJpegFileFormat = class(TImageFileFormat)
  private
    FGrayScale: Boolean;
  protected
    { Controls Jpeg save compression quality. It is number in range 1..100.
      1 means small/ugly file, 100 means large/nice file. Accessible trough
      ImagingJpegQuality option.}
    FQuality: LongInt;
    { If True Jpeg images are saved in progressive format. Accessible trough
      ImagingJpegProgressive option.}
    FProgressive: LongBool;
    procedure SetJpegIO(const JpegIO: TIOFunctions); virtual;
    function GetSupportedFormats: TImageFormats; override;
    procedure LoadData(Handle: TImagingHandle; var Images: TDynImageDataArray;
      OnlyFirstLevel: Boolean); override;
    function SaveData(Handle: TImagingHandle; const Images: TDynImageDataArray;
      Index: LongInt): Boolean; override;
    function MakeCompatible(const Image: TImageData; var Comp: TImageData;
      out MustBeFreed: Boolean): Boolean; override;
  public
    constructor Create; override;
    function TestFormat(Handle: TImagingHandle): Boolean; override;
  end;

const
  SJpegFormatName = 'Joint Photographic Experts Group Image';
  SJpegMasks      = '*.jpg,*.jpeg,*.jfif,*.jpe,*.jif';
  JpegSupportedFormats: TImageFormats = [ifR8G8B8, ifGray8];
  JpegDefaultQuality = 90;
  JpegDefaultProgressive = False;

implementation

const
  { Jpeg file identifiers.}
  JpegMagic: TChar2 = #$FF#$D8;
  JFIFSignature: TChar4 = 'JFIF';
  EXIFSignature: TChar4 = 'Exif';
  BufferSize = 16384;

type
  TJpegContext = record
    case Byte of
      0: (common: jpeg_common_struct);
      1: (d: jpeg_decompress_struct);
      2: (c: jpeg_compress_struct);
  end;

  TSourceMgr = record
    Pub: jpeg_source_mgr;
    Input: TImagingHandle;
    Buffer: JOCTETPTR;
    StartOfFile: Boolean;
  end;
  PSourceMgr = ^TSourceMgr;

  TDestMgr = record
    Pub: jpeg_destination_mgr;
    Output: TImagingHandle;
    Buffer: JOCTETPTR;
  end;
  PDestMgr = ^TDestMgr;

var
  JIO: TIOFunctions;


{ Intenal unit jpeglib support functions }

procedure JpegError(CurInfo: j_common_ptr);
begin
end;

procedure EmitMessage(CurInfo: j_common_ptr; msg_level: Integer);
begin
end;

procedure OutputMessage(CurInfo: j_common_ptr);
begin
end;

procedure FormatMessage(CurInfo: j_common_ptr; var buffer: string);
begin
end;

procedure ResetErrorMgr(CurInfo: j_common_ptr);
begin
  CurInfo^.err^.num_warnings := 0;
  CurInfo^.err^.msg_code := 0;
end;

var
  JpegErrorRec: jpeg_error_mgr = (
    error_exit: JpegError;
    emit_message: EmitMessage;
    output_message: OutputMessage;
    format_message: FormatMessage;
    reset_error_mgr: ResetErrorMgr);

procedure ReleaseContext(var jc: TJpegContext);
begin
  if jc.common.err = nil then
    Exit;
  jpeg_destroy(@jc.common);
  jpeg_destroy_decompress(@jc.d);
  jpeg_destroy_compress(@jc.c);
  jc.common.err := nil;
end;

procedure InitSource(cinfo: j_decompress_ptr);
begin
  PSourceMgr(cinfo.src).StartOfFile := True;
end;

function FillInputBuffer(cinfo: j_decompress_ptr): Boolean;
var
  NBytes: LongInt;
  Src: PSourceMgr;
begin
  Src := PSourceMgr(cinfo.src);
  NBytes := JIO.Read(Src.Input, Src.Buffer, BufferSize);

  if NBytes <= 0 then
  begin
    PChar(Src.Buffer)[0] := #$FF;
    PChar(Src.Buffer)[1] := Char(JPEG_EOI);
    NBytes := 2;
  end;
  Src.Pub.next_input_byte := Src.Buffer;
  Src.Pub.bytes_in_buffer := NBytes;
  Src.StartOfFile := False;
  Result := True;
end;

procedure SkipInputData(cinfo: j_decompress_ptr; num_bytes: LongInt);
var
  Src: PSourceMgr;
begin
  Src := PSourceMgr(cinfo.src);
  if num_bytes > 0 then
  begin
    while num_bytes > Src.Pub.bytes_in_buffer do
    begin
      Dec(num_bytes, Src.Pub.bytes_in_buffer);
      FillInputBuffer(cinfo);
    end;
    Src.Pub.next_input_byte := @PByteArray(Src.Pub.next_input_byte)[num_bytes];
//    Inc(LongInt(Src.Pub.next_input_byte), num_bytes);
    Dec(Src.Pub.bytes_in_buffer, num_bytes);
  end;
end;

procedure TermSource(cinfo: j_decompress_ptr);
var
  Src: PSourceMgr;
begin
  Src := PSourceMgr(cinfo.src);
  // Move stream position back just after EOI marker so that more that one
  // JPEG images can be loaded from one stream
  JIO.Seek(Src.Input, -Src.Pub.bytes_in_buffer, smFromCurrent);
end;

procedure JpegStdioSrc(var cinfo: jpeg_decompress_struct; Handle:
  TImagingHandle);
var
  Src: PSourceMgr;
begin
  if cinfo.src = nil then
  begin
    cinfo.src := cinfo.mem.alloc_small(j_common_ptr(@cinfo), JPOOL_PERMANENT,
      SizeOf(TSourceMgr));
    Src := PSourceMgr(cinfo.src);
    Src.Buffer := cinfo.mem.alloc_small(j_common_ptr(@cinfo), JPOOL_PERMANENT,
      BufferSize * SizeOf(JOCTET));
  end;
  Src := PSourceMgr(cinfo.src);
  Src.Pub.init_source := InitSource;
  Src.Pub.fill_input_buffer := FillInputBuffer;
  Src.Pub.skip_input_data := SkipInputData;
  Src.Pub.resync_to_restart := jpeg_resync_to_restart;
  Src.Pub.term_source := TermSource;
  Src.Input := Handle;
  Src.Pub.bytes_in_buffer := 0;
  Src.Pub.next_input_byte := nil;
end;

procedure InitDest(cinfo: j_compress_ptr);
var
  Dest: PDestMgr;
begin
  Dest := PDestMgr(cinfo.dest);
  Dest.Pub.next_output_byte := Dest.Buffer;
  Dest.Pub.free_in_buffer := BufferSize;
end;

function EmptyOutput(cinfo: j_compress_ptr): Boolean;
var
  Dest: PDestMgr;
begin
  Dest := PDestMgr(cinfo.dest);
  JIO.Write(Dest.Output, Dest.Buffer, BufferSize);
  Dest.Pub.next_output_byte := Dest.Buffer;
  Dest.Pub.free_in_buffer := BufferSize;
  Result := True;
end;

procedure TermDest(cinfo: j_compress_ptr);
var
  Dest: PDestMgr;
  DataCount: LongInt;
begin
  Dest := PDestMgr(cinfo.dest);
  DataCount := BufferSize - Dest.Pub.free_in_buffer;
  if DataCount > 0 then
    JIO.Write(Dest.Output, Dest.Buffer, DataCount);
end;

procedure JpegStdioDest(var cinfo: jpeg_compress_struct; Handle:
  TImagingHandle);
var
  Dest: PDestMgr;
begin
  if cinfo.dest = nil then
    cinfo.dest := cinfo.mem.alloc_small(j_common_ptr(@cinfo),
      JPOOL_PERMANENT, SizeOf(TDestMgr));
  Dest := PDestMgr(cinfo.dest);
  Dest.Buffer := cinfo.mem.alloc_small(j_common_ptr(@cinfo), JPOOL_IMAGE,
    BufferSize * SIZEOF(JOCTET));
  Dest.Pub.init_destination := InitDest;
  Dest.Pub.empty_output_buffer := EmptyOutput;
  Dest.Pub.term_destination := TermDest;
  Dest.Output := Handle;
end;

procedure InitDecompressor(Handle: TImagingHandle; var jc: TJpegContext);
begin
  FillChar(jc, sizeof(jc), 0);
  jc.common.err := @JpegErrorRec;
  jpeg_CreateDecompress(@jc.d, JPEG_LIB_VERSION, sizeof(jc.d));
  JpegStdioSrc(jc.d, Handle);
  jpeg_read_header(@jc.d, True);
  jc.d.scale_num := 1;
  jc.d.scale_denom := 1;
  jc.d.do_block_smoothing := True;
  if jc.d.out_color_space = JCS_GRAYSCALE then
  begin
    jc.d.quantize_colors := True;
    jc.d.desired_number_of_colors := 256;
  end;
end;

procedure InitCompressor(Handle: TImagingHandle; var jc: TJpegContext;
  Saver: TJpegFileFormat);
begin
  FillChar(jc, sizeof(jc), 0);
  jc.common.err := @JpegErrorRec;
  jpeg_CreateCompress(@jc.c, JPEG_LIB_VERSION, sizeof(jc.c));
  JpegStdioDest(jc.c, Handle);
  jpeg_set_defaults(@jc.c);
  jpeg_set_quality(@jc.c, Saver.FQuality, True);
  if Saver.FGrayScale then
    jpeg_set_colorspace(@jc.c, JCS_GRAYSCALE)
  else
    jpeg_set_colorspace(@jc.c, JCS_YCbCr);
  if Saver.FProgressive then
    jpeg_simple_progression(@jc.c);
end;

{ TJpegFileFormat class implementation }

constructor TJpegFileFormat.Create;
begin
  inherited Create;
  FName := SJpegFormatName;
  FCanLoad := True;
  FCanSave := True;
  FIsMultiImageFormat := False;

  FQuality := JpegDefaultQuality;
  FProgressive := JpegDefaultProgressive;

  AddMasks(SJpegMasks);
  RegisterOption(ImagingJpegQuality, @FQuality);
  RegisterOption(ImagingJpegProgressive, @FProgressive);
end;

function TJpegFileFormat.GetSupportedFormats: TImageFormats;
begin
  Result := JpegSupportedFormats;
end;

procedure TJpegFileFormat.LoadData(Handle: TImagingHandle;
  var Images: TDynImageDataArray; OnlyFirstLevel: Boolean);
var
  PtrInc, LinesPerCall, LinesRead: LongInt;
  Dest: PByte;
  jc: TJpegContext;
  Format: TImageFormat;
  Info: TImageFormatInfo;
{$IFDEF RGBSWAPPED}
  I: LongInt;
  Pix: PColor24Rec;
{$ENDIF}
begin
  // Copy IO functions to global var used in JpegLib callbacks
  SetJpegIO(GetIO);
  SetLength(Images, 1);
  InitDecompressor(Handle, jc);
  if (jc.d.out_color_space = JCS_GRAYSCALE) then
    Format := ifGray8
  else
    Format := ifR8G8B8;
  NewImage(jc.d.image_width, jc.d.image_height, Format, Images[0]);

  with JIO, Images[0] do
  begin
    jpeg_start_decompress(@jc.d);
    GetImageFormatInfo(Format, Info);
    PtrInc := Width * Info.BytesPerPixel;
    LinesPerCall := 1;
    Dest := Bits;

    while (jc.d.output_scanline < jc.d.output_height) do
    begin
      LinesRead := jpeg_read_scanlines(@jc.d, @Dest, LinesPerCall);
    {$IFDEF RGBSWAPPED}
      if Format = ifR8G8B8 then
      begin
        Pix := PColor24Rec(Dest);
        for I := 0 to Width - 1 do
        begin
          SwapValues(Pix.R, Pix.B);
          Inc(Pix, 1);
        end;
      end;
    {$ENDIF}
      Inc(Dest, PtrInc * LinesRead);
    end;

    jpeg_finish_output(@jc.d);
    jpeg_finish_decompress(@jc.d);
    ReleaseContext(jc);
  end;
end;

function TJpegFileFormat.SaveData(Handle: TImagingHandle;
  const Images: TDynImageDataArray; Index: LongInt): Boolean;
var
  Len, PtrInc, LinesWritten: LongInt;
  Src, Line: PByte;
  jc: TJpegContext;
  ImageToSave: TImageData;
  Info: TImageFormatInfo;
  MustBeFreed: Boolean;
{$IFDEF RGBSWAPPED}
  I: LongInt;
  Pix: PColor24Rec;
{$ENDIF}
begin
  // Check if option values are valid
  if not (FQuality in [1..100]) then
    FQuality := JpegDefaultQuality;
  // Copy IO functions to global var used in JpegLib callbacks
  SetJpegIO(GetIO);

  Result := PrepareSave(Handle, Images, Index);
  // Makes image to save compatible with Jpeg saving capabilities
  if Result and MakeCompatible(Images[Index], ImageToSave, MustBeFreed) then
  with JIO, ImageToSave do
  try
    GetImageFormatInfo(Format, Info);
    FGrayScale := Format = ifGray8;
    InitCompressor(Handle, jc, Self);
    jc.c.image_width := Width;
    jc.c.image_height := Height;
    if FGrayScale then
    begin
      jc.c.input_components := 1;
      jc.c.in_color_space := JCS_GRAYSCALE;
    end
    else
    begin
      jc.c.input_components := 3;
      jc.c.in_color_space := JCS_RGB;
    end;

    PtrInc := Width * Info.BytesPerPixel;
    Src := Bits;
    
  {$IFDEF RGBSWAPPED}
    GetMem(Line, PtrInc);
  {$ENDIF}

    jpeg_start_compress(@jc.c, True);
    while (jc.c.next_scanline < jc.c.image_height) do
    begin
    {$IFDEF RGBSWAPPED}
      if Format = ifR8G8B8 then
      begin
        Move(Src^, Line^, PtrInc);
        Pix := PColor24Rec(Line);
        for I := 0 to Width - 1 do
        begin
          SwapValues(Pix.R, Pix.B);
          Inc(Pix, 1);
        end;
      end;
    {$ELSE}
      Line := Src;
    {$ENDIF}

      LinesWritten := jpeg_write_scanlines(@jc.c, @Line, 1);
      Inc(Src, PtrInc * LinesWritten);
    end;

    jpeg_finish_compress(@jc.c);
  finally
    ReleaseContext(jc);
    if MustBeFreed then
      FreeImage(ImageToSave);
  {$IFDEF RGBSWAPPED}
    FreeMem(Line);
  {$ENDIF}
  end;
end;

function TJpegFileFormat.MakeCompatible(const Image: TImageData;
  var Comp: TImageData; out MustBeFreed: Boolean): Boolean;
begin
  if not inherited MakeCompatible(Image, Comp, MustBeFreed) then
  begin
    if GetFormatInfo(Comp.Format).HasGrayChannel then
      ConvertImage(Comp, ifGray8)
    else
      ConvertImage(Comp, ifR8G8B8);
  end;
  Result := Comp.Format in GetSupportedFormats;
end;

function TJpegFileFormat.TestFormat(Handle: TImagingHandle): Boolean;
var
  ReadCount: LongInt;
  ID: array[0..9] of Char;
begin
  Result := False;
  if Handle <> nil then
    with GetIO do
    begin
      FillChar(ID, SizeOf(ID), 0);
      ReadCount := Read(Handle, @ID, SizeOf(ID));
      Seek(Handle, -ReadCount, smFromCurrent);
      Result := (ReadCount = SizeOf(ID)) and
        CompareMem(@ID, @JpegMagic, SizeOf(JpegMagic)) and
        (CompareMem(@ID[6], @JFIFSignature, SizeOf(JFIFSignature)) or
        CompareMem(@ID[6], @EXIFSignature, SizeOf(EXIFSignature)));
    end;
end;

procedure TJpegFileFormat.SetJpegIO(const JpegIO: TIOFunctions);
begin
  JIO := JpegIO;
end;

initialization
  RegisterImageFileFormat(TJpegFileFormat);

{
  File Notes:

 -- TODOS ----------------------------------------------------
    - nothing now

  -- 0.21 Changes/Bug Fixes -----------------------------------
    - changed extensions to filename masks
    - changed SaveData, LoadData, and MakeCompatible methods according
      to changes in base class in Imaging unit
    - changes in TestFormat, now reads JFIF and EXIF signatures too

  -- 0.19 Changes/Bug Fixes -----------------------------------
    - input position is now set correctly to the end of the image
      after loading is done. Loading of sequence of JPEG files stored in
      single stream works now 
    - when loading and saving images in FPC with PASJPEG read and
      blue channels are swapped to have the same chanel order as IMJPEGLIB
    - you can now choose between IMJPEGLIB and PASJPEG implementations

  -- 0.17 Changes/Bug Fixes -----------------------------------
    - added SetJpegIO method which is used by JNG image format
}
end.

