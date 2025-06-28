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
            default: o.put(c); break;
        }
    return o[];
}
