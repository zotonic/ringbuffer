%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2021 Marc Worrell
%% @doc RingBuffer main API

%% Copyright 2021 Marc Worrell
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
    delete/1,
    write/2,
    read/1
]).

-type ringbuffer() :: term().

-export_type([ringbuffer/0]).


%% Start the ringbuffer application
start() ->
    application:start(ringbuffer).

%% @doc Create a new named buffer. The name must be unique for all ets tables.
-spec new( Name :: atom(), Size :: non_neg_integer() ) -> {ok, pid()} | {error, term()}.
new( Name, Size ) ->
    ringbuffer_sup:start_child(Name, Size).


%% @doc Delete a named ringbuffer, all queued data is destroyed.
-spec delete( Name :: atom() ) -> ok | {error, not_found}.
delete(Name) ->
    ringbuffer_sup:stop_child(Name).


%% @doc Add an entry to the named ringbuffer. Never fails, if the ringbuffer
%% is full then older entries are overwritten.
-spec write( Name :: atom(), Payload :: term() ) -> ok.
write(Name, Payload) ->
    ringbuffer_process:write(Name, Payload).

%% @doc Read the next entry from the named ringbuffer.
-spec read( Name :: atom() ) -> {ok, {non_neg_integer(), term()}} | {error, empty}.
read(Name) ->
    ringbuffer_process:read(Name).

