{ EventEmitter2 } = require 'eventemitter2'
d = (require 'debug') 'watcher'

module.exports =
class Watcher extends EventEmitter2

  constructor: (@moduleManager, @editor) ->
    super()
    #@editor.on 'grammar-changed', @verifyGrammar

    @editor.onDidDestroy @onDestroyed
    @editor.onDidStopChanging @onBufferChanged
    @editor.onDidChangeCursorPosition @onCursorMoved

    @verifyGrammar()
    @moduleManager.on 'changed', @verifyGrammar

  destruct: =>
    @removeAllListeners()
    @deactivate()
    #@editor.off 'grammar-changed', @verifyGrammar
    @moduleManager.off 'changed', @verifyGrammar

    delete @moduleManager
    delete @editor
    delete @module

  onDestroyed: =>
    return unless @eventDestroyed
    @emit 'destroyed', @


  ###
  Grammar valification process
  1. Detect grammar changed.
  2. Destroy instances and listeners.
  3. Exit process when the language plugin of the grammar can't be found.
  4. Create instances and listeners.
  ###

  verifyGrammar: =>
    scopeName = @editor.getGrammar().scopeName
    module = @moduleManager.getModule scopeName
    d 'verify grammar', scopeName, module
    return if module is @module
    @deactivate()
    return unless module?
    @module = module
    @activate()

  activate: ->
    # Setup model
    @ripper = new @module.Ripper()

    # Start listening
    @eventCursorMoved = on
    @eventDestroyed = on
    @eventBufferChanged = on

    d 'activate and parse'
    @parse()

  deactivate: ->
    # Stop listening
    @cursorMoved = false

    @eventCursorMoved = off
    @eventDestroyed = off
    @eventBufferChanged = off
    clearTimeout @bufferChangedTimeoutId
    clearTimeout @cursorMovedTimeoutId

    # Destruct instances
    @ripper?.destruct()

    # Remove references
    delete @bufferChangedTimeoutId
    delete @cursorMovedTimeoutId
    delete @module
    delete @ripper
    delete @renamingCursor
    delete @renamingMarkers


  ###
  Reference finder process
  1. Stop listening cursor move event and reset views.
  2. Parse.
  3. Show errors and exit process when compile error is thrown.
  4. Show references.
  5. Start listening cursor move event.
  ###

  parse: =>
    d 'parse'
    @eventCursorMoved = off
    text = @editor.buffer.getText()
    if text isnt @cachedText
      @destroyReferences()
      @destroyErrors()
      @cachedText = text
      @ripper.parse text, @onParseEnd
    else
      @onParseEnd()
    @eventCursorMoved = on

  onParseEnd: (errors) =>
    if errors?
      @createErrors errors
    else
      @createReferences()

  destroyErrors: ->
    d 'destroy errors'
    return unless @errorMarkers?
    for marker in @errorMarkers
      marker.destroy()
    delete @errorMarkers

  createErrors: (errors) =>
    d 'create errors'
    @errorMarkers = for { range, message } in errors
      marker = @editor.markBufferRange range
      d 'marker', range, marker
      @editor.decorateMarker marker, type: 'highlight', class: 'refactor-error'
      @editor.decorateMarker marker, type: 'line-number', class: 'refactor-error'
      # TODO: show error message
      marker

  destroyReferences: ->
    return unless @referenceMarkers?
    for marker in @referenceMarkers
      marker.destroy()
    delete @referenceMarkers

  createReferences: ->
    ranges = @ripper.find @editor.getSelectedBufferRange().start
    return unless ranges? and ranges.length > 0
    @referenceMarkers = for range in ranges
      marker = @editor.markBufferRange range
      @editor.decorateMarker marker, type: 'highlight', class: 'refactor-reference'
      marker


  ###
  Renaming life cycle.
  1. When detected rename command, start renaming process.
  2. When the cursors move out from the symbols, abort and exit renaming process.
  3. When detected done command, exit renaming process.
  ###

  rename: ->
    # When this editor isn't active, returns false to abort keyboard binding.
    return false unless @isActive()

    # Find references.
    # When no reference exists, do nothing.
    cursor = @editor.getLastCursor()
    ranges = @ripper.find cursor.getBufferPosition()
    return false unless ranges? and ranges.length > 0

    # Pause highlighting life cycle.
    @destroyReferences()
    @eventBufferChanged = off
    @eventCursorMoved = off

    #TODO Cursor::clearAutoScroll()

    # Register the triggered cursor.
    @renamingCursor = cursor
    # Select references.
    # Register the markers of the references' ranges.
    # Highlight these markers.
    @renamingMarkers = for range in ranges
      @editor.addSelectionForBufferRange range
      marker = @editor.markBufferRange range
      @editor.decorateMarker marker, type: 'highlight', class: 'refactor-reference'
      marker
    # Start renaming life cycle.
    @eventCursorMoved = off
    @eventCursorMoved = 'abort'

    # Returns true not to abort keyboard binding.
    true

  abort: =>
    # When this editor isn't active, do nothing.
    return unless @isActive() and @renamingCursor? and @renamingMarkers?

    # Verify all cursors are in renaming markers.
    # When the cursor is out of marker at least one, abort renaming.
    selectedRanges = @editor.getSelectedBufferRanges()
    isMarkersContainsCursors = true
    for marker in @renamingMarkers
      markerRange = marker.getBufferRange()
      isMarkerContainsCursor = false
      for selectedRange in selectedRanges
        isMarkerContainsCursor or= markerRange.containsRange selectedRange
        break if isMarkerContainsCursor
      isMarkersContainsCursors and= isMarkerContainsCursor
      break unless isMarkersContainsCursors
    return if isMarkersContainsCursors
    @done()

  done: ->
    # When this editor isn't active, returns false for aborting keyboard binding.
    return false unless @isActive() and @renamingCursor? and @renamingMarkers?

    # Stop renaming life cycle.
    @eventCursorMoved = off

    # Reset cursor's position to the triggerd cursor's position.
    @editor.setCursorBufferPosition @renamingCursor.getBufferPosition()
    delete @renamingCursor
    # Remove all markers for renaming.
    for marker in @renamingMarkers
      marker.destroy()
    delete @renamingMarkers

    # Start highlighting life cycle.
    d 'done and reparse'
    @parse()
    @eventBufferChanged = on
    @eventCursorMoved = on

    # Returns true not to abort keyboard binding.
    true


  ###
  User events
  ###

  onBufferChanged: =>
    return unless @eventBufferChanged
    d 'buffer changed'
    @parse()

  onCursorMoved: =>
    return unless @eventCursorMoved
    if @eventCursorMoved == 'abort'
      @abort()
    else
      clearTimeout @cursorMovedTimeoutId
      @cursorMovedTimeoutId = setTimeout @onCursorMovedAfter, 100

  onCursorMovedAfter: =>
    @destroyReferences()
    @createReferences()


  ###
  Utility
  ###

  isActive: ->
    @module? and atom.workspace.getActivePaneItem() is @editor

  # Range to pixel based start and end range for each row.
  rangeToRows: ({ start, end }) ->
    for raw in [start.row..end.row] by 1
      rowRange = @editor.buffer.rangeForRow raw
      point =
        left : if raw is start.row then start else rowRange.start
        right: if raw is end.row then end else rowRange.end
      pixel =
        tl: @editorView.pixelPositionForBufferPosition point.left
        br: @editorView.pixelPositionForBufferPosition point.right
      pixel.br.top += @editorView.lineHeight
      pixel
