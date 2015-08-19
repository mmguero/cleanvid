program cleanvid;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  regexpr, httpsend, synautil, XMLRead, XMLWrite, DOM, XMLUtils, zstream,
  Classes, SysUtils, DateUtils, CustApp, cvutil;

type

  TStringListArray = array of TStringList;

  TSubTitle = record
    index : integer;
    timeline : ansistring;
    startTime : extended;
    endTime : extended;
    newValues : TStringList;
    profane : boolean;
  end;
  PSubTitle = ^TSubTitle;

  TStreamInfo = record
    inputId : integer;
    streamId : integer;
    streamType : string;
    lang : string;
    info : string;
  end;
  PStreamInfo = ^TStreamInfo;

  { TCleanVid }
  TCleanVid = class(TCustomApplication)
  protected
    procedure DoRun; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure WriteHelp; virtual;
  end;

var
  doTerminate : boolean;
  verbose : boolean;
  noDelete : boolean;
  manualCmdMode : boolean;

procedure UpdateStatus(const Handle : pointer;
                       const Status : string);
var
  tmpVerbose : boolean;
begin
  if (Handle <> nil) then begin
    tmpVerbose := pboolean(Handle)^;
  end else begin
    tmpVerbose := verbose;
  end;
  if tmpVerbose then begin
    writeln(stderr, Status);
  end;
end;

function CheckCancelled(const Handle : pointer) : boolean;
begin
  if (Handle <> nil) then begin
    result := pboolean(Handle)^;
  end else begin
    result := false;
  end;
end;

{$IFDEF FPC}
{$IFOPT Q+}              // if overflow checking on
  {$Q-}                  // turn it off, but remember it!
  {$DEFINE turn_Q_On}    // set conditional to remember it!
{$ENDIF}
{$IFOPT R+}              // if range checking on
  {$R-}                  // turn it off, but remember it!
  {$DEFINE turn_R_On}    // set conditional to remember it!
{$ENDIF}
{$ENDIF}

procedure ComputeHash(const Stream : TStream;
                      out   Size : qword;
                      out   Hash : string); overload;
var
  hashQ : qword;
  fsize : qword;
  i : integer;
  read : integer;
  s : array[0..7] of char;
  tmp : qword absolute s;
begin
  Stream.Seek(0, soFromBeginning);
  Size := Stream.Size;
  hashQ := size;;

  i := 0;
  read := 1;
  while ((i < 8192) and (read > 0)) do begin
    read := Stream.Read(s, sizeof(s));
    if read > 0 then begin
      hashQ := hashQ + tmp;
    end;
    i := i + 1;
  end;

  Stream.Seek(-65536, soFromEnd); // 65536

  i := 0;
  read := 1;
  while ((i < 8192) and (read > 0)) do begin
    read := Stream.Read(s, sizeof(s));
    if read > 0 then begin
      hashQ := hashQ + tmp;
    end;
    i := i + 1;
  end;

  Hash := lowercase(Format('%.16x',[hashQ]));
end;

procedure ComputeHash(const FileName : string;
                      out   Size : qword;
                      out   Hash : string); overload;
var
  fs : TFileStream;
begin
  fs := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    ComputeHash(fs, Size, Hash);
  finally
    FreeAndNil(fs);
  end;
end;

{$IFDEF FPC}
{$IFDEF turn_Q_On}
  {$Q+}
{$ENDIF}
{$IFDEF turn_R_On}
  {$R+}
{$ENDIF}
{$ENDIF}

function CheckVid(const FileName : string) : boolean;
var
  ext : string;
  mime : string;
  cmdExitCode : integer;
  cmdSuccess : boolean;
begin
  result := false;
  if FileExists(FileName) then begin
    ext := lowercase(ExtractFileExt(FileName));
    if (ext <> '') and (ext[1] = '.') then Delete(ext, 1, 1);
    if (ext = '3g2') or (ext = '3gp') or (ext = '3gp2') or (ext = '3gpp') or (ext = 'ajp') or
       (ext = 'asf') or (ext = 'asx') or (ext = 'avchd') or (ext = 'avi') or (ext = 'bik') or
       (ext = 'bix') or (ext = 'box') or (ext = 'cam') or (ext = 'dat') or (ext = 'divx') or
       (ext = 'dmf') or (ext = 'dv') or (ext = 'dvr-ms') or (ext = 'evo') or (ext = 'flc') or
       (ext = 'fli') or (ext = 'flic') or (ext = 'flv') or (ext = 'flx') or (ext = 'gvi') or
       (ext = 'gvp') or (ext = 'h264') or (ext = 'm1v') or (ext = 'm2p') or (ext = 'm2ts') or
       (ext = 'm2v') or (ext = 'm4e') or (ext = 'm4v') or (ext = 'mjp') or (ext = 'mjpeg') or
       (ext = 'mjpg') or (ext = 'mkv') or (ext = 'moov') or (ext = 'mov') or (ext = 'movhd') or
       (ext = 'movie') or (ext = 'movx') or (ext = 'mp4') or (ext = 'mpe') or (ext = 'mpeg') or
       (ext = 'mpg') or (ext = 'mpv') or (ext = 'mpv2') or (ext = 'mxf') or (ext = 'nsv') or
       (ext = 'nut') or (ext = 'ogg') or (ext = 'ogm') or (ext = 'ogv') or (ext = 'omf') or
       (ext = 'ps') or (ext = 'qt') or (ext = 'ram') or (ext = 'rm') or (ext = 'rmvb') or
       (ext = 'swf') or (ext = 'ts') or (ext = 'vfw') or (ext = 'vid') or (ext = 'video') or
       (ext = 'viv') or (ext = 'vivo') or (ext = 'vob') or (ext = 'vro') or (ext = 'webm') or
       (ext = 'wm') or (ext = 'wmv') or (ext = 'wmx') or (ext = 'wrap') or (ext = 'wvx') or
       (ext = 'wx') or (ext = 'x264') or (ext = 'xvid')
    then begin
      mime := trim(lowercase(cvutil.ExecuteProcess('mimetype -b ' + FileName, false, cmdExitCode, cmdSuccess)));
      if verbose then writeln(stderr, ExtractFileName(FileName), ' mime type is ', mime);
      result := (Pos('video', mime) > 0);
    end;
  end;
end;

function HttpGetContentType(const http : THTTPSend) : string;
const
  CONTENT_TYPE_KEY  = 'Content-type:';
var
  i : integer;
begin
  result := '';
  if Assigned(http) and (http.Headers.Count > 0) then begin
    for i := 0 to http.Headers.Count-1 do begin
      if (Pos(uppercase(CONTENT_TYPE_KEY), uppercase(http.Headers.Strings[i])) > 0) then begin
        result := trim(Copy(http.Headers.Strings[i], Length(CONTENT_TYPE_KEY)+1, MAXINT));
        break;
      end;
    end;
  end;
end;

{ TCleanVid }

function MethodToXML(const MethodName : string;
                     const ParamPairs : TStringList;
                     const ArrayNames : array of string;
                     const ArrayValues : array of string) : string;
var
  xmlDoc : TXmlDocument;
  rootNode : TDomNode;
  methodNameNode : TDomNode;
  paramsNode : TDomNode;
  paramNode : TDomNode;
  valueNode : TDomNode;
  valueNode2 : TDomNode;
  valueNode3 : TDomNode;
  structNode : TDomNode;
  memberNode : TDomNode;
  arrayNode : TDomNode;
  dataNode : TDomNode;
  stringNode : TDomNode;
  nameNode : TDomNode;
  valueType : string;
  i : integer;
  resultStream : TStringStream;
begin
  xmlDoc := TXmlDocument.Create;
  resultStream := TStringStream.Create('');
  try
    rootNode := xmlDoc.CreateElement('methodCall');
    xmlDoc.AppendChild(rootNode);
    methodNameNode := xmlDoc.CreateElement('methodName');
    methodNameNode.TextContent := MethodName;
    rootNode.AppendChild(methodNameNode);
    paramsNode := xmlDoc.CreateElement('params');
    rootNode.AppendChild(paramsNode);
    for i := 0 to ParamPairs.Count-1 do begin
      paramNode := xmlDoc.CreateElement('param');
      valueNode := xmlDoc.CreateElement('value');
      stringNode := xmlDoc.CreateElement('string');
      stringNode.TextContent := ParamPairs.Strings[i];
      valueNode.AppendChild(stringNode);
      paramNode.AppendChild(valueNode);
      paramsNode.AppendChild(paramNode);
    end;

    if (length(ArrayNames) > 0) and (length(ArrayNames) = length(ArrayValues)) then begin
      paramNode := xmlDoc.CreateElement('param');
      valueNode := xmlDoc.CreateElement('value');
      arrayNode := xmlDoc.CreateElement('array');
      dataNode := xmlDoc.CreateElement('data');
      valueNode2 := xmlDoc.CreateElement('value');
      structNode := xmlDoc.CreateElement('struct');
      for i := low(ArrayNames) to high(ArrayNames) do begin
        memberNode := xmlDoc.CreateElement('member');
        nameNode := xmlDoc.CreateElement('name');
        nameNode.TextContent := ArrayNames[i];
        memberNode.AppendChild(nameNode);
        valueNode3 := xmlDoc.CreateElement('value');
        stringNode := xmlDoc.CreateElement('string');
        stringNode.TextContent := ArrayValues[i];
        valueNode3.AppendChild(stringNode);
        memberNode.AppendChild(valueNode3);
        structNode.AppendChild(memberNode);
      end;
      valueNode2.AppendChild(structNode);
      dataNode.AppendChild(valueNode2);
      arrayNode.AppendChild(dataNode);
      valueNode.AppendChild(arrayNode);
      paramNode.AppendChild(valueNode);
      paramsNode.AppendChild(paramNode);
    end;

    WriteXMLFile(xmlDoc, resultStream);
    resultStream.Seek(0, soFromBeginning);
    result := resultStream.DataString;
  finally
    FreeAndNil(xmlDoc);
    FreeAndNil(resultStream);
  end;
end;

procedure XMLToResponseList(const XMLResponse : TXMLDocument;
                            const ResponsePairs : TStringList);
var
  structNode : TDomNode;
  memberNode : TDomNode;
  nameNode : TDomNode;
  valueNode : TDomNode;
  dataNode : TDomNode;
begin
  ResponsePairs.Clear;
  structNode := FindNodeOrDie(XMLResponse, ['methodResponse', 'params', 'param', 'value', 'struct'], true, '');
  memberNode := structNode.FirstChild;
  while (memberNode <> nil) do begin
    nameNode := FindNodeOrDie(memberNode, ['name'], true, '');
    valueNode := FindNodeOrDie(memberNode, ['value'], true, '');
    dataNode := valueNode.FirstChild;
    ResponsePairs.AddObject(nameNode.TextContent + '=' + dataNode.TextContent, TObject(memberNode));
    memberNode := memberNode.NextSibling;
  end;
end;

procedure ParseMovieList(const DataMemberNode : TDomNode;
                         out MovieLists : TStringListArray);
var
  dataNode : TDomNode;
  valueNode : TDomNode;
  structNode : TDomNode;
  memberNode : TDomNode;
  nameNode : TDomNode;
  valueNode2 : TDomNode;
  name : string;
  value : string;
  arrayIdx : integer;
begin
  if (DataMemberNode <> nil) then begin
    dataNode := FindNodeOrDie(DataMemberNode, ['value', 'array', 'data'], true, '');
    valueNode := dataNode.FirstChild;
    SetLength(MovieLists, dataNode.ChildNodes.Count);
    for arrayIdx := low(MovieLists) to high(MovieLists) do begin
      MovieLists[arrayIdx] := nil;
    end;
    arrayIdx := 0;
    while (valueNode <> nil) do begin
      structNode := FindNodeOrDie(valueNode, ['struct'], true, '');
      memberNode := structNode.FirstChild;
      while (memberNode <> nil) do begin
        if not Assigned(MovieLists[arrayIdx]) then MovieLists[arrayIdx] := TStringList.Create;
        nameNode := FindNodeOrDie(memberNode, ['name'], true, '');
        valueNode2 := FindNodeOrDie(memberNode, ['value'], true, '');
        name := nameNode.TextContent;
        value := valueNode2.FirstChild.TextContent;
        MovieLists[arrayIdx].Add(name + '=' + value);
        memberNode := memberNode.NextSibling;
      end;
      valueNode := valueNode.NextSibling;
      inc(arrayIdx);
    end;
  end;
end;

function GetSubTitle(const FileName : string) : string;

  procedure InitHttp(var http : THttpSend);
  begin
    if Assigned(http) then FreeAndNil(http);
    http := THttpSend.Create;
    http.MimeType := 'application/xml';
  end;

const
  URL = 'http://api.opensubtitles.org/xml-rpc';
  USER_AGENT = 'cleanvid v1';
  LANG = 'en';
  CHUNKSIZE = 8192;
var
  hash : string;
  size : qword;
  http : THttpSend = nil;
  method : string;
  list : TStringList;
  response : TXMLDocument;
  responseStream : TStringStream;
  i, j : integer;
  token : string;
  status : string;
  subLists : TStringListArray;
  selectedSub : integer;
  selectLine : string;
  subLangId : string;
  subLangName : string;
  subURL : string;
  subPath : string;
  subPathGz : string;
  contentType : string;
  subFs : TFileStream = nil;
  subGzFs : TGZFileStream = nil;
  chunk : array of byte;
begin
  result := '';
  token := '';
  status := '';
  subPath := '';
  subUrl := '';

  ComputeHash(FileName, size, hash);
  if verbose then writeln(stderr, ExtractFileName(FileName), ' hashes to ', hash, ' (', size, ' bytes)');

  responseStream := TStringStream.Create('');
  list := TStringList.Create;
  InitHttp(http);
  try
    { LogIn }
    list.Clear;
    list.Add('');
    list.Add('');
    list.Add(LANG);
    list.Add(USER_AGENT);
    method := MethodToXML('LogIn', list, [], []);
    if verbose then writeln(stderr, 'LogInRequest = ', LineEnding, trim(method));
    WriteStrToStream(http.Document, method);
    if http.HTTPMethod('POST', URL) then begin
      http.Document.Seek(0, soFromBeginning);
      ReadXMLFile(response, http.Document);
      if Assigned(response) then begin
        try
          WriteXMLFile(response, responseStream);
          if verbose then writeln(stderr, 'LogInResponse = ', LineEnding, trim(responseStream.DataString));
          list.Clear;
          XMLToResponseList(response, list);
          if verbose then writeln(stderr, 'LogInResponse = ', list.CommaText);
          token := list.Values['token'];
          status := list.Values['status'];
        finally
          responseStream.Size := 0;
          if Assigned(response) then FreeAndNil(response);
        end;
      end else begin
        raise Exception.Create('LogIn response invalid!');
      end;
    end else begin
      raise Exception.Create('POST failed!');
    end;

    if (token <> '') and (status = '200 OK') then begin
      try
        { SearchSubtitles }
        SetLength(subLists, 0);
        InitHttp(http);
        list.Clear;
        list.Add(token);
        method := MethodToXML('SearchSubtitles', list, ['moviebytesize', 'sublanguageid', 'moviehash'], [IntToStr(size), 'eng', hash]);
        if verbose then writeln(stderr, 'SearchSubtitlesRequest = ', LineEnding, trim(method));
        WriteStrToStream(http.Document, method);
        if http.HTTPMethod('POST', URL) then begin
          http.Document.Seek(0, soFromBeginning);
          ReadXMLFile(response, http.Document);
          if Assigned(response) then begin
            try
              WriteXMLFile(response, responseStream);
              if verbose then writeln(stderr, 'SearchSubtitlesResponse = ', LineEnding, trim(responseStream.DataString));

              list.Clear;
              XMLToResponseList(response, list);
              if verbose then writeln(stderr, 'SearchSubtitlesResponse = ', list.CommaText);
              status := list.Values['status'];
              if (status = '200 OK') then begin
                i := list.IndexOfName('data');
                if (i > -1) then begin
                  ParseMovieList(TDomNode(list.Objects[i]), subLists);
                end;
                if (length(subLists) > 0) then begin
                  if (length(subLists) = 1) then begin
                    selectedSub := 0;
                  end else begin
                    selectedSub := -1;
                  end;
                  for i := low(subLists) to high(subLists) do begin
                    if Assigned(subLists[i]) then begin
                      writeln('Subtitle ', i, ':');
                      writeln('   Name:      ', subLists[i].Values['SubFileName']);
                      writeln('   Movie:     ', subLists[i].Values['MovieReleaseName']);
                      writeln('   Language:  ', subLists[i].Values['LanguageName']);
                      writeln('   Rating:    ', subLists[i].Values['SubRating']);
                      writeln('   Downloads: ', subLists[i].Values['SubDownloadsCnt']);
                      writeln('   Date:      ', subLists[i].Values['SubAddDate']);
                      if verbose then begin
                        for j := 0 to subLists[i].Count-1 do begin
                          writeln('   ', subLists[i].Strings[j]);
                        end;
                      end;
                    end;
                  end;
                  while (selectedSub < low(subLists)) or (selectedSub > high(subLists)) do begin
                    write('Make your subtitle selection (', low(subLists), ' to ', high(subLists),'): ');
                    readln(selectLine);
                    selectLine := trim(selectLine);
                    selectedSub := StrToIntDef(selectLine, -1);
                    if (selectedSub < low(subLists)) or (selectedSub > high(subLists)) then selectedSub := -1;
                  end;
                  subLangId := '_' + subLists[selectedSub].Values['ISO639'];
                  subLangName := subLists[selectedSub].Values['LanguageName'];
                  subURL := '_' + subLists[selectedSub].Values['SubDownloadLink'];
                  subPath := ChangeFileExt(FileName, subLangId + '.' + subLists[selectedSub].Values['SubFormat']);
                end else begin
                  raise Exception.Create('Could not find matching subtitle!');
                end;
              end else begin
                raise Exception.Create('Could not perform search!');
              end;

            finally
              for i := low(subLists) to high(subLists) do begin
                if Assigned(subLists[i]) then FreeAndNil(subLists[i]);
              end;
              SetLength(subLists, 0);
              responseStream.Size := 0;
              if Assigned(response) then FreeAndNil(response);
            end;
          end else begin
            raise Exception.Create('SearchSubtitles response invalid!');
          end;
        end else begin
          raise Exception.Create('POST failed!');
        end;

      finally
        { LogOut }
        InitHttp(http);
        list.Clear;
        list.Add(token);
        method := MethodToXML('LogOut', list, [], []);
        if verbose then writeln(stderr, 'LogOutRequest = ', LineEnding, trim(method));
        WriteStrToStream(http.Document, method);
        if http.HTTPMethod('POST', URL) then begin
          http.Document.Seek(0, soFromBeginning);
          ReadXMLFile(response, http.Document);
          if Assigned(response) then begin
            try
              WriteXMLFile(response, responseStream);
              if verbose then writeln(stderr, 'LogOutResponse = ', LineEnding, trim(responseStream.DataString));
            finally
              responseStream.Size := 0;
              if Assigned(response) then FreeAndNil(response);
            end;
          end else begin
            raise Exception.Create('LogOut response invalid!');
          end;
        end else begin
          raise Exception.Create('POST failed!');
        end;
      end;
    end else begin
      raise Exception.Create('Could not get session!');
    end;

    if (subPath <> '') and (subUrl <> '') then begin
      InitHttp(http);
      if http.HTTPMethod('GET', subUrl) then begin
        contentType := lowercase(HttpGetContentType(http));
        if verbose then writeln(stderr, 'Subtitle file content type is: ', contentType);
        if (contentType = 'application/x-gzip') then begin
          subPathGz := subPath + '.gz';
          try
            http.Document.Seek(0, soFromBeginning);
            http.Document.SaveToFile(subPathGz);
            subFs := TFileStream.Create(subPath, fmCreate);
            subGzFs := TGZFileStream.Create(subPathGz, gzopenread);
            SetLength(chunk, CHUNKSIZE);
            repeat
              i := subGzFs.read(chunk[0], CHUNKSIZE);
              if (i > 0) then subFs.Write(chunk[0], i);
            until (i < CHUNKSIZE);
          finally
            SetLength(chunk, 0);
            if FileExists(subPathGz) then DeleteFile(subPathGz);
          end;
          if FileExists(subPath) then result := subPath;
        end else begin
          raise Exception.Create('Subtitle is not gzip content type (' + contentType + ')!');
        end;
      end else begin
          raise Exception.Create('GET failed!');
      end;
    end else begin
      raise Exception.Create('Could not find subtitle to download!');
    end;

  finally
    if Assigned(http) then FreeAndNil(http);
    if Assigned(list) then FreeAndNil(list);
    if Assigned(responseStream) then FreeAndNil(responseStream);
    if Assigned(subFs) then FreeAndNil(subFs);
    if Assigned(subGzFs) then FreeAndNil(subGzFs);
  end;
end;

procedure CreateCleanSubAndEdl(const subFile : string;
                               const swearsFile : string;
                               out cleanSubFile : string;
                               out edlFile : string);
var
  swearsList : TStringList;
  swearsRegEx : TRegExpr;
  swearsHandle : TextFile;
  subHandle : TextFile;
  i, j : integer;
  swearOr : string;
  swearLine : string;
  pipePos : integer;
  dirty : string;
  dirtyCount : integer;
  clean : string;
  section : TStringList;
  subLine : string;
  subIndex : integer;
  subTimeline : string;
  timeRegExpr : TRegExpr;
  hour1, min1, sec1, ms1, hour2, min2, sec2, ms2 : integer;
  startTime, endTime : extended;
  startStr, endStr : string;
  subs : TList;
  tmpSub : PSubTitle;

  function IsProfane(const values : TStringList;
                     out newValues : TStringList)  : boolean;
  var
    i, j : integer;
    line : string;
    matches : TStringList;
    replacer : string;
  begin
    matches := TStringList.Create;
    try
      matches.Sorted := true;
      matches.Duplicates := dupIgnore;
      result := false;
      newValues := TStringList.Create;
      for i := 2 to values.Count-1 do begin // start at 2 to skip index and time line
        matches.Clear;
        line := values.Strings[i];
        if swearsRegEx.Exec(line) then repeat
          matches.Add(swearsRegEx.Match[2]);
        until not swearsRegEx.ExecNext;
        if (matches.Count > 0) then begin
          result := true;
          for j := 0 to matches.Count-1 do begin
            replacer := swearsList.Values[lowercase(matches.Strings[j])];
            if (replacer = '') then replacer := '*****';
            line := StringReplace(line, matches.Strings[j], replacer, [rfReplaceAll]);
          end;
        end;
        newValues.Add(line);
      end;
    finally
      FreeAndNil(matches);
    end;
  end;

begin
  cleanSubFile := '';
  edlFile := '';
  swearOr := '';
  swearsList := TStringList.Create;
  swearsRegEx := TRegExpr.Create;
  section := TStringList.Create;
  timeRegExpr := TRegExpr.Create;
  subs := TList.Create;
  try

    { parse and save the list of swears (with optional replacers) }
    swearsList.Sorted := true;
    swearsList.Duplicates := dupIgnore;
    AssignFile(swearsHandle, swearsFile);
    try
      Reset(swearsHandle);
      while not eof(swearsHandle) do begin
        readln(swearsHandle, swearLine);
        swearLine := trim(swearLine);
        pipePos := Pos('|', swearLine);
        if (pipePos > 1) then begin
          dirty := lowercase(Copy(swearLine, 1, pipePos-1));
          clean := lowercase(Copy(swearLine, pipePos+1, MaxInt));
          swearsList.Values[dirty] := clean;
        end else begin
          dirty := swearLine;
          clean := '';
          swearsList.Add(dirty);
        end;
        if (swearOr <> '') then swearOr := swearOr + '|';
        swearOr := swearOr + dirty;
      end;
    finally
      CloseFile(swearsHandle);
    end;
    swearsRegEx.ModifierI := true;
    swearsRegEx.Expression := '(\b)(' + swearOr + ')(s?)(\b)';

    { parse the subtitle file, extracting out sections and marking those that need replacing }
    timeRegExpr.Expression := '(\d+):(\d+):(\d+),(\d+) --> (\d+):(\d+):(\d+),(\d+)';
    subIndex := 0;
    AssignFile(subHandle, subFile);
    try
      Reset(subHandle);
      while not eof(subHandle) do begin
        readln(subHandle, subLine);
        subLine := trim(subLine);
        if (subLine = '') then begin
          if (section.Count >= 3) then begin
            try
              subIndex := StrToInt(section.Strings[0]);
            except
              inc(subIndex);
            end;
            subTimeline := section.Strings[1];
            if (subIndex > -1) and timeRegExpr.Exec(subTimeline) then begin
              hour1 := StrToIntDef(timeRegExpr.Match[1], 0);
              min1 := StrToIntDef(timeRegExpr.Match[2], 0);
              sec1 := StrToIntDef(timeRegExpr.Match[3], 0);
              ms1 := StrToIntDef(timeRegExpr.Match[4], 0);
              hour2 := StrToIntDef(timeRegExpr.Match[5], 0);
              min2 := StrToIntDef(timeRegExpr.Match[6], 0);
              sec2 := StrToIntDef(timeRegExpr.Match[7], 0);
              ms2 := StrToIntDef(timeRegExpr.Match[8], 0);
              startTime := (hour1 * 60 * 60) + (min1 * 60) + (sec1 - 0.5) + (ms1 / 1000.0);
              endTime := (hour2 * 60 * 60) + (min2 * 60) + sec2 + (ms2 / 1000.0);
              new(tmpSub);
              tmpSub^.index := subIndex;
              tmpSub^.timeline := subTimeline;
              tmpSub^.startTime := startTime;
              tmpSub^.endTime := endTime;
              tmpSub^.profane := IsProfane(section, tmpSub^.newValues);
              subs.Add(tmpSub);
            end;
            section.Clear;
          end;
        end else begin
          section.Add(subLine);
        end;
      end;
    finally
      CloseFile(subHandle);
    end;

    { create a "clean" subtitle file (only containing the profane lines with
      the profanity replaced) }
    cleanSubFile := ChangeFileExt(subFile, '.clean' + ExtractFileExt(subFile));
    subIndex := 0;
    AssignFile(subHandle, cleanSubFile);
    try
      ReWrite(subHandle);
      for i := 0 to subs.Count-1 do begin
        tmpSub := subs.Items[i];
        if (tmpSub <> nil) and (tmpSub^.profane) and Assigned(tmpSub^.newValues) and (tmpSub^.newValues.Count > 0) then begin
          inc(subIndex);
          write(subHandle, subIndex, chr(13), chr(10));
          write(subHandle, tmpSub^.timeline, chr(13), chr(10));
          for j := 0 to tmpSub^.newValues.Count-1 do begin
            write(subHandle, tmpSub^.newValues.Strings[j], chr(13), chr(10));
          end;
          write(subHandle, chr(13), chr(10));
        end;
      end;
    finally
      CloseFile(subHandle);
    end;

    { create the EDL file. if there are subsequent subtitles that both have
      swears, combine it into one EDL entry }
    edlFile := cleanSubFile + '.edl';
    startStr := '';
    endStr := '';
    AssignFile(subHandle, edlFile);
    try
      ReWrite(subHandle);
      dirtyCount := 0;
      for i := 0 to subs.Count-1 do begin
        tmpSub := subs.Items[i];
        if (tmpSub <> nil) then begin
          if tmpSub^.profane then begin
            if (dirtyCount = 0) then begin
              startStr := FloatToStrF(tmpSub^.startTime, ffFixed, 8, 3);
            end;
            endStr := FloatToStrF(tmpSub^.endTime, ffFixed, 8, 3);
            inc(dirtyCount);
          end else if (dirtyCount > 0) then begin
            writeln(subHandle, startStr, ' ', endStr, ' 1');
            dirtyCount := 0;
          end;
        end;
      end;
      if (dirtyCount > 0) then begin
        writeln(subHandle, startStr, ' ', endStr, ' 1');
        dirtyCount := 0;
      end;
    finally
      CloseFile(subHandle);
    end;

  finally
    for i := 0 to subs.Count-1 do begin
      tmpSub := PSubTitle(subs.Items[i]);
      if (tmpSub <> nil) then begin
        if Assigned(tmpSub^.newValues) then FreeAndNil(tmpSub^.newValues);
        dispose(tmpSub);
      end;
    end;
    FreeAndNil(subs);
    FreeAndNil(swearsRegEx);
    FreeAndNil(swearsList);
    FreeAndNil(section);
    FreeAndNil(timeRegExpr);
  end;
end;

procedure CreateCleanVideo(const inVideoFile : string;
                           const outVideoFile : string;
                           const edlFile : string);
var
  edlLine : string;
  edlHandle : TextFile;
  edlRegExpr : TRegExpr;
  streamsRegExpr : TRegExpr;
  lineStart : extended;
  lineEnd : extended;
  lastStart : extended = 0.0;
  lastEnd : extended = 0.0;
  newLines : TStringList;
  cmdSuccess : boolean;
  exCode : integer;
  tmpAudioFile : string;
  newAudioFile : string;
  ecaSoundPairs : TStringList;
  i : integer;
  lineStartStr : string;
  lineEndStr : string;
  operationStr : string;
  volStr : string;
  command : string;
  cmdOutput : TStringList;
  audioStreamId : integer;
  streams : TList;
  streamPtr : PStreamInfo;
  audioStreamCount : integer;
  selectLine : string;
begin
  tmpAudioFile := '';
  newAudioFile := '';
  newLines := TStringList.Create;
  edlRegExpr := TRegExpr.Create;
  streamsRegExpr := TRegExpr.Create;
  ecaSoundPairs := TStringList.Create;
  cmdOutput := TStringList.Create;
  streams := TList.Create;
  try
    edlRegExpr.Expression := '([\d\.]+)\s+([\d\.]+)(\s+(\d|-))?';

    streamsRegExpr.ModifierI := true;
    //     Stream #0.1(eng): Audio: aac, 48000 Hz, stereo, s16, 95 kb/s
    streamsRegExpr.Expression := 'Stream\s*#(\d+)\.(\d+)\s*(\((.*?)\))?\s*:\s*([^:]+)\s*:\s*(.*)';

    { fill in the EDL gaps }
    AssignFile(edlHandle, edlFile);
    try
      Reset(edlHandle);
      while not eof(edlHandle) do begin
        readln(edlHandle, edlLine);
        edlLine := trim(edlLine);
        if edlRegExpr.Exec(edlLine) then begin
          lineStart := StrToFloat(edlRegExpr.Match[1]);
          lineEnd := StrToFloat(edlRegExpr.Match[2]);
          lastEnd := lineStart - 0.001;
          newLines.Add(FloatToStrF(lastStart, ffFixed, 8, 3) + ' ' + FloatToStrF(lastEnd, ffFixed, 8, 3) + ' -');
          newLines.Add(FloatToStrF(lineStart, ffFixed, 8, 3) + ' ' + FloatToStrF(lineEnd, ffFixed, 8, 3) + ' 1');
          lastStart := lineEnd + 0.001;
        end;
      end;
      newLines.Add(FloatToStrF(lastStart, ffFixed, 8, 3) + ' 99999.000 -');
    finally
      CloseFile(edlHandle);
    end;

    { first we have to determine the streams (if there are multiple audio streams) }
    cmdOutput.Clear;
    audioStreamCount := 0;
    audioStreamId := -1;
    command := 'ffmpeg -i "' + inVideoFile + '"';
    if verbose then begin
      writeln(stderr, 'Determining streams...');
      writeln(stderr, command);
    end;
    cmdSuccess := cvutil.ExecuteProcess(command, exCode, 0, cmdOutput, nil, nil, nil, true);
    if cmdSuccess and (cmdOutput.Count > 0) then begin
      for i := cmdOutput.Count-1 downto 0 do begin
        if streamsRegExpr.Exec(cmdOutput.strings[i]) then begin
          new(streamPtr);
          streamPtr^.inputId := StrToInt(streamsRegExpr.Match[1]);
          streamPtr^.streamId := StrToInt(streamsRegExpr.Match[2]);
          streamPtr^.lang := lowercase(streamsRegExpr.Match[4]);
          streamPtr^.streamType := lowercase(streamsRegExpr.Match[5]);
          streamPtr^.info := streamsRegExpr.Match[6];
          streams.Add(streamPtr);
          if (streamPtr^.streamType = 'audio') then inc(audioStreamCount);
        end;
      end;
    end;
    if (audioStreamCount > 1) then begin
      { make them select which audio to use }
      while (audioStreamId < 0) do begin
        writeln('Audio streams:');
        for i := 0 to streams.Count-1 do begin
          streamPtr := PStreamInfo(streams.Items[i]);
          if (streamPtr <> nil) and (streamPtr^.streamType = 'audio') then begin
            writeln('   ', streamPtr^.streamId, ' (', streamPtr^.lang, '): ', streamPtr^.info);
          end;
        end;
        write('Make your audio stream ID selection: ');
        readln(selectLine);
        selectLine := trim(selectLine);
        audioStreamId := StrToIntDef(selectLine, -1);
      end;
    end else if (audioStreamCount = 1) then begin
      { find the audio stream }
      for i := 0 to streams.Count-1 do begin
        streamPtr := PStreamInfo(streams.Items[i]);
        if (streamPtr <> nil) and (streamPtr^.streamType = 'audio') then begin
          audioStreamId := streamPtr^.streamId;
          break;
        end;
      end;
    end;

    { extract the audio }
    tmpAudioFile := GetTempFileName(GetTempDir(false), 'audext') + '.wav';
    command := 'ffmpeg -y -i "' + inVideoFile + '" ';
    if (audioStreamId >= 0) then begin
      command := command + '-map 0:' + IntToStr(audioStreamId) + ' ';
    end;
    command := command + '-acodec pcm_s16le -ac 2 "' + tmpAudioFile + '"';
    if verbose then begin
      writeln(stderr, 'Exctracting audio from video file...');
      writeln(stderr, command);
    end;
    if manualCmdMode then begin
      writeln('Run this command to extract audio from video file, then press ENTER');
      writeln(command);
      readln();
      cmdSuccess := FileExists(tmpAudioFile);
      exCode := 0;
    end else begin
      cmdSuccess := cvutil.ExecuteProcessWithCallBack(command,
                      exCode, @UpdateStatus, @verbose, @CheckCancelled, @doTerminate);
    end;
    if (not cmdSuccess) or (exCode <> 0) or (not FileExists(tmpAudioFile)) then begin
      raise Exception.Create('Unable to extract audio');
    end;

    { use ecasound to generate the enveloped sound file }
    ecaSoundPairs.Delimiter := ',';
    ecaSoundPairs.StrictDelimiter := true;
    for i := 0 to newLines.Count-1 do begin
      if edlRegExpr.Exec(newLines.Strings[i]) then begin
        lineStartStr := edlRegExpr.Match[1];
        lineEndStr := edlRegExpr.Match[2];
        operationStr := edlRegExpr.Match[4];
        if (operationStr = '1') then begin
          volStr := '0';
        end else begin
          volStr := '1';
        end;
        ecaSoundPairs.Add(lineStartStr + ',' + volStr);
        ecaSoundPairs.Add(lineEndStr + ',' + volStr);
      end;
    end;
    newAudioFile := GetTempFileName(GetTempDir(false), 'audedl') + '.wav';

    command := 'ecasound -C -a:1 -f:s16_le "-i:' + tmpAudioFile + '" ' +
                '-ea:100 -klg:1,0,100,' + IntToStr(ecaSoundPairs.Count) + ',' +
                ecaSoundPairs.DelimitedText + ' "-o:' + newAudioFile + '"';
    if verbose then begin
      writeln(stderr, 'Applying EDL to audio...');
      writeln(stderr, command);
    end;
    if manualCmdMode then begin
      writeln('Run this command to apply EDL to audio, then press ENTER');
      writeln(command);
      readln();
      cmdSuccess := FileExists(newAudioFile);
      exCode := 0;
    end else begin
      cmdSuccess := cvutil.ExecuteProcessWithCallBack(command,
                      exCode, @UpdateStatus, @verbose, @CheckCancelled, @doTerminate);
    end;
    if (not cmdSuccess) or (exCode <> 0) or (not FileExists(newAudioFile)) then begin
      raise Exception.Create('Unable to apply EDL to audio');
    end;

    { use ffmpeg to remultiplex }
    command := 'ffmpeg -y -i "' + inVideoFile + '" -i "' + newAudioFile + '" ' +
                '-map 0:0 -map 1 -sn -vcodec copy -acodec libmp3lame "' + outVideoFile + '"';
    if verbose then begin
      writeln(stderr, 'Multiplexing...');
      writeln(stderr, command);
    end;
    if manualCmdMode then begin
      writeln('Run this command to remultiplex, then press ENTER');
      writeln(command);
      readln();
      cmdSuccess := FileExists(outVideoFile);
      exCode := 0;
    end else begin
      cmdSuccess := cvutil.ExecuteProcessWithCallBack(command,
                      exCode, @UpdateStatus, @verbose, @CheckCancelled, @doTerminate);
    end;
    if (not cmdSuccess) or (exCode <> 0) or (not FileExists(outVideoFile)) then begin
      raise Exception.Create('Unable to remultiplex audio and video');
    end;

  finally
    FreeAndNil(edlRegExpr);
    FreeAndNil(streamsRegExpr);
    FreeAndNil(newLines);
    FreeAndNil(cmdOutput);
    for i := 0 to streams.Count-1 do begin
      streamPtr := PStreamInfo(streams.Items[i]);
      if (streamPtr <> nil) then dispose(streamPtr);
    end;
    FreeAndNil(streams);
    if noDelete then begin
      if (tmpAudioFile <> '') and FileExists(tmpAudioFile) then begin
        writeln(stderr, 'nodel flag set, extracted audio file is ', tmpAudioFile);
      end;
      if (newAudioFile <> '') and FileExists(newAudioFile) then begin
        writeln(stderr, 'nodel flag set, edited audio file is ', newAudioFile);
      end;
    end else begin
      if (tmpAudioFile <> '') and FileExists(tmpAudioFile) then DeleteFile(tmpAudioFile);
      if (newAudioFile <> '') and FileExists(newAudioFile) then DeleteFile(newAudioFile);
    end;
  end;

end;

procedure TCleanVid.DoRun;
var
  errorMsg: string;
  errorParam : boolean;
  videoFile : string;
  outVideoFile : string;
  swearsFile : string;
  subFile : string;
  cleanSubFile : string;
  edlFile : string;
begin
  ExitCode := 1;

  { quick check parameters }
  errorMsg := CheckOptions('hvi:o:s:', 'help verbose in: out: swears: sub: nodel manual');
  if (errorMsg <> '') then begin
    ShowException(Exception.Create(errorMsg));
    Terminate;
    Exit;
  end;

  { parse parameters }
  if HasOption('h','help') then begin
    WriteHelp;
    Terminate;
    Exit;
  end;
  errorParam := false;

  verbose := HasOption('v','verbose');
  noDelete := HasOption('nodel');
  manualCmdMode := HasOption('manual');

  { make sure we have a swears file }
  swearsFile := GetOptionValue('swears');
  if not FileExists(swearsFile) then begin
    swearsFile := ExtractFilePath(ParamStr(0)) + 'swears.txt';
  end;
  if not FileExists(swearsFile) then begin
    writeln(stderr, 'Swears file (-s|--swears) not specified or does not exist');
    errorParam := true;
  end;

  { get video filename and validate }
  videoFile := GetOptionValue('i', 'in');
  if not FileExists(videoFile) then begin
    writeln(stderr, 'Input video file (-i|--in) not specified or does not exist');
    errorParam := true;
  end else if not CheckVid(videoFile) then begin
    writeln(stderr, 'Failed to validate video file');
    errorParam := true;
  end;
  outVideoFile := GetOptionValue('o', 'out');
  if (outVideoFile = '') then begin
    outVideoFile := ChangeFileExt(videoFile, '.clean' + ExtractFileExt(videoFile));
  end;

  if not errorParam then begin
    { make sure we have a subtitle file, or try to get one }
    subFile := GetOptionValue('s', 'sub');
    if (subFile = '') or (not FileExists(subFile)) then begin
      subFile := GetSubTitle(videoFile);
    end;
    if (subFile = '') or (not FileExists(subFile)) then begin
      writeln(stderr, 'Subtitle file not specified, and failed to download');
      errorParam := true;
    end;
    if verbose then writeln(stderr, 'Subtitle file is ', subFile);

    CreateCleanSubAndEdl(subFile, swearsFile, cleanSubFile, edlFile);
    if (cleanSubFile = '') or (not FileExists(cleanSubFile)) or
       (edlFile = '') or (not FileExists(edlFile))
    then begin
      writeln(stderr, 'Unable to generate clean subtitle and/or EDL file(s)');
      errorParam := true;
    end;
  end;

  if errorParam then begin
    WriteHelp;
    Terminate;
    Exit;
  end;

  CreateCleanVideo(videoFile, outVideoFile, edlFile);

  ExitCode := 0;
  // stop program loop
  Terminate;
end;

constructor TCleanVid.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  StopOnException:=True;
end;

destructor TCleanVid.Destroy;
begin
  inherited Destroy;
end;

procedure TCleanVid.WriteHelp;
begin
  writeln(stderr, '');
  writeln(stderr, 'Usage: ', ExtractFileName(ExeName));
  writeln(stderr, ' -h, --help');
  writeln(stderr, ' -v, --verbose');
  writeln(stderr, '');
end;

var
  Application: TCleanVid;
begin
  doTerminate := false;
  verbose := false;
  Application := TCleanVid.Create(nil);
  Application.Title := 'CleanVid';
  Application.Run;
  Application.Free;
end.

