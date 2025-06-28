module darktemple.parser;

private import std.algorithm: canFind;
private import std.ascii: isWhite;

// Type of fragment.
enum FragmentType {
    Text,
    Placeholder,
    Statement,
    Comment,
}

// Information about fragment that includes type, startToken, endToken
struct FragmentInfo {
    FragmentType type;
    string startToken;
    string endToken;
}

// Define info about fragments
enum FragmentInfoText = FragmentInfo(type: FragmentType.Text, startToken: null, endToken: null);
enum FragmentInfoPlaceholder = FragmentInfo(type: FragmentType.Placeholder, startToken: "{{", endToken: "}}");
enum FragmentInfoStatement = FragmentInfo(type: FragmentType.Statement, startToken: "{%", endToken: "%}");
enum FragmentInfoComment = FragmentInfo(type: FragmentType.Comment, startToken: "{#", endToken: "#}");

// Start tokens for statements. Used to search the end of text block.
enum string[] blockStartTokens = [
    FragmentInfoPlaceholder.startToken,
    FragmentInfoStatement.startToken,
    FragmentInfoComment.startToken,
];

/** This struct represents single fragment of parsed content and
  * includes info about fragment type, line number and data part of fragment
  **/
pure struct Fragment {
    FragmentType type;
    string data;
    ulong line;
}

/** Template parser. Implements range API.
  * Parse provided template in one iteration.
  * Parsed fragments (blocks) are: text, placeholder, statement and comment
  **/
pure struct Parser {
// TODO: Throw error, when  cannot find block end ('}}', '%}', '#}')
    private immutable string _data;

    private ulong _cursor = 0;
    private ulong _cursor_ln = 0;
    private ulong _block_start = 0;
    private ulong _block_start_ln = 0;
    private ulong _block_end = 0;
    private FragmentInfo _block_info;

    this(immutable string data) pure {
        _data = data;
    }

    immutable(Fragment) front() pure {
        if (_block_end <= _block_start)
            findNextBlock;

        if (_block_end > _block_start)
            return Fragment(
                type: _block_info.type,
                data: _data[_block_start .. _block_end],
                line: _block_start_ln,
            );

        assert(0, "Parser result already consumed!");
    }

    /** Returns true there is nothing left to parse (range fully consumed)
      **/
    bool empty() const pure {
        return _block_start >= _data.length;
    }

    /** Consume single fragment (block) of text being parsed
      **/
    void consumeBlock() pure {
        import std.ascii: newline;
        // in case of non-text blocks, we have to skip block start token and strip spaces
        final switch(_block_info.type) {
            case FragmentType.Text:
                // Do nothing here. It is just text
                break;
            case FragmentType.Placeholder, FragmentType.Statement, FragmentType.Comment:
                _cursor += 2;
                while (_data[_cursor].isWhite) _cursor++;
                _block_start = _cursor;
                break;
        }
        while (_cursor < _data.length) {
            if (_data[_cursor] == '\n') _cursor_ln++;

            final switch(_block_info.type) {
                case FragmentType.Text:
                    if (_data.length - _cursor >= 2 && blockStartTokens.canFind(_data[_cursor .. _cursor+2])) {
                        _block_end = _cursor;
                        return;
                    }
                    break;
                case FragmentType.Placeholder, FragmentType.Statement, FragmentType.Comment:
                    if (_data.length - _cursor >= 2 && _data[_cursor .. _cursor+2] == _block_info.endToken) {
                        _block_end = _cursor;
                        _cursor += 2;
                        while(_block_end - 1 > _block_start && _data[_block_end - 1].isWhite)
                            _block_end--;

                        if ((_block_info.type == FragmentType.Statement || _block_info.type == FragmentType.Comment) && _data.length - _cursor >= newline.length && _data[_cursor .. _cursor + newline.length] == newline)
                            _cursor += newline.length;

                        return;
                    }
                    break;
            }

            _cursor++;
        }
        _block_end = _data.length;
    }

    /** Find next fragment (block) in the text being parsed and consume it
      **/
    void findNextBlock() pure {
        if (_data.length - _cursor < 3) {
            // There are less then 3 digits, left, thus it could be just text block.
            _block_info = FragmentInfoText;
        } else switch (_data[_cursor .. _cursor + 2]) {
            case FragmentInfoPlaceholder.startToken:
                _block_info = FragmentInfoPlaceholder;
                break;
            case FragmentInfoStatement.startToken:
                _block_info = FragmentInfoStatement;
                break;
            case FragmentInfoComment.startToken:
                _block_info = FragmentInfoComment;
                break;
            default:
                _block_info = FragmentInfoText;
                break;
        }
        consumeBlock;
    }

    /** Move cursor to the end of last parsed block, thus
      * next call to front will parse next block.
      **/
    void popFront() pure
    in (!empty, "Attempt to popFront already consumed parser") {
        _block_start = _cursor;
        _block_start_ln = _cursor_ln;
    }

}


// Simple test with only placeholder
unittest {
    auto p = Parser("Hello {{ name }}!");
    assert(!p.empty);
    assert(p.front.data == "Hello ");
    assert(p.front.data == "Hello ");  // No changes when getting front
    assert(p.front.type == FragmentType.Text);
    p.popFront;
    assert(!p.empty);
    assert(p.front.data == "name");
    assert(p.front.type == FragmentType.Placeholder);
    p.popFront;
    assert(!p.empty);
    assert(p.front.data == "!");
    assert(p.front.type == FragmentType.Text);
    assert(!p.empty);
    p.popFront;
    assert(p.empty);
}

// Simple test with only placeholder
unittest {
    import std.algorithm;
    import std.array: array;
    auto p = Parser("Hello {{ name }}! Some {% statement %} and {# comment #}.");

    // Comment blocks should be ignored (skipped) by parser.
    assert(p.map!((in a) => a.data).array == ["Hello ", "name", "! Some ", "statement", " and ", "comment", "."]);
}

// Test that parser works in compile time
unittest {
    import std.algorithm;
    import std.array: array;
    immutable auto a = Parser("Hello {{ name }}! Some {% statement %} and {# comment #}.").array.map!((a) => a.data).array;

    // Comment blocks should be ignored (skipped) by parser.
    assert(a == ["Hello ", "name", "! Some ", "statement", " and ", "comment", "."]);
}

// Test some multiline template
unittest {
    auto p = Parser(
            "Hello, {{ name }}!\n" ~
            "Some text line here\n" ~
            "\n\n" ~
            "{% some statement %}");

    assert(p.front.data == "Hello, ");
    assert(p.front.type == FragmentType.Text);
    assert(p.front.line == 0);
    p.popFront;
    assert(p.front.data == "name");
    assert(p.front.type == FragmentType.Placeholder);
    assert(p.front.line == 0);
    p.popFront;
    assert(p.front.data == "!\nSome text line here\n\n\n");
    assert(p.front.type == FragmentType.Text);
    assert(p.front.line == 0);
    p.popFront;
    assert(p.front.data == "some statement");
    assert(p.front.type == FragmentType.Statement);
    assert(p.front.line == 4);
    p.popFront;
    assert(p.empty);
}

unittest {
    import std.algorithm;
    import std.array: array;
    immutable auto p = Parser(`Hello{% if check %} "{{ name }}"{% endif %}!`).array.map!((a) => a.data).array;;
    assert(p == ["Hello", "if check", " \"", "name", "\"", "endif", "!"]);
}

// Test parsing imported file
unittest {
    import std.ascii: newline;
    auto p = Parser(import("test-templates/template.1.tmpl"));

    assert(p.front.data == "Test template." ~ newline ~ newline ~ "User: ");
    assert(p.front.type == FragmentType.Text);
    assert(p.front.line == 0);
    p.popFront;
    assert(p.front.data == "user.name");
    assert(p.front.type == FragmentType.Placeholder);
    assert(p.front.line == 2);
    p.popFront;
    assert(p.front.data == newline);
    assert(p.front.type == FragmentType.Text);
    assert(p.front.line == 2);
    p.popFront;
    assert(p.front.data == "Show active or blocked state for user, depending on active field");
    assert(p.front.type == FragmentType.Comment);
    assert(p.front.line == 3);
    p.popFront;
    assert(p.front.data == "User is ");
    assert(p.front.type == FragmentType.Text);
    assert(p.front.line == 3);
    p.popFront;
    assert(p.front.data == "if user.active");
    assert(p.front.type == FragmentType.Statement);
    assert(p.front.line == 3);
    p.popFront;
    assert(p.front.data == "active");
    assert(p.front.type == FragmentType.Text);
    assert(p.front.line == 3);
    p.popFront;
    assert(p.front.data == "else");
    assert(p.front.type == FragmentType.Statement);
    assert(p.front.line == 3);
    p.popFront;
    assert(p.front.data == "blocked");
    assert(p.front.type == FragmentType.Text);
    assert(p.front.line == 3);
    p.popFront;
    assert(p.front.data == "endif");
    assert(p.front.type == FragmentType.Statement);
    assert(p.front.line == 3);
    p.popFront;
    assert(p.front.data == "!" ~ newline);
    assert(p.front.type == FragmentType.Text);
    assert(p.front.line == 3);
    p.popFront;
    assert(p.empty);
}
