import sys
import gumbo
import textwrap

options = {"rewrap": True}


def _traverse(node: gumbo.Node):
    # .findAll requires the .next pointer, which is what we're trying to add
    # when we call this, and so we manually supply a generator to yield the
    # nodes in DOM order.
    yield node
    try:
        for child in node.contents:
            for descendant in _traverse(child):
                yield descendant
    except AttributeError:
        # Not an element.
        return


def wrap(input: str,
         prefix: str,
         suffix=None,
         add_space: bool=False,
         add_newlines: bool=False):
    if suffix is None:
        suffix = prefix
    bprefix = prefix
    asuffix = suffix
    if add_space:
        bprefix = " " + prefix
        asuffix = suffix + " "

    result = bprefix + input + asuffix
    return result


def trimIt(string: str, leading=True, trailing=True):
    if(leading):
        while string.startswith(" ") or string.startswith(
                "\n") or string.startswith("\t"):
            string = string[1:]
    if(trailing):
        while string.endswith(" ") or string.endswith("\n") or string.endswith(
                "\t"):
            string = string[0:-1]
    return string

def fill(string, width=90):
    return textwrap.fill(" ".join(map(trimIt, string.split("\n"))), width)

def arrange_list_item(string, indent_prefix):
    string = fill(string)
    string = textwrap.indent(string, indent_prefix)
    string = trimIt(string, trailing=False)
    return string


def handle_tag(tag, result, list_indent_local, attributes=None, noFmt=[]):
    if tag in noFmt:
        return result
    if tag in ["H1", "H2", "H3", "H4"]:
        tag_s = tag.replace("H", "")
        result = ("*" * int(tag_s)) + " " + result + "\n"

    elif tag in ["TITLE"]:
        result = "\n#+TITLE: " + result + "\n"

    elif tag in ["STRONG", "B"]:
        result = wrap(result, "*", add_space=True)

    elif tag in ["TT"]:
        result = wrap(result, "=", add_space=True)

    elif tag in ["EM"]:
        result = wrap(result, "*", add_space=True)

    elif tag in ["I"]:
        result = wrap(result, "/", add_space=True)

    elif tag in ["DEL"]:
        result = wrap(result, "+", add_space=True)

    elif tag in ["SUB"]:
        result = wrap(result, "_{", "}", add_space=False)

    elif tag in ["SUP"]:
        result = wrap(result, "^{", "}", add_space=False)

    elif tag in ["P"]:
        if options["rewrap"]:
            result = fill(result)
        result = result + "\n\n"

    elif tag in ["BR"]:
        result = result + "\n\n"

    elif tag in ["TABLE"]:
        result = wrap(result, "\n")

    elif tag in ["CODE", "PRE"]:
        language = ""
        if result.find("\n") == -1 and len(result) < 15:
            result = "=" + result + "="
        else:
            if(result.startswith(" =") and result.endswith("= ")):
                result = result[2:-2]
            result = "#+BEGIN_SRC {}\n".format(language) + result + "\n#+END_SRC\n\n"

    elif tag in ["TR"]:
        result += "\n"

    elif tag in ["TD"]:
        result = " | " + result + " | "

    elif tag in ["UL", "OL"]:
        result = result + "\n"

    elif tag in ["A"]:
        while result.startswith("["):
            result = result[1:]
        while result.endswith("]"):
            result = result[0:-1]
        if (attributes and "href" in attributes):
            if result == "":
                result = wrap(attributes["href"], "[[", "]]", add_space=True)
            else:
                result = wrap(attributes["href"] + "][" + result,
                              prefix="[[",
                              suffix="]]",
                              add_space=True)

    elif tag in ["DL"]:
        result = result + "\n"

    elif tag in ["DT"]:
        result = (" " * list_indent_local) + "- " + result + " :: "

    elif tag in ["DD"]:
        result = arrange_list_item(result, (" " * list_indent_local) + "  ")
        result = result + "\n"

    elif tag in ["LI"]:
        result = arrange_list_item(result, (" " * list_indent_local) + "  ")
        result = (" " * list_indent_local) + "- " + result + "\n"

    elif tag in ["DIV", "SPAN"]:
        result = result

    elif tag in ["NAV", "META", "LINK", "SCRIPT", "STYLE"]:
        result = ""

    return result
    # else:

    # if tag in errors:
    #     errors[tag] = errors[tag] + 1
    # else:
    #     errors.add({tag: 0})


def html_to_org_gumbo(element: gumbo.Node, list_indent=0, noFmt=[]):
    result = ""

    if hasattr(element, "tag"):
        if str(element.tag) in ["H1", "H2", "H3"]:
            list_indent = 0
        elif str(element.tag) in ["UL", "DL", "OL"]:
            list_indent += 3

    if hasattr(element, "type"):
        if str(element.type) == "TEXT":
            result += trimIt(element.contents.text.decode("utf-8"))
    if hasattr(element, "children"):
        for child in element.children:
            skip = []
            if hasattr(child, "tag") and hasattr(element, "tag"):
                if str(child.tag) == "CODE" and str(element.tag) == "PRE":
                    skip.append("CODE")
            result += html_to_org_gumbo(child, list_indent, noFmt=skip)

    if hasattr(element, "tag"):
        attrs = None
        if hasattr(element, "attributes"):
            attrs = {(attr.name).decode("utf-8"): (attr.value).decode("utf-8")
                     for attr in element.attributes}
        result = handle_tag(str(element.tag), result, list_indent, attrs, noFmt)
    return result


def dump_ast_gumbo(element: gumbo.Node, indent=0):
    sindent = (" " * indent)
    if hasattr(element, "type"):
        if str(element.type) == "TEXT":
            print(sindent + "With text -->" + element.contents.text.decode("utf-8"),
                  file=sys.stderr)

    if hasattr(element, "children"):
        for child in element.children:
            dump_ast_gumbo(child, indent + 2)

    if hasattr(element, "tag"):
        print(sindent + str(element.tag), file=sys.stderr)


if (len(sys.argv) > 1):
    filename = sys.argv[1]
else:
    print("Usage: html_to_org HTMLFILENAME")
    quit(1)

with open(filename) as f:
    input = f.read()

with gumbo.gumboc.parse(input) as output:
    # dump_ast_gumbo(output.contents.root.contents)
    print(html_to_org_gumbo(output.contents.root.contents))
