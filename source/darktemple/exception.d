module darktemple.exception;

private import std.exception;

@safe:

pure class DarkTempleException : Exception {
    mixin basicExceptionCtors;
}

/// Syntax error in a template, always carrying the (0-based) line number
/// of the offending construct as a structured field.
pure class DarkTempleSyntaxError : DarkTempleException {
    ulong templateLine;

    this(string msg, ulong templateLine,
         string file = __FILE__, size_t codeLine = __LINE__,
         Throwable next = null) pure @safe {
        super(msg, file, codeLine, next);
        this.templateLine = templateLine;
    }
}
