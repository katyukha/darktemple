# DarkTemple

Born in the darkest place of the universe, full of darkest magic...

It is jinja-like compile-time template engine for D programming language.
The key goal for this implementation is to make it reliable, simple and convenient;

Currently, this is **dev** version of library.
**Everything will be changed**.


## Usage

### Simple example

```d
assert(render!(`Hello "{{ name }}"!`, name) == `Hello "John"!`);
```

### Example with file template

Let's assume that template file (named `template.1.tmpl`) has following content:

```
Test template.

User: {{ user.name }}
{# Show active or blocked state for user, depending on active field #}
User is {% if user.active %}active{% else %}blocked{% endif %}!
```

Use following code to render this file

```d
struct User {
    string name;
    bool active;
}

User user = User(name: "John", active: true);
auto result = renderFile!("test-templates/template.1.tmpl", user);
```

And result will be:

```
Test template.

User: John
User is active!
```

### Example with file that contains for statement

Content of template:

```
Test for statement

Data: {{ data }}
Content:
{% for el; data %}
- {{ el }}
{% endfor %}
```

Code:

```d
    string[] data = ["apple", "orange", "pineapple"];
    renderFile!("test-templates/template.2.tmpl", data);

```

Result:

```
Test for statement

Data: [\"apple\", \"orange\", \"pineapple\"]
Content:
- apple
- orange
- pineapple
```

## License

DarkTemple is distributed under MPL-2.0 license.
