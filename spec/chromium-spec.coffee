assert = require 'assert'
http = require 'http'
https = require 'https'
path = require 'path'
ws = require 'ws'

{remote} = require 'electron'
{BrowserWindow, session} = remote.require 'electron'

describe 'chromium feature', ->
  fixtures = path.resolve __dirname, 'fixtures'

  listener = null
  afterEach ->
    if listener?
      window.removeEventListener 'message', listener
    listener = null

  xdescribe 'heap snapshot', ->
    it 'does not crash', ->
      process.atomBinding('v8_util').takeHeapSnapshot()

  describe 'sending request of http protocol urls', ->
    it 'does not crash', (done) ->
      @timeout 5000
      server = http.createServer (req, res) ->
        res.end()
        server.close()
        done()
      server.listen 0, '127.0.0.1', ->
        {port} = server.address()
        $.get "http://127.0.0.1:#{port}"

  describe 'document.hidden', ->
    url = "file://#{fixtures}/pages/document-hidden.html"
    w = null

    afterEach ->
      w?.destroy()

    it 'is set correctly when window is not shown', (done) ->
      w = new BrowserWindow(show:false)
      w.webContents.on 'ipc-message', (event, args) ->
        assert.deepEqual args, ['hidden', true]
        done()
      w.loadURL url

    it 'is set correctly when window is inactive', (done) ->
      w = new BrowserWindow(show:false)
      w.webContents.on 'ipc-message', (event, args) ->
        assert.deepEqual args, ['hidden', false]
        done()
      w.showInactive()
      w.loadURL url

  xdescribe 'navigator.webkitGetUserMedia', ->
    it 'calls its callbacks', (done) ->
      @timeout 5000
      navigator.webkitGetUserMedia audio: true, video: false,
        -> done()
        -> done()

  describe 'navigator.language', ->
    it 'should not be empty', ->
      assert.notEqual navigator.language, ''

  describe 'navigator.serviceWorker', ->
    url = "file://#{fixtures}/pages/service-worker/index.html"
    w = null

    afterEach ->
      w?.destroy()

    it 'should register for file scheme', (done) ->
      w = new BrowserWindow(show:false)
      w.webContents.on 'ipc-message', (event, args) ->
        if args[0] == 'reload'
          w.webContents.reload()
        else if args[0] == 'error'
          done('unexpected error : ' + args[1])
        else if args[0] == 'response'
          assert.equal args[1], 'Hello from serviceWorker!'
          session.defaultSession.clearStorageData {storages: ['serviceworkers']}, ->
            done()
      w.loadURL url

  describe 'window.open', ->
    @timeout 20000

    it 'returns a BrowserWindowProxy object', ->
      b = window.open 'about:blank', '', 'show=no'
      assert.equal b.closed, false
      assert.equal b.constructor.name, 'BrowserWindowProxy'
      b.close()

    it 'accepts "node-integration" as feature', (done) ->
      listener = (event) ->
        assert.equal event.data, 'undefined'
        b.close()
        done()
      window.addEventListener 'message', listener
      b = window.open "file://#{fixtures}/pages/window-opener-node.html", '', 'nodeIntegration=no,show=no'

    it 'inherit options of parent window', (done) ->
      listener = (event) ->
        [width, height] = remote.getCurrentWindow().getSize()
        assert.equal event.data, "size: #{width} #{height}"
        b.close()
        done()
      window.addEventListener 'message', listener
      b = window.open "file://#{fixtures}/pages/window-open-size.html", '', 'show=no'

    it 'does not override child options', (done) ->
      size = {width: 350, height: 450}
      listener = (event) ->
        assert.equal event.data, "size: #{size.width} #{size.height}"
        b.close()
        done()
      window.addEventListener 'message', listener
      b = window.open "file://#{fixtures}/pages/window-open-size.html", '', "show=no,width=#{size.width},height=#{size.height}"

  describe 'window.opener', ->
    @timeout 10000

    url = "file://#{fixtures}/pages/window-opener.html"
    w = null

    afterEach ->
      w?.destroy()

    it 'is null for main window', (done) ->
      w = new BrowserWindow(show: false)
      w.webContents.on 'ipc-message', (event, args) ->
        assert.deepEqual args, ['opener', null]
        done()
      w.loadURL url

    it 'is not null for window opened by window.open', (done) ->
      listener = (event) ->
        assert.equal event.data, 'object'
        b.close()
        done()
      window.addEventListener 'message', listener
      b = window.open url, '', 'show=no'

  describe 'window.postMessage', ->
    it 'sets the source and origin correctly', (done) ->
      sourceId = remote.getCurrentWindow().id
      listener = (event) ->
        window.removeEventListener 'message', listener
        b.close()
        message = JSON.parse(event.data)
        assert.equal message.data, 'testing'
        assert.equal message.origin, 'file://'
        assert.equal message.sourceEqualsOpener, true
        assert.equal message.sourceId, sourceId
        assert.equal event.origin, 'file://'
        done()
      window.addEventListener 'message', listener
      b = window.open "file://#{fixtures}/pages/window-open-postMessage.html", '', 'show=no'
      BrowserWindow.fromId(b.guestId).webContents.once 'did-finish-load', ->
        b.postMessage('testing', '*')

  describe 'window.opener.postMessage', ->
    it 'sets source and origin correctly', (done) ->
      listener = (event) ->
        window.removeEventListener 'message', listener
        b.close()
        assert.equal event.source, b
        assert.equal event.origin, 'file://'
        done()
      window.addEventListener 'message', listener
      b = window.open "file://#{fixtures}/pages/window-opener-postMessage.html", '', 'show=no'

  describe 'creating a Uint8Array under browser side', ->
    it 'does not crash', ->
      RUint8Array = remote.getGlobal 'Uint8Array'
      new RUint8Array

  describe 'webgl', ->
    it 'can be get as context in canvas', ->
      return if process.platform is 'linux'
      webgl = document.createElement('canvas').getContext 'webgl'
      assert.notEqual webgl, null

  describe 'web workers', ->
    it 'Worker can work', (done) ->
      worker = new Worker('../fixtures/workers/worker.js')
      message = 'ping'
      worker.onmessage = (event) ->
        assert.equal event.data, message
        worker.terminate()
        done()
      worker.postMessage message

    it 'SharedWorker can work', (done) ->
      worker = new SharedWorker('../fixtures/workers/shared_worker.js')
      message = 'ping'
      worker.port.onmessage = (event) ->
        assert.equal event.data, message
        done()
      worker.port.postMessage message

  describe 'iframe', ->
    iframe = null

    beforeEach ->
      iframe = document.createElement 'iframe'

    afterEach ->
      document.body.removeChild iframe

    it 'does not have node integration', (done) ->
      iframe.src = "file://#{fixtures}/pages/set-global.html"
      document.body.appendChild iframe
      iframe.onload = ->
        assert.equal iframe.contentWindow.test, 'undefined undefined undefined'
        done()

  describe 'storage', ->
    it 'requesting persitent quota works', (done) ->
      navigator.webkitPersistentStorage.requestQuota 1024 * 1024, (grantedBytes) ->
        assert.equal grantedBytes, 1048576
        done()

  describe 'websockets', ->
    wss = null
    server = null
    WebSocketServer = ws.Server

    afterEach ->
      wss.close()
      server.close()

    it 'has user agent', (done) ->
      server = http.createServer()
      server.listen 0, '127.0.0.1', ->
        port = server.address().port
        wss = new WebSocketServer(server: server)
        wss.on 'error', done
        wss.on 'connection', (ws) ->
          if ws.upgradeReq.headers['user-agent']
            done()
          else
            done('user agent is empty')
        websocket = new WebSocket("ws://127.0.0.1:#{port}")

  describe 'Promise', ->
    it 'resolves correctly in Node.js calls', (done) ->
      document.registerElement('x-element', {
        prototype: Object.create(HTMLElement.prototype, {
          createdCallback: { value: -> }
        })
      })

      setImmediate ->
        called = false
        Promise.resolve().then ->
          done(if called then undefined else new Error('wrong sequence'))
        document.createElement 'x-element'
        called = true

    it 'resolves correctly in Electron calls', (done) ->
      document.registerElement('y-element', {
        prototype: Object.create(HTMLElement.prototype, {
          createdCallback: { value: -> }
        })
      })

      remote.getGlobal('setImmediate') ->
        called = false
        Promise.resolve().then ->
          done(if called then undefined else new Error('wrong sequence'))
        document.createElement 'y-element'
        called = true
