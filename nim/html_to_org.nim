import gumbo
import algorithm
import parseopt
import tables
import sequtils
import httpclient
import os
import strutils

proc writeHelp()=
  echo getAppFilename() & " *.html"

proc writeVersion()=
  echo "v0.01"

var
  filename = ""
for kind, key, val in getopt():
  case kind
  of cmdArgument:
    filename = key
  of cmdLongOption, cmdShortOption:
    case key
      of "help", "h": writeHelp()
      of "version", "v": writeVersion()
      else:
        discard
  of cmdEnd: assert(false) # cannot happen
if filename == "":
  # no filename has been given, so we show the help:
  writeHelp()
  quit(1)

var is_http  = false
if filename.startsWith("http") or filename.startsWith("https"):
  is_http = true
type options_t = object
    full_rewrap: bool

var options : options_t = options_t(full_rewrap:false)

let show_debug = false
import times
import htmlparser
let n1 = epochtime()
if is_http == false:
  let nim_html = loadHtml(filename)  ## measurement purposes
let n2 = epochtime()

import htmlgen
let g1 = epochtime()
var html = ""
if is_http:
  var client = newHttpClient()
  html = client.getContent(filename)
else:
  html = readFile(filename)

var out1 = gumbo.gumbo_parse(html)
let g2 = epochtime()

# root
var root = out1.root[]

if show_debug:
  stderr.write "root: " & $gumbo_normalized_tagname( root.v.element.tag) &
    "with " & $root.v.element.children.length & " children"


proc tableify_attributes (gv:GumboVector): Table[string, string]=
  result = initTable[string,string]()

  let GRchildrenVector = gv
  for i in countUp[int](a=0,b=int(GRchildrenVector.length)-1):
    let test = GRchildrenVector.data
    var nodeP = cast[ptr ptr GumboAttribute](cast[int](test) +% i* sizeof(ptr pointer) ) # pointer arithmagic
    var node = nodeP[][]
    let name = $node.name
    let value = $node.value
    result.add(name, value)

proc tag_toStr(tag: GumboTag): string=
  result = ($tag).replace("GUMBO_TAG_", "")


proc trimIt(input:string, leading:bool=true, trailing:bool=true):string {.procvar.}=
  result = input
  if result in ["\n"]:
    result = ""
  while (result.startsWith(" ") or result.startsWith("\n") or result.startsWith("\t")):
    result = result[1..result.len-1]
  while (result.endsWith(" ") or result.endsWith("\n") or result.endsWith("\t")):
    result = result[0..result.len - 2]

var unknown = initTable[string, int]()

#import templates
template foreach_child(node:untyped,children:GumboVector, body:untyped):untyped=
  for i in countUp[int](a=0,b=int(children.length)-1):
    let test = children.data
    let nodeP = cast[ptr ptr GumboNode](cast[int](test) +% i* sizeof(ptr pointer) ) # pointer arithmagic
    node = nodeP[][]
    body

proc print_ngumbo_to_org*(gumbon: GumboNode, list_indent:int=0, noFmt:openArray[string]=[]):string=
  result = ""
  let gelem = gumbon.v.element
  let attributes = tableify_attributes(gelem.attributes)
  let tagStr = tag_toStr(gelem.tag)
  var list_indent_local = list_indent
  if (gelem.tag in {GUMBO_TAG_H1, GUMBO_TAG_H2, GUMBO_TAG_H3}):
    list_indent_local = 3

  if (gelem.tag in {GUMBO_TAG_UL, GUMBO_TAG_DL, GUMBO_TAG_OL}):
    list_indent_local = list_indent + 3
  var skip :seq[string] = @[]

  var child:GumboNode
  foreach_child(child,gelem.children):
    if(child.`type` == GUMBO_NODE_ELEMENT):
      if tagStr == "CODE" and tag_toStr(gelem.tag) == "PRE":
        skip.add("PRE")
      if tagStr == "PRE" and tag_toStr(gelem.tag) == "CODE":
        skip.add("CODE")
      result &= print_ngumbo_to_org(child, list_indent_local, skip)
    if(child.`type` == GUMBO_NODE_TEXT):
      result &= ($child.v.text.text).trimIt
    if(child.`type` == GUMBO_NODE_DOCUMENT):
      stderr.write "no impl"


  if defined(result) and result.trimIt == "" :
     return result

  proc wrap(input:string, prefix,suffix: string, add_space:bool=false, add_newlines:bool=false ):string=
    var bprefix = prefix
    var asuffix = suffix
    if add_space:
      bprefix = " " & prefix
      asuffix = suffix & " "

    result = bprefix & input & asuffix

  proc wrap(input:string, wrapStr: string, add_space:bool=false, add_newlines:bool=false ):string=
    wrap(input, wrapStr, wrapStr, add_space, add_newlines)

  proc fill(s:string, width:int=90):string=
    result = wordWrap(s.split("\n").mapIt(trimIt(it)).join(" "), maxLineWidth = width, splitLongWords = false)

  proc arrange_list_item(s:string, indent_prefix:string):string=
    result = fill(s)
    result = indent(result, len(indent_prefix))
    result = trimIt(result, trailing=false)

  if(tagStr in noFmt):
    return result

  case tagStr:
    of "H1" , "H2" , "H3", "H4", "H5", "H6":
      let tag_s = tagStr.replace("H", "")
      let level = parseInt($tag_s[0])
      result = repeat("*", level) & " " & result & "\n"
      if attributes.contains("id"):
        stderr.write tagStr & ": " & attributes["id"] & "\n"

    of "TITLE":
      result = "\n#+TITLE: " & result & "\n"

    of "STRONG", "B":
      result = wrap(result, "*", true)

    of "TT":
      result = wrap(result, "=", true)

    of "EM":
      result = wrap(result, "*", true)

    of "I":
      result = wrap(result, "/", true)

    of "DEL":
      result = wrap(result, "+", true)

    of "SUB":
      result = wrap(result, "_{","}", false)

    of "SUP":
      result = wrap(result, "^{","}", false)

    of "P":
      if options.full_rewrap:
        result = wordWrap(result.split("\n").mapIt(trimIt(it)).join(" "), splitLongWords = false)
      result = result & "\n\n"

    of "BR":
      result = result & "\n\n"

    of "TABLE":
      result = wrap(result, "\n")

    of "CODE", "PRE":
      if result.find("\n") == -1 and result.len < 15:
        result = "=" & result & "="
      else:
        if(result.startsWith(" =") and result.endSwith("= ")):
          result = result[2..result.len-3]
        result = "#+BEGIN_SRC\n" & result & "\n#+END_SRC\n\n"

    of "TR":
      result &= "\n"

    of "TD":
      result = " | " & result & " | "

    of "UL", "OL":
      result = result & "\n"

    of "A":
      while result.startsWith("["):
        result = result[1..result.len-1]
      while result.endsWith("]"):
        result = result[0..result.len-2]
      if  attributes.contains("href" ):
        if result == "":
          result = " [[" & attributes["href"].trimIt & "]] "
        else:
          result = (attributes["href"].trimIt & "][" & result).wrap("[[","]]", add_space = true)

    of "DL":
      result =  result & "\n"

    of "DT":
      result = repeat(" ", list_indent_local) & "- " & result & " :: "

    of "DD":
      result = arrange_list_item(result, repeat(" ", list_indent_local) & "  ")
      result = result & "\n"

    of "LI":
      result = arrange_list_item(result, repeat(" ", list_indent_local) & "  ")
      result = repeat(" ", list_indent_local) & "- " &  result & "\n"

    of "DIV", "SPAN":
      discard

    of "NAV", "META", "LINK", "SCRIPT", "STYLE":
      result = ""
    else:
      if unknown.contains($gelem.tag):
        unknown[$(gelem.tag)] = unknown[$gelem.tag]+1
      else:
        unknown.add($gelem.tag, 0)


echo print_ngumbo_to_org(root)

if show_debug:
  let g3 = epochtime()

  stderr.write "\nunknown key type:\n"
  for key in unknown.keys:
    stderr.write "  - " & key & "\n"

  stderr.write "\nTiming: \n"
  stderr.write "  - gumbo:" & $(g2-g1) & " + " & $(g3-g2) & "\n"
  stderr.write "  - nim:" & $(n2-n1) & "\n"


proc dump_ast*(gumbon: GumboNode, indent:int=0)=
  let gelem = gumbon.v.element
  let ide = repeat(" ", indent)
  stderr.write ide & " " & tag_toStr(gelem.tag) & "\n"
  var child:GumboNode
  foreach_child(child,gelem.children):
    if(child.`type` == GUMBO_NODE_ELEMENT):
      dump_ast(child, indent + 2 )
    if(child.`type` == GUMBO_NODE_TEXT):
      stderr.write ide & "  " & "with text --> " & escape(($child.v.text.text).trimIt) & "\n"
    if(child.`type` == GUMBO_NODE_DOCUMENT):
      stderr.write "no impl"

if show_debug:
  dump_ast(root)


# Local Variables:
# firestarter: "nim -d:release -d:ssl c %f || notify-send -u low 'nim' 'compil%f'"
# End:
