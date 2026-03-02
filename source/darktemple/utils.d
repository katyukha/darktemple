module darktemple.utils;

private import std.array: appender;


/** Escape characters that are not valid in d string
  **/
string doEscapeString(in string str) pure {
    auto o = appender!string;
    // Reserve 110 percent of string length
    o.reserve(cast(ulong)(str.length * 1.10));
    foreach(c; str)
        switch(c) {
            case '\\': o.put("\\\\"); break;
            case '\"': o.put("\\\""); break;
            case '\0': o.put("\\0");  break;
            default: o.put(c); break;
        }
    return o[];
}

unittest {
    assert(doEscapeString("\\") == "\\\\");
    assert(doEscapeString("\"") == "\\\"");
    // NUL byte must be escaped as \0 so it does not appear literally in
    // generated D source code (#7).
    assert(doEscapeString("\0") == "\\0");
    assert(doEscapeString("foo\0bar") == "foo\\0bar");
}
