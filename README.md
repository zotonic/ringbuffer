RingBuffer
==========

A ring buffer implementation using Erlang and ets tables.

Writing and reading from the ring buffer is without locking and
does not use message passing.

The size of the ring is set upon creation. If the ring is full
then older entries are overwritten. Overwritten entries are skipped
when reading the next entry. The number of skipped entries is
returned.

The ring's ets table is owned by a process managed by the ringbuffer_sup.

Usage
-----

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
    {ok, {0, Payload}} = ringbuffer:read(name).
```

The `0` is the number of entries skipped during reads. If the consumer
can keep up with the producers then it will be 0. If entries are overwritten
then it will return the number of overwritten entries.

Entries are skipped by repeatingly reading the next buffer position till
an entry that is expected is found.

If the buffer is empty then an error is returned:

```erlang
    {error, empty} = ringbuffer:read(name).
```
