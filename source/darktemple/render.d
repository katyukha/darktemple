module darktemple.render;



// TODO: render file, specify file, that have to be imported, and do import.
template render(string tmpl, ALIASES...) {
    private static import std.conv;
    private static import darktemple.statement;

    static foreach(i; 0 .. ALIASES.length) {
        mixin("alias ALIASES[" ~ std.conv.to!string(i) ~ "] " ~ __traits(identifier, ALIASES[i]) ~ ";");
    }

    private void render_impl(T)(ref T output) {
        mixin(new darktemple.statement.Template(tmpl).generateCode);
    }

    // TODO: Do we need to have it pure?
    string render() {
        import darktemple.output: DarkTempleOutput;
        DarkTempleOutput o;
        render_impl(o);
        return o.output[];
    }
}

unittest {
    assert(render!("Hello World!") == "Hello World!");

    // We have to assign value to some variable, to make it accessible in template.
    string name = "John";
    assert(render!("Hello {{ name }}!", name) == "Hello John!");
    assert(render!(`Hello "{{ name }}"!`, name) == `Hello "John"!`);

    bool check = false;
    assert(render!(`Hello{% if check %} "{{ name }}"{% endif %}!`, name, check) == `Hello!`);
    check = true;
    assert(render!(`Hello{% if check %} "{{ name }}"{% endif %}!`, name, check) == `Hello "John"!`);

    check = false;
    assert(render!(`Hello {% if check %}"{{ name }}"{% else %}None{% endif %}!`, name, check) == `Hello None!`);
    check = true;
    assert(render!(`Hello {% if check %}"{{ name }}"{% else %}None{% endif %}!`, name, check) == `Hello "John"!`);

    auto status = "1";
    assert(render!(`Hello {% if status == "1" %}dear{% elif status == "2" %}lucky{% else %}some{% endif %} user!`, status) == `Hello dear user!`);
    status = "2";
    assert(render!(`Hello {% if status == "1" %}dear{% elif status == "2" %}lucky{% else %}some{% endif %} user!`, status) == `Hello lucky user!`);
    status = "3";
    assert(render!(`Hello {% if status == "1" %}dear{% elif status == "2" %}lucky{% else %}some{% endif %} user!`, status) == `Hello some user!`);

    assert(render!(`Numbers: {% for num; 1 .. 5 %}{{num}}, {% endfor %}`) == `Numbers: 1, 2, 3, 4, `);
    assert(render!("Numbers: {% for num; 1 .. 5 %}{{num}} {% endfor %}") == `Numbers: 1 2 3 4 `);
    assert(render!("Numbers: {% for num; 1 .. 5 %}\n{{num}} {% endfor %}") == `Numbers: 1 2 3 4 `);
    assert(render!("Numbers: {% for num; 1 .. 5 %}\r{{num}} {% endfor %}") == `Numbers: 1 2 3 4 `);
    assert(render!("Numbers: {% for num; 1 .. 5 %}\r\n{{num}} {% endfor %}") == `Numbers: 1 2 3 4 `);
    assert(render!("Numbers: {% for num; 1 .. 5 %} \n{{num}} {% endfor %}") == `Numbers: 1 2 3 4 `);
    assert(render!("Numbers: {% for num; 1 .. 5 %} \r{{num}} {% endfor %}") == `Numbers: 1 2 3 4 `);
    assert(render!("Numbers: {% for num; 1 .. 5 %} \r\n{{num}} {% endfor %}") == `Numbers: 1 2 3 4 `);
}

// Empty template, comments, and escape round-trips
unittest {
    // #5: empty template produces empty string
    assert(render!("") == "");

    // #6: comments produce no output
    assert(render!("{# just a comment #}") == "");
    assert(render!("before{# comment #}after") == "beforeafter");
    // Newline after comment is consumed; surrounding text is unaffected
    assert(render!("a\n{# comment #}\nb") == "a\nb");

    // #8: backslash in template literal text round-trips correctly
    assert(render!("a\\b")   == "a\\b");    // template string is a\b,  output is a\b
    assert(render!("a\\\\b") == "a\\\\b");  // template string is a\\b, output is a\\b

    // #8: NUL byte in template literal text is preserved in output
    assert(render!("foo\0bar") == "foo\0bar");
    assert(render!("a\0\0b")   == "a\0\0b");
}

// Render file
unittest {

    struct User {
        string name;
        bool active;
    }

    User user = User(name: "John", active: true);
    assert(
        render!(import("test-templates/template.1.tmpl"), user) == (
"Test template.

User: John
User is active!
"));
}


/** Render file, with provided data
  **/
string renderFile(string path, ALIASES...)() {
    return render!(import(path), ALIASES);
}


// Render file 1
unittest {

    struct User {
        string name;
        bool active;
    }

    User user = User(name: "John", active: true);
    assert(
        renderFile!("test-templates/template.1.tmpl", user) == (
"Test template.

User: John
User is active!
"));
}

// Render file 2
unittest {
    string[] data = ["apple", "orange", "pineapple"];
    assert(
        renderFile!("test-templates/template.2.tmpl", data) == (
"Test for statement

Data: [\"apple\", \"orange\", \"pineapple\"]
Content:
- apple
- orange
- pineapple
"));
}

// Render file 3
unittest {
    auto val1 = 42;
    auto val2 = 78;
    assert(
        renderFile!("test-templates/template.3.tmpl", val1, val2) == (
"Value 1: 42
Value 2: 78
"));
}

// Render file 4
unittest {
    assert(
        renderFile!("test-templates/template.4.tmpl") == (
"Value: my-int=42
"));
}

// Render file 4.1
// Test that simple templates could be wrapped in pure functions
unittest {
    auto f() pure {
        return renderFile!("test-templates/template.4.tmpl");
    }
    assert(f == "Value: my-int=42\n");
}


// Render file 5
unittest {
    string[] data = ["apple", "orange", "pineapple"];
    assert(
        renderFile!("test-templates/template.5.tmpl", data) == (
"Whitespace after for block

Data: [\"apple\", \"orange\", \"pineapple\"]
Content:
- apple
- orange
- pineapple
"));
}

// Test if template can show files in directory.
// These templates are compiletime,
// thus template itself comes from trusted source (developer),
// thus we can allow it to side-effects
unittest {
    import thepath;
    import thepath.utils: createTempPath;
    auto root = createTempPath;
    scope(exit) root.remove();

    root.join("f1.txt").writeFile("Test 1");
    root.join("f2.txt").writeFile("Test 2");


    assert(
        renderFile!("test-templates/template.6.tmpl", root) == "f1.txt,\nf2.txt,\n");
}


