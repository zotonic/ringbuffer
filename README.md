[![Test](https://github.com/zotonic/ringbuffer/workflows/Test/badge.svg)](https://github.com/zotonic/ringbuffer/actions?query=workflow%3ATest)
[![Hex version](https://img.shields.io/hexpm/v/ringbuffer.svg "Hex version")](https://hex.pm/packages/ringbuffer)

Ringbuffer
==========

A ring buffer implementation using Erlang and ets tables.

Main feature is lock free writing without message passing, making
this implementation ideal for log systems with many fast writers or
big bursts.

Ringbuffer implements a length limited queue. In systems this is
often implemented as a ring, or cylic, buffer. Where the writer can
push the reader ahead if the buffer is full.

This kind of buffers is useful in situations where you can have
surges of writers, with a limited amount of readers. And where it
is allowed to drop entries from the queue if the readers can't keep
up with the writers.

An example is a logging system for a http server, which can handle large
bursts of requests. The logger is often limited in its throughput, and it
is perfectly ok to drop log entries if that means that the server can
handle the peak load.

This ring buffer is technically not a ring. It is a size limited buffer,
implemented in ets. Its main characteristics are:

 * Optimized for writes: non locking and non blocking queue writes;
 * Size limited, define the maximum number of entries upon queue creation;
 * Readers are synchronized to prevent race conditions;
 * Readers return the number of entries that were lost due to too fast writers;
 * As many queues as needed.

The size of the ring is set upon creation. If the ring is full
then older entries are overwritten. Overwritten entries are skipped
when reading the next entry. The number of skipped entries is
returned.

The ring's ets table is owned by a process managed by the ringbuffer_sup.

## Installation

RingBuffer is at Hex, in your `rebar.config` file use:

```erlang
{deps, [
    ringbuffer
]}.
```

You can also use the direct Git url and use the development version:

```erlang
{deps, [
    {ringbuffer, {git, "https://github.com/zotonic/ringbuffer.git", {branch, "main"}}}
]}.
```

## Usage

First create a ringbuffer. The buffer is named with an atom
and needs a size of the maximum amount of items to buffer.

```erlang
    {ok, Pid} = ringbuffer:new(name, 1000)
```

Then an entry can be written:

```erlang
    ok = ringbuffer:write(name, Payload).
```

The `Payload` can be any Erlang term.


It can be read afterwards:

```erlang
    {ok, {NSkipped, Payload}} = ringbuffer:read(name).
```

The `NSkipped` is the number of entries skipped during reads. If the consumer
can keep up with the producers then it will be `0`. If entries are overwritten
then it will return the number of overwritten entries.

If the buffer is empty then an error is returned:

```erlang
    {error, empty} = ringbuffer:read(name).
```

## Use in your own supervisor

You can use ringbuffer in your own supervisor with the following child spec:

```erlang
    % Size and name of the ringbuffer
    BufferSize = 1000,
    NameOfMyBuffer = foobar,
    % The child spec for your supervisor
    #{
        start => {ringbuffer_process, start_link, [NameOfMyBuffer, BufferSize]},
        restart => permanent,
        type => worker
    }
```


## Test

Run the tests:

```
make test
```

All tests should pass.

For additional checks, also run:

```
make xref
make dialyzer
```

## License

Ringbuffer is licensed under the Apache 2.0 license.
