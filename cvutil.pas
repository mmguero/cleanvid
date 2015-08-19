unit cvutil;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils,
  process, pipes,
  {$IFDEF UNIX}
  Unix, BaseUnix,
  {$ENDIF}
  regexpr,
  DOM, XMLRead, XMLWrite;

type
 {=============================================================================
   proecedural types, mostly for updating status of an operation
  =============================================================================}
  UpdateStatusProc =
    procedure(const Handle : pointer;
              const Status : string);

  CheckCancelledProc =
    function(const Handle : pointer)
      : boolean;

{-----------------------------------------------------------------------------
  FindNodeOrDie - Given a DOM node or an xml document, find the node represented
  by the array of strings in nodepath. If the node is not found, nil will be
  returned. If the node is not found and raiseException is true, an exception
  will be raised with sourceLine included in the exception message
}
function FindNodeOrDie
  (const parentNode : TDomNode;
   const nodePath : array of string;
   const raiseException : boolean = false;
   const sourceLine : string = '')
: TDomNode; overload;

function FindNodeOrDie
  (const parentDoc : TXMLDocument;
   const nodePath : array of string;
   const raiseException : boolean = false;
   const sourceLine : string = '')
: TDomNode; overload;

{ executes a command, sending newline-separated results (from both STDOUT and
  STDERR) to statusProc }
function ExecuteProcessWithCallBack
  (const command : string;
   out   exitCode : integer;
   const statusProc : UpdateStatusProc = nil;
   const updateHandle : pointer = nil;
   const cancelledProc : CheckCancelledProc = nil;
   const cancelHandle : pointer = nil;
   const timeoutSec : integer  = 0;
   const statusFilterRegEx : string = '';
   const statusPrepend : string = '';
   const statusAppend : string = '';
   const inheritHandles : boolean = false)
  : boolean;

{ use TProcess to execute a command. if you're compiling with FPC, this is
  better than using a libc call. note, TProcess is not a terminal/shell!
  You cannot use operators like "|", ">", "<", "&", etc. without
  doing something like /bin/bash -c 'blah | blah blah > blah.txt' }
function ExecuteProcess
  (const command : string;
   out   exitCode : integer;
   const timeoutSec : integer;
   const stdout_list : TStringList;
   const stdout_stream : TStream;
   const stderr_list : TStringList;
   const stderr_stream : TStream;
   const redirectErr : boolean;
   const updateHandle : pointer = nil;
   const stdoutbytesStatusProc : UpdateStatusProc = nil;
   const cancelHandle : pointer = nil;
   const cancelledProc : CheckCancelledProc = nil;
   const environmentVariables : TStringList = nil;
   const inheritHandles : boolean = false)
  : boolean; overload;

function ExecuteProcess
  (const command : string;
   const includeStdErr : boolean;
   out   exitCode : integer;
   out   success : boolean;
   const timeoutSec : integer = 120;
   const cancelHandle : pointer = nil;
   const cancelledProc : CheckCancelledProc = nil;
   const environmentVariables : TStringList = nil;
   const inheritHandles : boolean = false)
  : string; overload;

function FileSizeFormat (numBytes : extended) : string;

implementation


{----------------------------------------------------------------------------}
function FindNodeOrDie
  (const parentNode : TDomNode;
   const nodePath : array of string;
   const raiseException : boolean;
   const sourceLine : string)
: TDomNode; overload;
var
  i : integer;
  tmpParent : TDomNode;
begin
  result := nil;
  if (Length(nodePath) > 0) then begin
    tmpParent := parentNode;
    for i := low(nodePath) to high(nodePath) do begin
      result := tmpParent.FindNode(nodePath[i]);
      if (result = nil) then begin
        if raiseException then begin
          raise Exception.Create('Could not find ' + nodePath[i] + ' under ' + tmpParent.NodeName + ' (' + sourceLine + ')');
        end else begin
          break;
        end;
      end;
      tmpParent := result;
    end;
  end else begin
    if raiseException then begin
      raise Exception.Create('FindNodeOrDie called with invalid node path (' + sourceLine + ')');
    end;
  end;
end;

{----------------------------------------------------------------------------}
function FindNodeOrDie
  (const parentDoc : TXMLDocument;
   const nodePath : array of string;
   const raiseException : boolean;
   const sourceLine : string)
: TDomNode; overload;
begin
  if (Length(nodePath) > 0) then begin
    result := parentDoc.FindNode(nodePath[low(nodePath)]);
    if (result <> nil) then begin
      if (Length(nodePath) > 1) then begin
        result := FindNodeOrDie(result, nodePath[low(nodePath)+1..high(nodePath)], raiseException, sourceLine);
      end;
    end else begin
      if raiseException then begin
        raise Exception.Create('Could not find ' + nodePath[low(nodePath)] + ' (' + sourceLine + ')');
      end;
    end;
  end else begin
    if raiseException then begin
      raise Exception.Create('FindNodeOrDie called with invalid node path (' + sourceLine + ')');
    end;
  end;
end;

{$IFDEF UNIX}
{ should be called in the context of the child after the fork; used to
  close all file descriptors inherited from the parent }
procedure DisinheritDescriptors;
const
  MAX_FD = 16384;
var
  fdIdx : integer;
begin
  for fdIdx := 3 to MAX_FD-1 do begin
    fpclose(fdIdx);
  end;
end;
{$ENDIF}

function ExecuteProcessWithCallBack
  (const command : string;
   out   exitCode : integer;
   const statusProc : UpdateStatusProc;
   const updateHandle : pointer;
   const cancelledProc : CheckCancelledProc;
   const cancelHandle : pointer;
   const timeoutSec : integer;
   const statusFilterRegEx : string;
   const statusPrepend : string;
   const statusAppend : string;
   const inheritHandles : boolean)
  : boolean;
const
  BUFF_SIZE = 1024;
var
  buffer : array of byte;
  buff_idx : longint;
  proc : TProcess;
  start_time : TDateTime;
  status_regex : TRegExpr;
  cancelCheckLastTime : TDateTime;
  nowTime : TDateTime;
  tmpResult : longint;

  procedure CheckAndSendBuffer;
  begin
    if (buff_idx >= BUFF_SIZE-2) then begin
      buffer[BUFF_SIZE-1] := 0; // don't go past the end of the buffer
    end else begin
      buffer[buff_idx] := 0;
    end;
    if Assigned(statusProc) then begin
      if (not Assigned(status_regex)) or status_regex.Exec(pchar(@buffer[0])) then begin
        statusProc(updateHandle, statusPrepend + trim(pchar(@buffer[0])) + statusAppend);
      end;
    end;
    buff_idx := 0;
  end;

  procedure ReadAvailableBytes;
  var
    bytes_available : longword;
    read_idx : longint;
    value : byte;
  begin
    repeat
      bytes_available := proc.Output.NumBytesAvailable;
      for read_idx := 0 to bytes_available-1 do begin
        value := proc.Output.ReadByte;
        if (value = byte({$IFDEF LINUX}LineEnding{$ELSE}#10{$ENDIF})) then begin
          CheckAndSendBuffer();
        end else begin
          if (buff_idx >= BUFF_SIZE-2) then CheckAndSendBuffer();
          buffer[buff_idx] := value;
          inc(buff_idx);
        end;
      end;
    until (bytes_available = 0);
  end;

begin
  result := true;
  exitCode := -1;
  cancelCheckLastTime := now;

  try

    if (statusFilterRegEx <> '') then begin
      status_regex := TRegExpr.Create;
      status_regex.ModifierI := true;
      status_regex.Expression := statusFilterRegEx;
    end else begin
      status_regex := nil;
    end;

    proc := TProcess.Create(nil);
    try

      SetLength(buffer, BUFF_SIZE);
      buff_idx := 0;
      proc.Options := [poUsePipes, poStderrToOutPut];
      {$IFDEF UNIX}
      if not inheritHandles then proc.OnForkEvent := @DisinheritDescriptors;
      {$ELSE}
      proc.InheritHandles := inheritHandles;
      {$ENDIF}
      proc.CommandLine := command;
      proc.Execute;

      start_time := now;
      while proc.Running do begin

        nowTime := now;

        { check timeout }
        if (timeoutSec > 0) and (SecondsBetween(nowTime, start_time) > timeoutSec) then begin
          result := false;
          tmpResult := 128;
          proc.Terminate(tmpResult);
          proc.WaitOnExit; // avoid a zombie process
          raise Exception.Create('Execution timed out');
        end;

        { check to see if the operation has been cancelled }
        if Assigned(cancelledProc) and
           (SecondsBetween(cancelCheckLastTime, nowTime) >= 1)
        then begin
          if cancelledProc(cancelHandle) then begin
            result := false;
            tmpResult := 128;
            proc.Terminate(tmpResult);
            proc.WaitOnExit; // avoid a zombie process
            raise Exception.Create('Execution was cancelled');
          end;
          cancelCheckLastTime := nowTime;
        end;

        { read any output since our last loop iteration, calling the callback
          when a newline is received }
        ReadAvailableBytes();

        sleep(100);
      end; // proc.Running loop

      { read any leftover data }
      ReadAvailableBytes();

      { output any leftover data }
      if (buff_idx > 0) then CheckAndSendBuffer();

      exitCode := proc.ExitStatus;

    finally
      SetLength(buffer, 0);
      FreeAndNil(proc);
      if Assigned(status_regex) then FreeAndNil(status_regex);
    end;

  except
    on E : Exception do begin
      result := false;
    end;
  end;

end;



function ExecuteProcess
  (const command : string;
   out   exitCode : integer;
   const timeoutSec : integer;
   const stdout_list : TStringList;
   const stdout_stream : TStream;
   const stderr_list : TStringList;
   const stderr_stream : TStream;
   const redirectErr : boolean;
   const updateHandle : pointer;
   const stdoutbytesStatusProc : UpdateStatusProc;
   const cancelHandle : pointer;
   const cancelledProc : CheckCancelledProc;
   const environmentVariables : TStringList;
   const inheritHandles : boolean)
  : boolean;
const
  READ_BYTES = 2048;
var
  P : TProcess;
  buffer : array of byte;
  tmpStdOutput : TMemoryStream;
  tmpStdError : TMemoryStream;
  stdOutToUse : TStream;
  stdErrToUse : TStream;
  startTime : TDateTime;
  totalStdOutBytes : longword;
  lastStdOutBytes : longword;
  stdOutBytesRead : longword;
  callBackLastTime : TDateTime;
  cancelCheckLastTime : TDateTime;
  nowTime : TDateTime;
  tmpResult : longint;

  function ReadAvailableBytes(const source_stream : TInputPipeStream;
                              const dest_stream : TStream) : longword;
  var
    bytes_available : longword;
    bytes_read      : longint;
    bytes_to_read   : longint;
  begin
    result := 0;
    if Assigned(source_stream) and Assigned(dest_stream) then begin
      bytes_available := source_stream.NumBytesAvailable;
      while (bytes_available > 0) do begin
        if (bytes_available >= READ_BYTES) then begin
          bytes_to_read := READ_BYTES;
        end else begin
          bytes_to_read := bytes_available;
        end;
        bytes_read := source_stream.Read(buffer[0], bytes_to_read);
        if (bytes_read > 0) then begin
          dest_stream.Write(buffer[0], bytes_read);
          result := result + longword(bytes_read);
        end;
        bytes_available := source_stream.NumBytesAvailable;
      end;
    end;
  end;

begin

  result := true;
  exitCode := -1;
  totalStdOutBytes := 0;
  lastStdOutBytes := 0;
  callBackLastTime := now;
  cancelCheckLastTime := callBackLastTime;

  if Assigned(stdout_stream) then begin
    tmpStdOutput := nil;
    stdOutToUse := stdout_stream;
  end else begin
    tmpStdOutput := TMemoryStream.Create;
    stdOutToUse := tmpStdOutput;
  end;
  stdOutToUse.Size := 0;
  stdOutToUse.Seek(0, soFromBeginning);

  if Assigned(stderr_stream) then begin
    tmpStdError := nil;
    stdErrToUse := stderr_stream;
  end else begin
    tmpStdError := TMemoryStream.Create;
    stdErrToUse := tmpStdError;
  end;
  stdErrToUse.Size := 0;
  stdErrToUse.Seek(0, soFromBeginning);

  try
    SetLength(buffer, READ_BYTES);
    P := TProcess.Create(nil);
    try
      P.CommandLine := command;
      P.Options := [poUsePipes];
      if redirectErr then P.Options := P.Options + [poStderrToOutPut];
      {$IFDEF UNIX}
      if not inheritHandles then p.OnForkEvent := @DisinheritDescriptors;
      {$ELSE}
      P.InheritHandles := inheritHandles;
      {$ENDIF}
      if Assigned(environmentVariables) then begin
        P.Environment.AddStrings(environmentVariables);
      end;
      startTime := now;
      P.Execute;

      { read stdout while the process runs }
      while P.Running do begin

        stdOutBytesRead := ReadAvailableBytes(P.Output, stdOutToUse);
        if (stdOutBytesRead = 0) and
           (ReadAvailableBytes(P.Stderr, stdErrToUse) = 0) then begin
          sleep(100);
        end;

        nowTime := now;

        totalStdOutBytes := totalStdOutBytes + stdOutBytesRead;
        if Assigned(stdoutbytesStatusProc) and
           (totalStdOutBytes <> lastStdOutBytes) and
           (SecondsBetween(callBackLastTime, nowTime) >= 1)
        then begin
          stdoutbytesStatusProc(updateHandle, FileSizeFormat(totalStdOutBytes));
          lastStdOutBytes := totalStdOutBytes;
          callBackLastTime := nowTime;
        end;

        { check timeout }
        if (timeoutSec > 0) and (SecondsBetween(now, startTime) > timeoutSec) then begin
          result := false;
          tmpResult := 128;
          P.Terminate(tmpResult);
          P.WaitOnExit; // avoid a zombie process
          raise Exception.Create('Execution timed out');
        end;

        { check to see if the operation has been cancelled }
        if Assigned(cancelledProc) and
           (SecondsBetween(cancelCheckLastTime, nowTime) >= 1)
        then begin
          if cancelledProc(cancelHandle) then begin
            result := false;
            tmpResult := 128;
            P.Terminate(tmpResult);
            P.WaitOnExit; // avoid a zombie process
            raise Exception.Create('Execution was cancelled');
          end;
          cancelCheckLastTime := nowTime;
        end;

      end;

      exitCode := P.ExitStatus;

      { read what's left over in stdout }
      totalStdOutBytes := totalStdOutBytes + ReadAvailableBytes(P.Output, stdOutToUse);
      if Assigned(stdoutbytesStatusProc) then begin
        stdoutbytesStatusProc(updateHandle, FileSizeFormat(totalStdOutBytes));
      end;

      { read what's left over in stderr }
      ReadAvailableBytes(P.Stderr, stdErrToUse);

      if Assigned(stdout_list) then begin
        stdOutToUse.Seek(0, soFromBeginning);
        stdout_list.LoadFromStream(stdOutToUse);
      end;

      if (not redirectErr) then begin
        if Assigned(stderr_list) then begin
          stdErrToUse.Seek(0, soFromBeginning);
          stderr_list.LoadFromStream(stdErrToUse);
        end;
      end;

    finally
      if Assigned(tmpStdError) then FreeAndNil(tmpStdError);
      if Assigned(tmpStdOutput) then FreeAndNil(tmpStdOutput);
      FreeAndNil(P);
      SetLength(buffer, 0)
    end;
  except
    on E : Exception do begin
      result := false;
      if redirectErr and Assigned(stdout_list) then begin
        stdout_list.Add(E.Message);
      end else if Assigned(stderr_list) then begin
        stderr_list.Add(E.Message);
      end;
    end;
  end;

end;

function ExecuteProcess
  (const command : string;
   const includeStdErr : boolean;
   out   exitCode : integer;
   out   success : boolean;
   const timeoutSec : integer;
   const cancelHandle : pointer;
   const cancelledProc : CheckCancelledProc;
   const environmentVariables : TStringList;
   const inheritHandles : boolean)
  : string;
var
  stdout_list : TStringList;
begin
  stdout_list := TStringList.Create;
  try
    success := ExecuteProcess(command, exitCode, timeoutSec,
                              stdout_list, nil, nil, nil, includeStdErr,
                              nil, nil, cancelHandle, cancelledProc,
                              environmentVariables, inheritHandles);
    if (stdout_list.Count > 0) then begin
      result := stdout_list.Text;
    end else begin
      result := '';
    end;
  finally
    FreeAndNil(stdout_list);
  end;
end;

{ Get a number of bytes formatted neatly with the most logical file
  size unit. }
function FileSizeFormat(numBytes : extended) : string;

  { return the best unit of measurement for the given "order of magnitude" }
  function FileSizeUnit(orderOfMagnitude : integer) : string;
  begin
    case orderOfMagnitude of
      0 : result := 'B';
      1 : result := 'KB';
      2 : result := 'MB';
      3 : result := 'GB';
      4 : result := 'TB';
    else
      result := FileSizeUnit(1) + '^' + IntToStr(orderOfMagnitude) + ' Bytes';
    end;
  end;

var
  orderOfMagnitude : integer;
begin
  orderOfMagnitude := 0;
  while numBytes >= 1000 do begin
    numBytes := numBytes / 1024;
    orderOfMagnitude := orderOfMagnitude + 1;
  end;

  if (numBytes >= 100) or (orderOfMagnitude = 0) then begin
    result := FormatFloat('0', numBytes) + ' ' + FileSizeUnit(orderOfMagnitude);
  end else if (numBytes >= 10) then begin
    result := FormatFloat('0.0', numBytes) + ' ' + FileSizeUnit(orderOfMagnitude);
  end else begin
    result := FormatFloat('0.00', numBytes) + ' ' + FileSizeUnit(orderOfMagnitude);
  end;
end;

end.

