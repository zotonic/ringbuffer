%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2021-2025 Marc Worrell
%% @doc Supervisor for the ring buffers processes.
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

-module(ringbuffer_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).
-export([start_child/2, find_child/1, stop_child/1]).

%% Supervisor callbacks
-export([init/1]).


%% ===================================================================
%% API functions
%% ===================================================================

%% @doc Start the simple_one_for_one supervisor for the ring buffer processes.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @doc Start a ringbuffer.
-spec start_child( Name :: atom(), Size :: pos_integer() ) -> {ok, pid()} | {error, term()}.
start_child(Name, Size) ->
    supervisor:start_child(?MODULE, [Name, Size]).

%% @doc Stop a ringbuffer. The managing process is removed from the supervisor and the
%% ets table is released.
-spec stop_child( Name :: atom() ) -> ok | {error, not_found}.
stop_child(Name) ->
    case find_child(Name) of
        {ok, Pid} -> supervisor:terminate_child(?MODULE, Pid);
        {error, _} -> {error, not_found}
    end.

%% @doc Find the Pid of the ringbuffer with a certain name.
-spec find_child( Name :: atom() ) -> {ok, pid()} | {error, not_found}.
find_child(Name) ->
    case ringbuffer_process:process_pid(Name) of
        {ok, _} = Ok -> Ok;
        {error, badarg} -> {error, not_found}
    end.

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

%% @doc Supervisor callback, initialize the children.
init([]) ->
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 0,
        period => 1
    },
    ChildSpecs = [
        #{
            id => ringbuffer,
            start => {ringbuffer_process, start_link, []},
            shutdown => brutal_kill
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.
