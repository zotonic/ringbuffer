%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2021-2025 Marc Worrell
%% @doc Process to own the created ets table for the ring buffer.
%% @end

%% Copyright 2021-2025 Marc Worrell
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
        w :: integer(),
        payload :: term()
    }).

-define(PID_INDEX,    -1).
-define(SIZE_INDEX,   -2).
-define(WRITER_INDEX, -3).
-define(READER_INDEX, -4).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

%% @doc Create a new process managing a ringbuffer.
-spec start_link( atom(), pos_integer() ) -> {ok, pid()} | {error, term()}.
start_link(Name, Size) ->
    gen_server:start_link(?MODULE, [Name, Size], []).


%% @doc Find the process pid for the process owning the ets table. If the buffer
%% does not exist then an error is returned.
-spec process_pid( Name :: atom() ) -> {ok, pid()} | {error, badarg}.
process_pid(Name) ->
    try
        [ #entry{ payload = Pid } ] = ets:lookup(Name, ?PID_INDEX),
        {ok, Pid}
    catch
        error:badarg ->
            {error, badarg}
    end.

%% @doc Write a payload the buffer. If the readers can't keep up then
%% older entries are deleted.
-spec write( Name :: atom(), Payload :: term() ) -> ok.
write(Name, Payload) ->
    [ #entry{ payload = Size } ] = ets:lookup(Name, ?SIZE_INDEX),
    NextW = ets:update_counter(Name, ?WRITER_INDEX, {#entry.payload, 1}),
    ets:insert(Name, #entry{ w = NextW, payload = Payload }),
    case NextW > Size of
        true -> ets:delete(Name, NextW - Size);
        false -> ok
    end,
    ok.

%% @doc Read a payload from the buffer. Skip entries that are deleted
%% by the writers.
%%
%% There are a coupe of race conditions we need to take care of:
%%
%% 1. Writer incremented -> Reader tries entry --> Writer writes entry
%% In this case the w-value read by the reader is Size smaller than that
%% of the writer. In this case we wait till the writer finishes writing.
%%
%% 2. Two or more readers arrive at the same time, incrementing the reader value.
%% One of the readers will have the correct value and can fetch the next entry.
%% In this case the reader can move past the writer if there are not enough
%% entries in the buffer for all readers.
%%
%% For the case where multiple readers are racing past the writer can not be solved
%% without synchronization, we let the ringbuffer process handle the reader increment.
%%
-spec read( Name :: atom() ) -> {ok, {Skipped :: non_neg_integer(), Payload :: term() }} | {error, empty}.
read(Name) ->
    read(Name, 0).

read(Name, Skipped) ->
    [ #entry{ payload = Size } ] = ets:lookup(Name, ?SIZE_INDEX),
    [ #entry{ payload = Writer } ] = ets:lookup(Name, ?WRITER_INDEX),
    [ #entry{ payload = Reader } ] = ets:lookup(Name, ?READER_INDEX),
    case Reader of
        Writer ->
            % Reader is at the writer, buffer is empty.
            {error, empty};
        _ ->
            [ #entry{ payload = Pid } ] = ets:lookup(Name, ?PID_INDEX),
            case gen_server:call(Pid, advance_reader) of
                {ok, {IncSkipped, R}} ->
                    case ets:lookup(Name, R) of
                        [ #entry{ w = R, payload = P} ] ->
                            % All ok - this is the value we expected
                            ets:delete(Name, R),
                            {ok, {Skipped + IncSkipped, P}};
                        [] ->
                            % No entry, possible reasons:
                            % 1. race condition: writer didn't write yet
                            % 2. entry too old, skip and try next
                            % 3. writer crashed between counter update and write
                            % 4. writer was so fast that it deleted the too old entry
                            [ #entry{ payload = W1 } ] = ets:lookup(Name, ?WRITER_INDEX),
                            if
                                R =< (W1 - Size) ->
                                    % option 2: Reader fell behind, writer deleted the entry
                                    read(Name, Skipped+IncSkipped+1);
                                true ->
                                    % option 1: reader tried to read an entry that was not written yet.
                                    % or option 3, which we discover by waiting for a set period
                                    read_wait(Name, Size, Skipped+IncSkipped, R, 100)
                            end
                    end;
                {error, empty} ->
                    {error, empty}
            end
    end.

read_wait(Name, _Size, Skipped, _R, 0) ->
    % Give up - try next entry
    read(Name, Skipped+1);
read_wait(Name, Size, Skipped, R, Try) ->
    case ets:lookup(Name, R) of
        [ #entry{ w = R, payload = P} ] ->
            % All ok - this is the value we expected
            ets:delete(Name, R),
            {ok, {Skipped, P}};
        [] ->
            [ #entry{ w = W } ] = ets:lookup(Name, ?WRITER_INDEX),
            if
                R =< (W - Size) ->
                    % Fell behind while waiting for the value, assume it is gone.
                    read(Name, Skipped+1);
                true ->
                    timer:sleep(1),
                    read_wait(Name, Size, Skipped, R, Try-1)
            end
    end.

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([Name, Size]) when is_integer(Size) andalso Size > 0 ->
    Options = [
        set,
        named_table,
        public,
        {keypos, #entry.w},
        {write_concurrency, true}
    ],
    Name = ets:new(Name, Options),
    ets:insert(Name, #entry{ w = ?PID_INDEX,    payload = self() }),
    ets:insert(Name, #entry{ w = ?SIZE_INDEX,   payload = Size }),
    ets:insert(Name, #entry{ w = ?WRITER_INDEX, payload = 1 }),
    ets:insert(Name, #entry{ w = ?READER_INDEX, payload = 1 }),
    {ok, {Name, Size}}.

handle_call(advance_reader, _From, {Name, Size} = State) ->
    [ #entry{ payload = Writer } ] = ets:lookup(Name, ?WRITER_INDEX),
    [ #entry{ payload = Reader } ] = ets:lookup(Name, ?READER_INDEX),
    Reply = if
        Writer > (Reader + Size) ->
            Skip = (Writer - Size) - Reader,
            NextR = ets:update_counter(Name, ?READER_INDEX, {#entry.payload, Skip + 1}),
            {ok, {Skip, NextR}};
        Writer > Reader ->
            NextR = ets:update_counter(Name, ?READER_INDEX, {#entry.payload, 1}),
            {ok, {0, NextR}};
        true ->
            {error, empty}
    end,
    {reply, Reply, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(timeout, State) ->
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
