Watcher = require './watcher'
ModuleManager = require './module_manager'
{ packages: packageManager } = atom
d = (require 'debug') 'refactor'

module.exports =
new class Main

  renameCommand: 'refactor:rename'
  doneCommand: 'refactor:done'

  config:
    highlightError:
      type: 'boolean'
      default: true
    highlightReference:
      type: 'boolean'
      default: true


  ###
  Life cycle
  ###

  activate: (state) ->
    d 'activate'
    @moduleManager = new ModuleManager
    @watchers = []

    atom.workspace.observeTextEditors @onCreated
    atom.commands.add 'atom-text-editor', @renameCommand, @onRename
    atom.commands.add 'atom-text-editor', @doneCommand, @onDone

  deactivate: ->
    @moduleManager.destruct()
    delete @moduleManager
    for watcher in @watchers
      watcher.destruct()
    delete @watchers

    atom.workspaceView.off @renameCommand, @onRename
    atom.workspaceView.off @doneCommand, @onDone

  serialize: ->


  ###
  Events
  ###

  onCreated: (editor) =>
    watcher = new Watcher @moduleManager, editor
    watcher.on 'destroyed', @onDestroyed
    @watchers.push watcher

  onDestroyed: (watcher) =>
    watcher.destruct()
    @watchers.splice @watchers.indexOf(watcher), 1

  onRename: (e) =>
    isExecuted = false
    for watcher in @watchers
      isExecuted or= watcher.rename()
    d 'rename', isExecuted
    return if isExecuted
    e.abortKeyBinding()

  onDone: (e) =>
    isExecuted = false
    for watcher in @watchers
      isExecuted or= watcher.done()
    return if isExecuted
    e.abortKeyBinding()
