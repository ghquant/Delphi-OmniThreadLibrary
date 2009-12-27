///<summary>Locking collections. Part of the OmniThreadLibrary project.</summary>
///<author>Primoz Gabrijelcic</author>
///<license>
///This software is distributed under the BSD license.
///
///Copyright (c) 2009 Primoz Gabrijelcic
///All rights reserved.
///
///Redistribution and use in source and binary forms, with or without modification,
///are permitted provided that the following conditions are met:
///- Redistributions of source code must retain the above copyright notice, this
///  list of conditions and the following disclaimer.
///- Redistributions in binary form must reproduce the above copyright notice,
///  this list of conditions and the following disclaimer in the documentation
///  and/or other materials provided with the distribution.
///- The name of the Primoz Gabrijelcic may not be used to endorse or promote
///  products derived from this software without specific prior written permission.
///
///THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
///ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
///WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
///DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
///ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
///(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
///LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
///ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
///(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
///SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
///</license>
///<remarks><para>
///   Author            : Primoz Gabrijelcic
///   Creation date     : 2009-12-27
///   Last modification : 2009-12-27
///   Version           : 0.1
///</para><para>
///   History:
///     0.1: 2009-12-27
///       - Created.
///</para></remarks>

unit OtlCollections;

///  - BlockingCollection
///    http://blogs.msdn.com/pfxteam/archive/2009/11/06/9918363.aspx
///    http://msdn.microsoft.com/en-us/library/dd267312(VS.100).aspx

interface

uses
  Windows,
  SysUtils,
  OtlCommon;

type
  ECollectionCompleted = class(Exception);

  IOmniBlockingCollectionEnumerator = interface ['{7A5AA8F4-5ED8-40C3-BDC3-1F991F652F9E}']
    function  GetCurrent: TOmniValue;
    function  MoveNext: boolean;
    property Current: TOmniValue read GetCurrent;
  end; { IOmniBlockingCollectionEnumerator }

  IOmniBlockingCollection = interface ['{208EFA15-1F8F-4885-A509-B00191145D38}']
    procedure Add(const value: TOmniValue);
    procedure CompleteAdding;
    function  GetEnumerator: IOmniBlockingCollectionEnumerator;
    function  IsCompleted: boolean;
    function  Take(var value: TOmniValue): boolean;
    function  TryAdd(const value: TOmniValue): boolean;
    function  TryTake(var value: TOmniValue; timeout_ms: cardinal = 0): boolean;
  end; { IOmniBlockingCollection }

function CreateBlockingCollection: IOmniBlockingCollection;

implementation

uses
  Classes,
  DSiWin32,
  OtlContainerObserver,
  OtlContainers;

type
  TOmniBlockingCollection = class(TInterfacedObject, IOmniBlockingCollection)
  strict private
    obcCollection     : TOmniCollection;
    obcCompleted      : boolean;
    obcCompletedSignal: TDSiEventHandle;
  public
    constructor Create;
    destructor  Destroy; override;
    procedure Add(const value: TOmniValue);
    procedure CompleteAdding;
    function  GetEnumerator: IOmniBlockingCollectionEnumerator;
    function  IsCompleted: boolean;
    function  Take(var value: TOmniValue): boolean;
    function  TryAdd(const value: TOmniValue): boolean;
    function  TryTake(var value: TOmniValue; timeout_ms: cardinal = 0): boolean;
  end; { TOmniBlockingCollection }

  TOmniBlockingCollectionEnumerator = class(TInterfacedObject, IOmniBlockingCollectionEnumerator)
  strict private
    obceCollection_ref: TOmniBlockingCollection;
    obceValue         : TOmniValue;
  public
    constructor Create(collection: TOmniBlockingCollection);
    function GetCurrent: TOmniValue;
    function MoveNext: boolean;
    property Current: TOmniValue read GetCurrent;
  end; { TOmniBlockingCollectionEnumerator }

{ exports }

function CreateBlockingCollection: IOmniBlockingCollection;
begin
  Result := TOmniBlockingCollection.Create;
end; { CreateBlockingCollection }

{ TOmniBlockingCollectionEnumerator }

constructor TOmniBlockingCollectionEnumerator.Create(collection: TOmniBlockingCollection);
begin
  obceCollection_ref := collection;
end; { TOmniBlockingCollectionEnumerator.Create }

function TOmniBlockingCollectionEnumerator.GetCurrent: TOmniValue;
begin
  Result := obceValue;
end; { TOmniBlockingCollectionEnumerator.GetCurrent }

function TOmniBlockingCollectionEnumerator.MoveNext: boolean;
begin
  Result := obceCollection_ref.Take(obceValue);
end; { TOmniBlockingCollectionEnumerator.MoveNext }

{ TOmniBlockingCollection }

constructor TOmniBlockingCollection.Create;
begin
  inherited Create;
  obcCollection := TOmniCollection.Create;
  obcCompletedSignal := CreateEvent(nil, true, false, nil);
end; { TOmniBlockingCollection.Create }

destructor TOmniBlockingCollection.Destroy;
begin
  DSiCloseHandleAndNull(obcCompletedSignal);
  FreeAndNil(obcCollection);
  inherited Destroy;
end; { TOmniBlockingCollection.Destroy }

procedure TOmniBlockingCollection.Add(const value: TOmniValue);
begin
  if not TryAdd(value) then
    raise ECollectionCompleted.Create('Adding to completed collection');
end; { TOmniBlockingCollection.Add }

procedure TOmniBlockingCollection.CompleteAdding;
begin
  obcCompleted := true;
  SetEvent(obcCompletedSignal);
end; { TOmniBlockingCollection.CompleteAdding }

function TOmniBlockingCollection.GetEnumerator: IOmniBlockingCollectionEnumerator;
begin
  Result := TOmniBlockingCollectionEnumerator.Create(Self);
end; { TOmniBlockingCollection.GetEnumerator }

function TOmniBlockingCollection.IsCompleted: boolean;
begin
  Result := obcCompleted;
end; { TOmniBlockingCollection.IsCompleted }

function TOmniBlockingCollection.Take(var value: TOmniValue): boolean;
begin
  Result := TryTake(value, INFINITE);
end; { TOmniBlockingCollection.Take }

function TOmniBlockingCollection.TryAdd(const value: TOmniValue): boolean;
begin
  // CompleteAdding and TryAdd are not synchronised
  Result := not obcCompleted;
  if Result then
    obcCollection.Enqueue(value);
end; { TOmniBlockingCollection.TryAdd }

function TOmniBlockingCollection.TryTake(var value: TOmniValue;
  timeout_ms: cardinal): boolean;
var
  observer   : TOmniContainerWindowsEventObserver;
  startTime  : int64;
  waitHandles: array [0..1] of THandle;

  function Elapsed: boolean;
  begin
    if timeout_ms = INFINITE then
      Result := false
    else
      Result := (startTime + timeout_ms) < DSiTimeGetTime64;
  end; { Elapsed }

  function TimeLeft: DWORD;
  var
    intTime: integer;
  begin
    if timeout_ms = INFINITE then
      Result := INFINITE
    else begin
      intTime := startTime + timeout_ms - DSiTimeGetTime64;
      if intTime < 0 then
        Result := 0
      else
        Result := intTime;
    end;
  end; { TimeLeft }

begin { TOmniBlockingCollection.TryTake }
  if obcCollection.TryDequeue(value) then
    Result := true
  else if IsCompleted then
    Result := false
  else begin
    observer := CreateContainerWindowsEventObserver;
    try
      obcCollection.ContainerSubject.Attach(observer, coiNotifyOnAllInserts);
      try
        startTime := DSiTimeGetTime64;
        waitHandles[0] := obcCompletedSignal;
        waitHandles[1] := observer.GetEvent;
        Result := false;
        while not (IsCompleted or Elapsed) do begin
          if obcCollection.TryDequeue(value) then begin
            Result := true;
            break; //while
          end;
          if WaitForMultipleObjects(2, @waitHandles, false, TimeLeft) <> WAIT_OBJECT_1 then begin
            Result := false;
            break; //while
          end;
        end;
      finally
        obcCollection.ContainerSubject.Detach(observer, coiNotifyOnAllInserts);
      end;
    finally FreeAndNil(observer); end;
  end;
end; { TOmniBlockingCollection.TryTake }

end.

