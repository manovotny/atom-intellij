{ Context } = require '../vender/esrefactor'
{ parse } = require './parser'
{ Range } = require 'atom'
d = (require 'debug') 'ripper'

module.exports =
class Ripper

  @locToRange: ({ start, end }) ->
    new Range [ start.line - 1, start.column ], [ end.line - 1, end.column ]

  @scopeNames: [
    'source.js'
    'source.js.jsx'
    'source.babel'
  ]

  parseOptions:
    loc: true
    range: true
    tokens: true
    tolerant: true
    sourceType: 'module'
    allowReturnOutsideFunction: true
    features:
      # stage 2
      'es7.asyncFunctions': true
      'es7.exponentiationOperator': true
      'es7.objectRestSpread': true
      # stage 1
      'es7.decorators': true
      'es7.exportExtensions': true
      'es7.trailingFunctionCommas': true
      # TODO: wait estraverse support the new Node types (eg. BindingNode)
      # stage 0
      # 'es7.classProperties': true
      # 'es7.comprehensions': true
      # 'es7.doExpressions': true
      # 'es7.functionBind': true

  constructor: ->
    @context = new Context

  destruct: ->
    delete @context

  parse: (code, callback) ->
    try
      d 'parse', code
      rLine = /.*(?:\r?\n|\n?\r)/g
      @lines = (result[0].length while (result = rLine.exec code)?)
      @parseError = null
      @context.setCode code, @parseOptions
      callback() if callback
    catch err
      { loc, message } = @parseError = err
      if loc? and message?
        { line, column } = loc
        lineNumber = line - 1
        callback [
          range  : new Range [lineNumber, column], [lineNumber, column + 1]
          message: message
        ] if callback
      else
        d 'unknown error', err
        callback() if callback

  find: ({ row, column }) ->
    return if @parseError?
    d 'find', row, column
    pos = 0
    while --row >= 0
      pos += @lines[row]
    pos += column

    identification = @context.identify pos
    d 'identification at', pos, identification
    return [] unless identification

    { declaration, references } = identification
    if declaration? and not (declaration in references)
      references.unshift declaration
    ranges = []
    for reference in references
      ranges.push Ripper.locToRange reference.loc
    ranges
