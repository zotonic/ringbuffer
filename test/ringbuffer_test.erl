%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2021 Marc Worrell
%% @doc Tests for ringbuffer

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

-module(ringbuffer_test).

-include_lib("eunit/include/eunit.hrl").

all_test_() ->
    {foreach, fun () -> setup() end,
     fun (State) -> cleanup(State) end,
     [ fun test_simple/0
     , fun test_full/0
     , fun test_race/0
     ]}.

setup() ->
    application:start(ringbuffer).

cleanup(_) ->
    application:stop(ringbuffer).

test_simple() ->
    {error, not_found} = ringbuffer:delete(simple),
    {ok, _} = ringbuffer:new(simple, 10),
    ok = ringbuffer:write(simple, test),
    {ok, {0, test}} = ringbuffer:read(simple),
    {error, empty} = ringbuffer:read(simple),
    ok = ringbuffer:delete(simple),
    {error, not_found} = ringbuffer:delete(simple),
    ok.

test_full() ->
    {ok, _} = ringbuffer:new(full, 10),
    lists:foreach(
        fun(N) ->
            ok = ringbuffer:write(full, N)
        end,
        lists:seq(1,11)),
    {ok, {1, 2}} = ringbuffer:read(full),
    {ok, {0, 3}} = ringbuffer:read(full),
    ok = ringbuffer:delete(full),
    ok.

test_race() ->
    {ok, _} = ringbuffer:new(race, 10000),
    Self = self(),
    erlang:spawn_link(fun() -> writer(a, 1000, Self) end),
    erlang:spawn_link(fun() -> writer(b, 1000, Self) end),
    erlang:spawn_link(fun() -> writer(c, 1000, Self) end),
    A1 = collect_all([]),
    timer:sleep(1),
    A2 = collect_all(A1),
    timer:sleep(1),
    A3 = collect_all(A2),
    timer:sleep(1),
    A4 = collect_all(A3),
    receive a -> ok end,
    receive b -> ok end,
    receive c -> ok end,
    Acc = collect_all(A4),
    3000 = length(Acc),
    ok = ringbuffer:delete(race),
    ok.

collect_all(Acc) ->
    case ringbuffer:read(race) of
        {error, empty} -> Acc;
        {ok, {0, K}} -> collect_all([ K | Acc ])
    end.

writer(K, 0, Self) ->
    Self ! K,
    ok;
writer(K, N, Self) ->
    ringbuffer:write(race, {K, N}),
    writer(K, N-1, Self).
