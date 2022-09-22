# Date Parser 2 (dateparser2) made @safe

A port of the Python Dateutil date parser.
This module offers a generic date/time string parser which is able to parse
most known formats to represent a date and/or time. 
This module attempts to be forgiving with regards to unlikely input formats, 
returning a `SysTime` object even for dates which are ambiguous.

## Simple Example

View the docs for more.

```
import std.datetime;
import dateparser2;

void main()
{
    assert(parse("2003-09-25") == SysTime(DateTime(2003, 9, 25)));
    assert(parse("09/25/2003") == SysTime(DateTime(2003, 9, 25)));
    assert(parse("Sep 2003")   == SysTime(DateTime(2003, 9, 1)));
}
```


## Install With Dub

```
{
    ...
    "dependencies": {
        "dateparser2": "~>4.0.0"
    }
}
```

## Speed

Based on `master`, measured on a 2015 Macbook Pro 2.8GHz Intel i7. Python times measured with ipython's `%timeit` function. D times measured with `bench.sh`.

String | Python 2.7.11 | LDC 1.13.0 | DMD 2.084.0
------ | ------ | --- | ---
Thu Sep 25 10:36:28 BRST 2003 | 156 µs | 10 μs | 15 μs
2003-09-25T10:49:41.5-03:00 | 136 µs | 5 μs | 6 μs
09.25.2003 | 124 µs | 5 μs | 7 μs
2003-09-25 | 66.4 µs | 4 μs | 5 μs

## Difference to Date Parser

The difference to the original [dateparser](https://github.com/JackStouffer/date-parser)
is that this version does not use allocator but plain old `new` resulting in
being able to be called from `@safe` code.
