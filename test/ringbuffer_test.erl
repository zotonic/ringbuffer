%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2021-2025 Marc Worrell
%% @doc Tests for ringbuffer
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

-module(ringbuffer_test).

-include_lib("eunit/include/eunit.hrl").

all_test_() ->
    {foreach, fun () -> setup() end,
     fun (State) -> cleanup(State) end,
     [ fun test_simple/0
     , fun test_full/0
     , fun test_race/0
     , {timeout, 60, fun test_busy/0}
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

%% Test with many concurrent writers, all messages should be
%% queued (and no overflow as the buffer is larger).
test_race() ->
    {ok, _} = ringbuffer:new(race, 10000),
    Self = self(),
    erlang:spawn_link(fun() -> writer(race, a, 1000, Self) end),
    erlang:spawn_link(fun() -> writer(race, b, 1000, Self) end),
    erlang:spawn_link(fun() -> writer(race, c, 1000, Self) end),
    A1 = collect_all(race, []),
    timer:sleep(1),
    A2 = collect_all(race, A1),
    timer:sleep(1),
    A3 = collect_all(race, A2),
    timer:sleep(1),
    A4 = collect_all(race, A3),
    receive a -> ok end,
    receive b -> ok end,
    receive c -> ok end,
    Acc = collect_all(race, A4),
    3000 = length(Acc),
    ok = ringbuffer:delete(race),
    ok.


%% Test with many concurrent readers and writers
test_busy() ->
    {ok, _} = ringbuffer:new(busy, 100),
    NMsgs = 10000,
    NReader = 10,
    NWriter = 100,
    Self = self(),
    Ws = lists:map(
        fun(N) ->
            erlang:spawn_link(
                fun() ->
                    timer:sleep(10),
                    writer(busy, N, NMsgs, Self)
                end)
        end,
        lists:seq(1,NWriter)),
    Rs = lists:map(
        fun(_N) ->
            erlang:spawn_link(fun() -> reader(busy, 0, []) end)
        end,
        lists:seq(1,NReader)),
    % Wait for all writers to finish
    wait_processes(Ws),
    % Wait a bit for readers to catch up.
    timer:sleep(100),
    % Collect all readers in Rs
    lists:map(
        fun(Pid) ->
            Pid ! {stop, Self}
        end,
        Rs),
    % Receive length(Rs) messages back
    Accs = lists:map(
        fun(Pid) ->
            receive
                {SAcc, Acc, Pid} -> {SAcc, Acc}
            end
        end,
        Rs),
    {Skips, Data} = lists:unzip(Accs),
    TotalSkips = lists:sum(Skips),
    Data1 = lists:flatten(Data),
    % - SAcc + length(Acc) + length(SRest) should be NWriter * NMsgs.
    Received = TotalSkips + length(Data1),
    Sent = NWriter * NMsgs,
    Sent = Received,
    % - Data1 should only contain unique elements
    Sorted = lists:sort(Data1),
    Sorted = lists:usort(Data1),
    ok.

wait_processes([]) ->
    ok;
wait_processes([ Pid | Ps ]) ->
    case erlang:is_process_alive(Pid) of
        true ->
            timer:sleep(1),
            wait_processes([ Pid | Ps ]);
        false ->
            wait_processes(Ps)
    end.

collect_all(Buffer, Acc) ->
    case ringbuffer:read(Buffer) of
        {error, empty} -> Acc;
        {error, no_value} -> collect_all(Buffer, Acc);
        {ok, {0, K}} -> collect_all(Buffer, [ K | Acc ])
    end.

writer(_Buffer, K, 0, Self) ->
    Self ! K,
    ok;
writer(Buffer, K, N, Self) ->
    ringbuffer:write(Buffer, {K, N}),
    writer(Buffer, K, N-1, Self).


% very busy reader
reader(Buffer, SAcc, Acc) ->
    case ringbuffer:read(Buffer) of
        {error, empty} ->
            receive
                {stop, Pid} -> Pid ! {SAcc, Acc, self()}
            after 0 ->
                reader(Buffer, SAcc, Acc)
            end;
        {ok, {Skipped, K}} ->
            reader(Buffer, SAcc + Skipped, [ K | Acc ])
    end.
