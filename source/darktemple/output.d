module darktemple.output;

private import std.array: appender, Appender;
private import std.traits : isSomeString;
private import std.conv: to;

@safe:

unittest {
    DarkTempleOutput o;

    // Branch 1: isSomeString — written directly to the appender
    o.put("hello");
    assert(o.output[] == "hello");

    // Branch 4: to!string fallback (int has no toString method)
    o.put(42);
    assert(o.output[] == "hello42");

    // Branch 3: type with toString()
    struct WithToString {
        string toString() const pure { return "-t-"; }
    }
    o.put(WithToString());
    assert(o.output[] == "hello42-t-");

    // Branch 2: type with toString(sink)
    struct WithSinkToString {
        void toString(W)(ref W sink) const pure { sink.put("-s-"); }
    }
    o.put(WithSinkToString());
    assert(o.output[] == "hello42-t--s-");
}

/** Implementation of output object for dark temple.
  * It implements automatic convertion to string when needed
  **/
struct DarkTempleOutput {
    private Appender!string _output;

    const(Appender!string) output() const pure => _output;

    void put(T)(in T value) pure {
        static if (isSomeString!(typeof(value))) {
            _output.put(value);
        } else static if (__traits(compiles, value.toString(_output))) {
            value.toString(_output);
        } else static if (__traits(compiles, value.toString())) {
            _output.put(value.toString());
        } else {
            _output.put(value.to!string);
        }
    }
}
