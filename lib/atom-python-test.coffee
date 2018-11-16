AtomPythonTestView = require './atom-python-test-view'
{CompositeDisposable} = require 'atom'

module.exports = AtomPythonTest =

  atomPythonTestView: null

  modalPanel: null

  subscriptions: null

  config:
    pythonExecutableDirectory:
      type: 'string'
      default: ''
      title: 'Path of python executable. May be set if you have a setting that is not supported by the plugin default configuration. Example: /usr/bin/python3'
      order: 1
    serviceName:
      type: 'string'
      default: ''
      title: 'Name of the service to run tests against'
      order: 2
    executeDocTests:
      type: 'boolean'
      default: false
      title: 'Execute doc tests on test runs'
      order: 3
    outputColored:
      type: 'boolean'
      default: false
      title: 'Color the output'
      order: 4
    onlyShowPanelOnFailure:
      type: 'boolean'
      default: false
      title: 'Only show test panel on test failure'
      order: 5

  activate: (state) ->

    @atomPythonTestView = new AtomPythonTestView(state.atomPythonTestViewState)

    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-python-test:run-all-tests': => @runAllTests()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-python-test:run-test-under-cursor': => @runTestUnderCursor()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-python-test:close-panel': => @closePanel()
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-python-test:run-all-project-tests': => @runAllProjectTests()


  deactivate: ->
    @subscriptions.dispose()
    @atomPythonTestView.destroy()

  serialize: ->
    atomPythonTestViewState: @atomPythonTestView.serialize()

  executePyTest: (filePath) ->
    {BufferedProcess} = require 'atom'

    @tmp = require('tmp');

    @atomPythonTestView.clear()

    # display of panel depends on onlyShowPanelOnFailure
    @onlyShowPanelOnFailure = atom.config.get('atom-python-test.onlyShowPanelOnFailure')
    if @onlyShowPanelOnFailure
      @atomPythonTestView.destroy()
    else
      @atomPythonTestView.toggle()

    stderr = (output) ->
      console.log(output)

    stdout = (output) ->
      atomPythonTestView = AtomPythonTest.atomPythonTestView
      doColoring = atom.config.get('atom-python-test.outputColored')
      atomPythonTestView.addLine output, doColoring

    exit = (code) =>
      atomPythonTestView = AtomPythonTest.atomPythonTestView

      if @onlyShowPanelOnFailure and atomPythonTestView.message.includes("success-line") #pytest retrun succes
        statusBar = document.getElementsByClassName('status-bar')[0]
        statusBar.style.background = "green"
        setTimeout ->
          statusBar.style.background = "" # show green status bar while one second  on sucess
        , 500
      else
        atomPythonTestView.toggle() #show panel if pytest is not success

      junitViewer = require('junit-viewer')
      parsedResults = junitViewer.parse(AtomPythonTest.testResultsFilename.name)

      if parsedResults.junit_info.tests.error > 0 and code != 0
        atomPythonTestView.addLine "An error occured while executing py.test.
          Check if py.test is installed and is in your path."

    @testResultsFilename = @tmp.fileSync({prefix: 'results', keep : true, postfix: '.xml'});

    executeDocTests = atom.config.get('atom-python-test.executeDocTests')

    pythonExecutableDirectory = atom.config.get('atom-python-test.pythonExecutableDirectory')

    console.log(pythonExecutableDirectory)

    if pythonExecutableDirectory and !!pythonExecutableDirectory
      command = pythonExecutableDirectory
    else
      command = 'docker'

    serviceName = atom.config.get('atom-python-test.serviceName')

    substrIdx = filePath.indexOf serviceName
    modulePath = filePath.substr substrIdx+serviceName.length+1

    if modulePath.startsWith('src')
      modulePath = modulePath.substr 4  # remove 'src/' before the module path

    args = ['exec', '--env', 'PYTHONPATH=/service']
    finalArgs = ['python', '-m', 'pytest', '-x', '-vv', "#{modulePath}"]
    if serviceName
      args = args.concat serviceName.split " "
      args = args.concat finalArgs

    process = new BufferedProcess({command, args, stdout, exit, stderr})


  runTestUnderCursor: ->
    editor = atom.workspace.getActiveTextEditor()
    file = editor?.buffer.file
    filePath = file?.path
    selectedText = editor.getSelectedText()

    testLineNumber = editor.getCursorBufferPosition().row
    testIndentation = editor.indentationForBufferRow(testLineNumber)

    class_re = /class \w*\((\w*.*\w*)*\):/
    buffer = editor.buffer

    # Starts searching backwards from the test line until we find a class. This
    # guarantee that the class is a Test class, not an utility one.
    reversedLines = buffer.getLines()[0...testLineNumber].reverse()

    for line, i in reversedLines
      # startIndex = line.search(class_re)
      isClassLine = line.startsWith("class")

      classLineNumber = testLineNumber - i - 1

      # We think that we have found a Test class, but this is guaranteed only if
      # the test indentation is greater than the class indentation.
      classIndentation = editor.indentationForBufferRow(classLineNumber)
      # if startIndex != -1 and testIndentation > classIndentation
      if isClassLine and testIndentation > classIndentation
        if line.includes('(')
          endIndex = line.indexOf('(')
        else
          endIndex = line.indexOf(':')
        className = line[6...endIndex]
        filePath = filePath + '::' + className
        break

    re = /test(\w*|\W*)/;
    content = editor.buffer.getLines()[testLineNumber]
    endIndex = content.indexOf('(')
    startIndex = content.search(re)
    testName = content[startIndex...endIndex]

    if testName
      filePath = filePath + '::' + testName
      @executePyTest(filePath)

  runAllTests: () ->
    editor = atom.workspace.getActivePaneItem()
    file = editor?.buffer.file
    filePath = file?.path
    @executePyTest(filePath)

  runAllProjectTests: () ->
    editor = atom.workspace.getActivePaneItem()
    fullPath = atom.project.relativizePath(editor.getBuffer().file.path)
    @executePyTest(fullPath[0])

  closePanel: ->
      @atomPythonTestView.destroy()
