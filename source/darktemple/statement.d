module darktemple.statement;


private import std.regex;
private import std.range;
private import std.array: Appender, replace, join;
private import std.algorithm: startsWith, map;
private import std.format: format;

private import darktemple.parser: Parser, FragmentType, Fragment;
private import darktemple.exception: DarkTempleSyntaxError;
private import darktemple.utils: doEscapeString;


interface ITemplateStatement {

    string generateCode() const pure;

    string toString() const pure;
}

interface ITemplateMultiStatement : ITemplateStatement {
    void addStatement(ITemplateStatement st) pure;
    ulong startLn() const pure;
}


pure class TemplateDataBlock : ITemplateStatement {
    private const string _data;

    this(in string data) pure {
        _data = data.doEscapeString;
    }

    override string generateCode() const pure {
        return "    output.put(\"" ~ _data ~ "\");\n";
    }

    override string toString() const pure {
        return "TemplateDataBlock: [" ~ _data ~ "]";
    }

    unittest {
        enum x = new TemplateDataBlock("somevar\nbackslash: \\,\nquote: \",\n").generateCode;
        assert(x == "    output.put(\"somevar\nbackslash: \\\\,\nquote: \\\",\n\");\n");
        // NUL byte must be escaped as \0 in the generated code, not appear literally (#7).
        enum y = new TemplateDataBlock("foo\0bar").generateCode;
        assert(y == "    output.put(\"foo\\0bar\");\n");
    }
}

pure class TemplateImportBlock : ITemplateStatement {
    private const string _expression;

    this(in string expression) pure {
        _expression = expression;
    }

    override string generateCode() const pure {
        return "    import " ~ _expression ~ ";\n";
    }

    override string toString() const pure {
        return "TemplateImportBlock: [" ~ _expression ~ "]";
    }
}

pure class TemplatePlaceholder : ITemplateStatement {
    private const string _expression;

    this(in string expression) pure {
        _expression = expression;
    }

    override string generateCode() const pure {
        return "    output.put(" ~ _expression ~ ");\n";
    }

    override string toString() const pure {
        return "TemplatePlaceholder: [" ~ _expression ~ "]";
    }
}

/// Template block that contains multiple statements
pure class TemplateMultiST: ITemplateMultiStatement {
    private ITemplateStatement[] _statements;
    private ulong _startLn;

    this(ulong startLn = 0) pure {
        _statements = [];
        _startLn = startLn;
    }

    override ulong startLn() const pure => _startLn;

    void addStatement(ITemplateStatement st) pure {
        _statements ~= st;
    }

    override string generateCode() const pure {
        string res = "";
        foreach(st; _statements)
            res ~= st.generateCode();
        return res;
    }

    override string toString() const pure {
        return "TemplateMultiStatement: [\n" ~ _statements.map!((s) => s.toString).join(",\n") ~ "\n]";
    }
}

/// Template block that implements IF statement
pure class TemplateIfBranch: TemplateMultiST {
    private string _condition;

    this(in string condition) pure {
        super();
        _condition = condition;
    }

    override string generateCode() const pure {
        string res = "if (" ~ _condition ~ ") {\n";
        res ~= super.generateCode();
        res ~= "}\n";
        return res;
    }

    override string toString() const pure {
        return "TemplateIfBranch (" ~ _condition ~ "): [\n" ~ _statements.map!((s) => s.toString).join(",\n") ~ "\n]";
    }
}

/// Template block that implements IF/ELIF/ELSE statement
pure class TemplateIf: ITemplateMultiStatement {
    private TemplateIfBranch[] _branches;
    private TemplateMultiST _else;
    private ulong _startLn;

    this(in string condition, ulong startLn = 0) pure {
        _branches  = [new TemplateIfBranch(condition)];
        _startLn = startLn;
    }

    override ulong startLn() const pure => _startLn;

    void addStatement(ITemplateStatement st) pure {
        if (_else)
            _else.addStatement(st);
        else
            _branches.back.addStatement(st);
    }

    void addElse(ulong line) pure {
        if (_else)
            throw new DarkTempleSyntaxError("Duplicate 'else'", line);
        _else = new TemplateMultiST();
    }

    void addElif(in string condition, ulong line) pure {
        if (_else)
            throw new DarkTempleSyntaxError("Unexpected 'elif' after 'else'", line);
        _branches ~= new TemplateIfBranch(condition);
    }

    override string generateCode() const pure {
        string res = "";
        foreach(ifbranch; _branches) {
            if (res.empty)
                res ~= ifbranch.generateCode;
            else
                res ~= "else " ~ ifbranch.generateCode;
        }
        if (_else) {
            res ~= "else {\n";
            res ~= _else.generateCode;
            res ~= "}\n";
        }
        return res;
    }

    override string toString() const pure {
        return "TemplateIf: {\n" ~ _branches.map!((s) => s.toString).join(",\n") ~ (_else ? ("Else - " ~ _else.toString) : "") ~ "\n}";
    }
}


pure class TemplateFor: TemplateMultiST {
    private string _expression;

    // TODO: Implement support for expression in format `val in range` or `key, val in assocArray`

    this(in string expression, ulong startLn = 0) pure {
        super(startLn);
        _expression = expression;
    }

    override string generateCode() const pure {
        string res = "foreach (" ~ _expression ~ ") {\n";
        res ~= super.generateCode();
        res ~= "}\n";
        return res;
    }

    override string toString() const pure {
        return "TemplateFor (" ~ _expression ~ "): [\n" ~ _statements.map!((s) => s.toString).join(",\n") ~ "\n]";
    }
}

pure class Template : TemplateMultiST {

    this(in string input) pure {
        super();

        ITemplateMultiStatement[] _stack = [this];

        foreach(fragment; Parser(input)) {
            final switch(fragment.type) {
                case FragmentType.Text:
                    _stack.back.addStatement(new TemplateDataBlock(fragment.data));
                    break;
                case FragmentType.Placeholder:
                    _stack.back.addStatement(new TemplatePlaceholder(fragment.data));
                    break;
                case FragmentType.Statement:
                    if (fragment.data.startsWith("if ")) {
                        auto stIf = new TemplateIf(fragment.data[3 .. $], fragment.line);
                        _stack.back.addStatement(stIf);
                        _stack ~= stIf;
                    } else if (fragment.data == "else") {
                        if (auto stIf = cast(TemplateIf) _stack.back) {
                            stIf.addElse(fragment.line);
                        } else {
                            throw new DarkTempleSyntaxError(
                                "Unexpected 'else': no open 'if' block",
                                fragment.line);
                        }
                    } else if (fragment.data.startsWith("elif ")) {
                        if (auto stIf = cast(TemplateIf) _stack.back) {
                            stIf.addElif(fragment.data[5 .. $], fragment.line);
                        } else {
                            throw new DarkTempleSyntaxError(
                                "Unexpected 'elif': no open 'if' block",
                                fragment.line);
                        }
                    } else if (fragment.data == "endif") {
                        if (auto stIf = cast(TemplateIf) _stack.back) {
                            _stack.popBack;
                        } else {
                            throw new DarkTempleSyntaxError(
                                "Unexpected 'endif': no open 'if' block",
                                fragment.line);
                        }
                    } else if (fragment.data.startsWith("for ")) {
                        auto stFor = new TemplateFor(fragment.data[4 .. $], fragment.line);
                        _stack.back.addStatement(stFor);
                        _stack ~= stFor;
                    } else if (fragment.data == "endfor") {
                        if (auto stIf = cast(TemplateFor) _stack.back) {
                            _stack.popBack;
                        } else {
                            throw new DarkTempleSyntaxError(
                                "Unexpected 'endfor': no open 'for' block",
                                fragment.line);
                        }
                    } else if (fragment.data.startsWith("import ")) {
                        auto stImport = new TemplateImportBlock(fragment.data[7 .. $]);
                        _stack.back.addStatement(stImport);
                    } else
                        throw new DarkTempleSyntaxError(
                            "Unknown statement '%s'".format(fragment.data),
                            fragment.line);
                    break;
                case FragmentType.Comment:
                    // Do nothing
                    break;
            }
        }
        if (_stack.length != 1 || _stack[0] !is this)
            throw new DarkTempleSyntaxError(
                "Unclosed block: " ~ _stack.back.toString,
                _stack.back.startLn);
    }

    override string generateCode() const pure {
        string tmpl = "";
        tmpl ~= super.generateCode();
        return tmpl;
    }
}

// Unclosed if/for blocks must throw DarkTempleException (#1)
unittest {
    import std.exception: assertThrown;
    import darktemple.exception: DarkTempleException;

    assertThrown!DarkTempleException(new Template("{% if true %}"));
    assertThrown!DarkTempleException(new Template("{% for x; xs %}"));
    // Both unclosed simultaneously — error reports the innermost one
    assertThrown!DarkTempleException(new Template("{% if true %}{% for x; xs %}"));
}

// Mismatched nesting: endfor inside if, endif inside for (#2)
unittest {
    import std.exception: assertThrown;
    import darktemple.exception: DarkTempleException;

    assertThrown!DarkTempleException(
        new Template("{% if true %}{% endfor %}{% endif %}"));
    assertThrown!DarkTempleException(
        new Template("{% for x; xs %}{% endif %}{% endfor %}"));
}

// Double else and elif-after-else trigger D in-contracts, which currently
// throw AssertError instead of DarkTempleException (#3 — unfixed bug).
unittest {
    import std.exception: assertThrown;
    import darktemple.exception: DarkTempleException;

    assertThrown!DarkTempleException(
        new Template("{% if true %}{% else %}x{% else %}y{% endif %}"));
    assertThrown!DarkTempleException(
        new Template("{% if true %}{% else %}x{% elif z %}y{% endif %}"));
}

// Tests for issues #3, #4, #5
unittest {
    import std.conv: to;
    import std.exception: assertThrown, collectException;
    import darktemple.exception: DarkTempleException, DarkTempleSyntaxError;

    // #3: unknown statement must throw DarkTempleException, not AssertError
    // #5: all control-flow mismatches must throw DarkTempleException, not Exception
    assertThrown!DarkTempleException(new Template("{% foobar %}"));
    assertThrown!DarkTempleException(new Template("{% else %}"));
    assertThrown!DarkTempleException(new Template("{% elif true %}"));
    assertThrown!DarkTempleException(new Template("{% endif %}"));
    assertThrown!DarkTempleException(new Template("{% endfor %}"));

    // #4: line number of the offending statement is available as a structured field
    auto e1 = collectException!DarkTempleSyntaxError(
        new Template("first line\n{% foobar %}"));
    assert(e1 !is null);
    assert(e1.templateLine == 1, "expected templateLine 1, got: " ~ e1.templateLine.to!string);

    auto e2 = collectException!DarkTempleSyntaxError(
        new Template("line 0\nline 1\n{% else %}"));
    assert(e2 !is null);
    assert(e2.templateLine == 2, "expected templateLine 2, got: " ~ e2.templateLine.to!string);
}

