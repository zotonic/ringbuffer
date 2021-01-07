%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2021 Marc Worrell
%% @doc Process to own the created ets table for the ring buffer.

%% Copyright 2021 Arjan Scherpenisse
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(ringbuffer_process).
-behaviour(gen_server).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([
    start_link/2,
    process_pid/1,
    write/2,
    read/1
]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).


-record(entry, {
        index :: non_neg_integer(),
        w :: non_neg_integer(),
        payload :: term()
    }).

-define(PID_INDEX,    0).
-define(SIZE_INDEX,   1).
-define(WRITER_INDEX, 2).
-define(READER_INDEX, 3).
-define(INDEX_OFFSET, 4).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(Name, Size) ->
    gen_server:start_link(?MODULE, [Name, Size], []).


%% @doc Find the process pid for the process owning the ets table.
-spec process_pid( Name :: atom() ) -> {ok, pid()}.
process_pid(Name) ->
    [ #entry{ payload = Pid } ] = ets:lookup(Name, ?PID_INDEX),
    {ok, Pid}.


%% @doc Write a payload the buffer. If the readers can't keep up then
%% older entries are overwritten.
-spec write( Name :: atom(), Payload :: term() ) -> ok.
write(Name, Payload) ->
    [ #entry{ payload = Size } ] = ets:lookup(Name, ?SIZE_INDEX),
    Writer = ets:update_counter(Name, ?WRITER_INDEX, {#entry.w, 1}),
    Index = (Writer rem Size) + ?INDEX_OFFSET,
    ets:insert(Name, #entry{ index = Index, w = Writer, payload = Payload }),
    ok.

%% @doc Read a payload from the buffer. Skip entries that are overwritten
%% by the writer.
-spec read( Name :: atom() ) -> {ok, {Skipped :: pos_integer(), Payload :: term() }} | {error, empty}.
read(Name) ->
    read(Name, 0).

read(Name, Skipped) ->
    [ #entry{ payload = Size } ] = ets:lookup(Name, ?SIZE_INDEX),
    [ #entry{ w = Writer } ] = ets:lookup(Name, ?WRITER_INDEX),
    [ #entry{ w = Reader } ] = ets:lookup(Name, ?READER_INDEX),
    case Reader of
        Writer ->
            % Writer is at reader, buffer is empty.
            {error, empty};
        _ ->
            % Writer is passed the reader, fetch next position to read
            NextReader = ets:update_counter(Name, ?READER_INDEX, {#entry.w, 1}),
            Index = (NextReader rem Size) + ?INDEX_OFFSET,
            [ #entry{ w = W, payload = P } ] = ets:lookup(Name, Index),
            case W of
                NextReader ->
                    {ok, {Skipped, P}};
                _ ->
                    % Writer is passed our reader, skip the reader forward.
                    read(Name, Skipped + 1)
            end
    end.

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([Name, Size]) ->
    Options = [
        set,
        named_table,
        public,
        {keypos, #entry.index},
        {write_concurrency, true}
    ],
    Name = ets:new(Name, Options),
    ets:insert(Name, #entry{ index = ?PID_INDEX,    w = 0, payload = self() }),
    ets:insert(Name, #entry{ index = ?SIZE_INDEX,   w = 0, payload = Size }),
    ets:insert(Name, #entry{ index = ?WRITER_INDEX, w = 0, payload = 1 }),
    ets:insert(Name, #entry{ index = ?READER_INDEX, w = 0, payload = 1 }),
    initialize(Name, Size),
    {ok, Name}.

handle_call(_Call, _From, Name) ->
    {reply, ok, Name}.

handle_cast(_Msg, Name) ->
    {noreply, Name}.

handle_info(timeout, Name) ->
    {noreply, Name};

handle_info(_Info, Name) ->
    {noreply, Name}.

terminate(_Reason, _Name) ->
    ok.

code_change(_OldVsn, Name, _Extra) ->
    {ok, Name}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% @doc Initialize all slots in the ring buffer.
initialize(_Name, 0) ->
    ok;
initialize(Name, N) ->
    R = #entry{
        index = N - 1 + ?INDEX_OFFSET,
        w = 0,
        payload = undefined
    },
    ets:insert(Name, R).
