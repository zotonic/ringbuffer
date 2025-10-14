%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2021-2025 Marc Worrell
%% @doc Ringbuffer implements a length limited queue. In systems this is
%% often implemented as a ring, or cylic, buffer. Where the writer can
%% push the reader ahead if the buffer is full.
%%
%% This kind of buffers is useful in situations where you can have
%% surges of writers, with a limited amount of readers. And where it
%% is allowed to drop entries from the queue if the readers can't keep
%% up with the writers.
%%
%% An example is a logging system for a http server, which can handle large
%% bursts of requests. The logger is often limited in its throughput, and it
%% is perfectly ok to drop log entries if that means that the server can
%% handle the peak load.
%%
%% This ring buffer is technically not a ring. It is a size limited buffer,
%% implemented in ets. Its main characteristics are:
%%
%% <ul>
%% <li>Optimized for writes: non locking and non blocking queue writes;</li>
%% <li>Size limited, define the maximum number of entries upon queue creation;</li>
%% <li>Readers are synchronized to prevent race conditions;</li>
%% <li>Readers return the number of entries that were lost due to too
%% fast writers;</li>
%% <li>As many queues as needed.</li>
%% </ul>
%%
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

-module(ringbuffer).

-export([
    start/0,
    new/2,
    whereis/1,
    delete/1,
    write/2,
    read/1
]).

-type ringbuffer() :: term().

-export_type([ringbuffer/0]).


%% Start the ringbuffer application
start() ->
    application:start(ringbuffer).

%% @doc Create a new named buffer of Size entries. The name must be unique for all ets tables.
%% The name must be an atom, and is used for the name of the ets table. A process owning the
%% ets table and synchronizing the readers is added to <tt>ringbuffer_sup</tt>.
-spec new( Name, Size ) -> {ok, pid()} | {error, Reason} when
    Name :: atom(),
    Size :: pos_integer(),
    Reason :: {already_started, pid()} | term().
new(Name, Size) ->
    case ?MODULE:whereis(Name) of
        undefined ->
            ringbuffer_sup:start_child(Name, Size);
        Pid ->
            {error, {already_started, Pid}}
    end.

%% @doc Find the ringbuffer with a certain name, return the pid if found, otherwise undefined.
-spec whereis(Name) -> pid() | undefined when
    Name :: atom().
whereis(Name) ->
    case ringbuffer_process:process_pid(Name) of
        {ok, Pid} -> Pid;
        {error, _} -> undefined
    end.

%% @doc Delete a named ringbuffer, all queued data is destroyed. The ets table and the
%% synchronizing process are deleted.
-spec delete(Name) -> ok | {error, not_found} when
    Name :: atom().
delete(Name) ->
    ringbuffer_sup:stop_child(Name).


%% @doc Add an entry to the named ringbuffer. Never fails, if the ringbuffer
%% is full then older entries are overwritten.
-spec write(Name, Payload) -> ok when
    Name :: atom(),
    Payload :: term().
write(Name, Payload) ->
    ringbuffer_process:write(Name, Payload).

%% @doc Read the next entry from the named ringbuffer. Return the number of skipped entries and
%% the payload of the entry read. An entry is skipped if the readers are falling behind the
%% writers by more that the size of the buffer. <tt>{error, empty}</tt> is returned if the
%% buffer is empty.
-spec read( Name ) -> {ok, {SkipCount, Payload}} | {error, empty} when
    Name :: atom(),
    SkipCount :: non_neg_integer(),
    Payload :: term().
read(Name) ->
    ringbuffer_process:read(Name).

