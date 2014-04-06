#consume = (text, token) ->
#
#  if text.substr 0, token.length == token
#    match = text.substr(0, token.length)
#    text = text.substr(token.length)
#    match
#
#  false


# Missing: escaping
#spit = (text, token) ->
#
#  str = ''
#  while text.length > 0
#    if  text.substr 0, token.length == token
#      true
#    str += text.substr 0, 1
#    text = text.substr 1
#
#  false



#  HELLO WORLD
#
#
#  rule say
#    'say' string 'to the World'
#  do
#    alert string
#
#  say 'Hello!' to the World
#
#
#-------------------------
#
#
#  sayMethods = {
#    theWorld: (msg) ->
#      alert msg
#    theConsole: (msg) ->
#      console.log msg
#  }
#
#  rule say
#    'say' string 'to' identifier
#  do
#    sayMethods[identifier](string)
#
#
#  say 'Hello!' to theWorld


# TODO: If javascript engines are not optimizing string handling (substr, string copy),
#       use a counter to consume string, and for backtraking (parseSingleExpr)
# TODO: XRegExp for Unicode support


zeroOrMany = '*'
oneOrMany = '+'
zeroOrOne = '?'

renameParentRule: (child, parentName) ->
  for el, idx in child
    if typeof el is "object"
      mergeChildRule(el)
    else if (el == 'super')
      child[i] = parentName
  return child


class bnf

  @identifier: /[a-zA-Z][a-zA-Z0-9_]+/

  #excluding \n
  @whitespace: /[^\n\S]+/

  @newline: /\n/

  @whites: /\s+/

  @string: ///
             "
             (?:
               [^\\"]
               | \\.
             )*
             "
           ///

  @block:
    parse: [
      /\(/
      'BNFExpr'
      /\)/
    ]

  @cardinality:
      parse: [
        /\*/
        /\+/
        /\?/
      ]
      logic: 'OR'
      cardinality: zeroOrOne

  @terminal:
    parse: [
      'identifier'
      'string'
      'block'
    ]
    logic: 'OR'
    do: (parseTree) ->
      if parseTree.identifier?
        parseTree.parse = parseTree.identifier[0].parsed
        delete parseTree.identifier
      else if parseTree.string?
        pat = parseTree.string[0].parsed
        pat = pat.substr 1, pat.length - 2
        parseTree.parse = ///
                 ^ #{pat}
              ///
        delete parseTree.string
      else
        parseTree.parse = parseTree.block[0].BNFExpr[0]
        delete parseTree.block
      delete parseTree.parsed

  @group:
    parse: [
      'terminal'
      'cardinality'
    ]
    cardinality: oneOrMany
    do: (parseTree) ->
      parseTree.parse = parseTree.terminal[0].parse
      delete parseTree.terminal
      if parseTree.cardinality?
        parseTree.cardinality = parseTree.cardinality[0].parsed

  @OrExpr:
    parse: [
      /\|/
      'group'
    ]
    cardinality: zeroOrMany

  @BNFExpr:
    parse: [
        'group'
        'OrExpr'
    ]
    do: (parseTree) ->
      if (not parseTree.OrExpr)
        parseTree.OrExpr = []
      else
        parseTree.logic = 'OR'
      parseTree.OrExpr.unshift({group: parseTree.group})
      delete parseTree.group
      parseTree.parse = parseTree.OrExpr
      delete parseTree.OrExpr
      for expr,i in parseTree.parse
        parseTree.parse[i] = expr.group[0]

  @ruleExpr:
    parse: 'BNFExpr'
    idented: true

  @script_block:
    parse: 'TODO'
    indented: true

  @output_block:
    parse: 'TODO'
    indented: true

  @ruleScript:
    parse: [
      /do/
      'scriptBlock'
    ]
    cardinality: zeroOrOne

  @ruleOutput:
    parse: [
      /as/
      'outputBlock'
    ]
    cardinality: zeroOrOne

  @rule:
    parse : [
      /rule/
      'identifier'
      'ruleExpr'
      'ruleScript'
      'ruleOutput'
    ]
    
    spawnChild: (ruleName, ruleBody) ->
      parentCount = 0
      if (bnf[ruleName].parentCount?)
        parentCount = bnf[ruleName].parentCount
      parentName = ruleName + "_parent" + bnf[ruleName].parentCount
      ruleBody = renameParentRule(ruleBody.parse)
      ruleBody.super = (parseTree) ->
        bnf[parentName].do(pasteTree)
      ruleBody.parentCount = parentCount + 1
      bnf[parentName] = this
      bnf[ruleName] = ruleBody
    
    do: (parseTree) ->
      delete parseTree.ruleExpr[0].BNFExpr[0].parsed
      ruleName = parseTree.identifier[0].parsed
      ruleBody = parseTree.ruleExpr[0].BNFExpr[0]
      if bnf[ruleName]?
        this.spawnChild(ruleName, ruleBody)
      else
        bnf[ruleName] = ruleBody #ruleName
        if not bnf.altroot?
          bnf.altroot = ruleName
          bnf.root.parse.push ruleName



  @root:
    parse : [
      'rule'
    ]
    cardinality: zeroOrMany
    logic: 'OR'



  

class lInfiniJSBase

  consume: (opts, token) ->
    tokenStr = token.source
    if tokenStr.charAt(0) != '^'
      tokenStr = '^' + tokenStr

    pat = new RegExp(tokenStr)

    if (match = opts.text.match(pat)) == null
      return false

    opts.text = opts.text.substring(match[0].length)

    return match[0]


  error: (message) ->
    throw message

  parseRegexpToken: (opts, token, parseTree) ->
    return this.consume opts, token

  parseRuleToken: (opts, token, parseTree) ->
    return this.parseExpr opts, opts.grammar[token], token, parseTree

  parseToken: (opts, token, parseTree) ->
    #this.process_whites(opts)
    #if parseTree.indent.length < opts.indents[opts.indents.length - 1].length
    #throw "Indentation Error"

    if token.constructor == RegExp
      return this.parseRegexpToken opts, token, parseTree
    else if typeof token is 'string'
      return this.parseRuleToken opts, token, parseTree
    else
      return this.parseExpr opts, token, null, parseTree

  parseGroup: (opts, rule, ruleName, parseTree) ->
    expr = rule.parse ? rule

    if (expr.length == undefined or typeof expr == 'string')
      this.parseToken(opts, expr, parseTree)
    else
      textBak = opts.text
      parsed = true
      for token in expr
        if (parsed = this.parseToken(opts, token, parseTree)) == false
          opts.text = textBak
        # Coffee Script! Where are Exclusive Ors!
        if (rule.logic == 'OR' and parsed != false) or
           (rule.logic != 'OR' and parsed == false)
          return parsed

      return parsed

  parseSingleExpr: (opts, rule, ruleName, parseTree) ->
    textBak = opts.text
    ltree = {}
    ltree.indent = parseTree.indent
    parsed = this.parseGroup opts, rule, ruleName, ltree
    if parsed != false
      ltree.parsed = parsed
      if rule.do?
        rule.do(ltree)
      if ruleName?
        if not parseTree[ruleName]?
          parseTree[ruleName] = []
        parseTree[ruleName].push ltree
    else
      opts.text = textBak
    return parsed

  #TODO: Missing backtracking on cardinality operators
  parseExpr: (opts, rule, ruleName, parseTree) ->

    if rule.cardinality == zeroOrMany or rule.cardinality == oneOrMany
      count = 0
      count += 1 while this.parseSingleExpr(opts, rule, ruleName, parseTree)

      if count > 0 or
         rule.cardinality == zeroOrMany
        return true
      else
        return false
    else
      parsed = this.parseSingleExpr opts, rule, ruleName, parseTree
      if rule.cardinality == zeroOrOne then return true else return parsed

  process_tree: (opts) ->
    parseTree = {}
    opts.debug = ''
    opts.debug_indent = ''
    opts.indents = []
    opts.whites_parsed_pos = opts.text.length + 1
    [lf_present, whites] = this.parse_whites(opts)
   # opts.indents.push whites
   # opts.cur_indent = whites
    parseTree.indent = whites
    this.parseExpr opts, opts.grammar.root, 'root', parseTree
    return parseTree


class lInfiniJSWhites extends lInfiniJSBase

  parse_whites: (opts) ->
    if opts.whites_parsed_pos > opts.text.length
      opts.whites = this.consume(opts, opts.grammar.whites)
      if opts.whites == false
        opts.lf_present = false
        opts.whites = ''
      else
        lf = opts.whites.lastIndexOf('\n')
        opts.lf_present = true
        if lf == -1
          opts.lf_present = false
        else
          opts.whites = opts.whites.substr(lf + 1)
      opts.whites_parsed_pos = opts.text.length

    return [opts.lf_present, opts.whites]

  parseToken: (opts, token, parseTree) ->
    ret = super opts, token, parseTree
    if ret != false
      this.parse_whites(opts)
    return ret





class lInfiniJSIndent extends lInfiniJSWhites

  indent_fail: (opts, parseTree) ->
    return opts.lf_present and
    opts.whites.length < parseTree.indent.length


  parseRegexpToken: (opts, token, parseTree) ->
    ret = super opts, token, parseTree
    if this.indent_fail(opts, parseTree) then return false else return ret


  parseExpr: (opts, rule, ruleName, parseTree) ->

    if rule.indented
      #if indents.length > 1 and not indents.slice(-1) >= indents[-2..-2]
      if (not opts.lf_present) or
      not opts.whites.length > parseTree.indent
        if rule.cardinality == zeroOrMany or
        rule.cardinality == zeroOrOne
          return true
        else
          # Do we want to allow fallback in that case? Or maybe we want 2 separate features?
          throw "Indentation error"

      parseTree.indent = opts.whites

    else
      if this.indent_fail(opts, parseTree)
        if rule.cardinality == zeroOrMany or
        rule.cardinality == zeroOrOne
          return true
        else
          return false

    return super(opts, rule, ruleName, parseTree)




class lInfiniJSCheck extends lInfiniJSIndent
  parseExpr: (opts, rule, ruleName, parseTree) ->
    if not rule?
      throw 'Rule ' + ruleName + ' is not defined'

    return super(opts, rule, ruleName, parseTree)



class lInfiniJSLog extends lInfiniJSCheck
  parseExpr: (opts, rule, ruleName, parseTree) ->
    if ruleName?
      opts.debug += opts.debug_indent + ruleName + '\n'
    ret = super(opts, rule, ruleName, parseTree)
    if ruleName?
      opts.debug += opts.debug_indent + ruleName + ' '
      if ret != false
        opts.debug += 'true\n'
      else
        opts.debug += 'false\n'
    return ret

  parseRuleToken: (opts, token, parseTree) ->
    opts.debug_indent += '  '
    ret = super opts, token, parseTree
    opts.debug_indent = opts.debug_indent.substr(2)
    return ret




#  process_whites: (opts) ->
#    [lf_present, whites] = this.parse_whites(opts)
#    if (lf_present == false)
#      return whites
#
#    (opts.indents = opts.indents[0...-1]) while whites.length < opts.indents[opts.indents.length - 1].length
#
#    if opts.indents.length == 0
#      throw "Indentation Error"
#
#    opts.cur_indent = whites







#    '[': (text, node) ->
#      spit text, ']'
#      node.push parse node, block
#      if consume text, ']' is false
#        error 'Expected \']\''






`InfiniJS = new lInfiniJSLog;`
`gBNF =  bnf;`

