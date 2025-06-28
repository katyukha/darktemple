module darktemple.statement;


private import std.regex;
private import std.range;
private import std.exception;
private import std.array: Appender, replace, join;
private import std.algorithm: startsWith, map;
private import std.format: format;

private import darktemple.parser: Parser, FragmentType, Fragment;
private import darktemple.exception: DarkTempleException;
private import darktemple.utils: doEscapeString;


interface ITemplateStatement {

    string generateCode() const pure;

    string toString() const pure;
}

interface ITemplateMultiStatement : ITemplateStatement {
    void addStatement(ITemplateStatement st) pure;
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

    this() pure {
        _statements = [];
    }

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

    this(in string condition) pure {
        _branches  = [new TemplateIfBranch(condition)];
    }

    void addStatement(ITemplateStatement st) pure {
        if (_else)
            _else.addStatement(st);
        else
            _branches.back.addStatement(st);
    }

    void addElse() pure
    in (!_else, "Attempt to add second else branch") {
        _else = new TemplateMultiST();
    }

    void addElif(in string condition) pure
    in (!_else, "Attempt to add elif after else branch") {
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

    this(in string expression) pure {
        super();
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
                        auto stIf = new TemplateIf(fragment.data[3 .. $]);
                        _stack.back.addStatement(stIf);
                        _stack ~= stIf;
                    } else if (fragment.data == "else") {
                        if (auto stIf = cast(TemplateIf) _stack.back) {
                            stIf.addElse;
                        } else {
                            throw new Exception("Found 'else', but no opened IF statemenet at this place.");
                        }
                    } else if (fragment.data.startsWith("elif ")) {
                        if (auto stIf = cast(TemplateIf) _stack.back) {
                            stIf.addElif(fragment.data[5 .. $]);
                        } else {
                            throw new Exception("Found 'elif', but no opened IF statemenet at this place.");
                        }
                    } else if (fragment.data == "endif") {
                        if (auto stIf = cast(TemplateIf) _stack.back) {
                            _stack.popBack;
                        } else {
                            throw new Exception("Found 'endif', but no opened IF statemenet at this place.");
                        }
                    } else if (fragment.data.startsWith("for ")) {
                        auto stFor = new TemplateFor(fragment.data[4 .. $]);
                        _stack.back.addStatement(stFor);
                        _stack ~= stFor;
                    } else if (fragment.data == "endfor") {
                        if (auto stIf = cast(TemplateFor) _stack.back) {
                            _stack.popBack;
                        } else {
                            throw new Exception("Found 'endfor', but no opened FOR statemenet at this place.");
                        }
                    } else if (fragment.data.startsWith("import ")) {
                        auto stImport = new TemplateImportBlock(fragment.data[7 .. $]);
                        _stack.back.addStatement(stImport);
                    } else
                        assert(0, "Unknown instruction '%s'".format(fragment.data));
                    break;
                case FragmentType.Comment:
                    // Do nothing
                    break;
            }
        }
        assert(
            _stack.length == 1 && _stack[0] is this,
            "There are unclosed statements. Last unclosed statement is: " ~_stack.back.toString);
    }

    override string generateCode() const pure {
        string tmpl = "";
        tmpl ~= super.generateCode();
        return tmpl;
    }
}


