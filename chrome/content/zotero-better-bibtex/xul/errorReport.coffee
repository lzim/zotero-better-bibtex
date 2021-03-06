Components.utils.import('resource://zotero/config.js')
Components.utils.import('resource://gre/modules/AddonManager.jsm')

Zotero_BetterBibTeX_ErrorReport =
  submit: (filename, data) ->
    return new Promise((resolve, reject) =>
      fd = new FormData()
      for own name, value of @form.fields
        fd.append(name, value)

      file = new Blob([data], { type: 'text/plain'})
      fd.append('file', file, "#{@timestamp}-#{@key}-#{filename}")

      request = Components.classes["@mozilla.org/xmlextras/xmlhttprequest;1"].createInstance()
      request.open('POST', @form.action, true)

      request.onload = =>

        switch
          when !request.status || request.status > 1000
            reject(Zotero.getString('errorReport.noNetworkConnection') + ': ' + request.status)
          when request.status != parseInt(@form.fields.success_action_status)
            reject(Zotero.getString('errorReport.invalidResponseRepository') + ": #{request.status}, expected #{@form.fields.success_action_status}\n#{request.responseText}")
          else
            resolve()

      request.onerror = ->
        reject(Zotero.getString('errorReport.noNetworkConnection') + ': ' + request.statusText)

      request.send(fd)
    )

  getSystemInfo: ->
    return new Promise((resolve, reject) =>
      AddonManager.getAllAddons((addons)=>
        try
          versions = {}
          standalone = false

          types = {
            2:    'extension'
            4:    'theme'
            8:    'locale'
            32:   'multiple item package'
            64:   'spell check dictionary'
            128:  'telemetry experiment'
            256:  'WebExtension experiment'
          }
          active = []
          disabled = []
          for addon in addons
            versions[addon.id] = addon.version unless addon.appDisabled || addon.userDisabled
            info = "  #{addon.name} (#{types['' + addon.type] || addon.type}): #{addon.version}\n"
            if addon.appDisabled || addon.userDisabled
              disabled.push(info)
            else
              active.push(info)
          info = ''
          if active.length > 0
            active.sort((a, b) -> a.toLowerCase().localeCompare(b.toLowerCase()))
            info += "Active addons:\n" + active.join('')
          if disabled.length > 0
            disabled.sort((a, b) -> a.toLowerCase().localeCompare(b.toLowerCase()))
            info += "Disabled addons:\n" + disabled.join('')

          settings = []
          for key in Zotero.BetterBibTeX.Pref.branch.getChildList('')
            settings.push("  #{key} = #{JSON.stringify(Zotero.BetterBibTeX.Pref.get(key))}\n")
          settings.sort((a, b) -> a.toLowerCase().localeCompare(b.toLowerCase()))
          info += "Settings:\n" + settings.join('')

          for guid in ['zotero@chnm.gmu.edu', 'juris-m@juris-m.github.io']
            continue unless ZOTERO_CONFIG.GUID == guid
            continue if versions[guid]
            versions[guid] = ZOTERO_CONFIG.VERSION
            versions[guid + '-standalone'] = true

          header = ''
          appInfo = Components.classes['@mozilla.org/xre/app-info;1'].getService(Components.interfaces.nsIXULAppInfo)
          header += "Platform: #{Zotero.platform} #{Zotero.oscpu}\n"
          header += "Application: #{appInfo.name} #{appInfo.version} #{Zotero.locale}\n"
          header += "Zotero#{if versions['zotero@chnm.gmu.edu-standalone'] then ' standalone' else ''}: #{versions['zotero@chnm.gmu.edu']}\n" if versions['zotero@chnm.gmu.edu']
          header += "Juris-M#{if versions['juris-m@juris-m.github.io-standalone'] then ' standalone' else ''}: #{versions['juris-m@juris-m.github.io']}\n" if versions['juris-m@juris-m.github.io']

          @errorlog = {
            info: header + info
            errors: Zotero.getErrors(true).join('\n')
            full: Zotero.Debug.get()
          }

          debug = @errorlog.full.split("\n")
          debug = debug.slice(0, 5000) # max 5k lines
          debug = (Zotero.Utilities.ellipsize(line, 80, true) for line in debug) # trim lines
          debug = debug.join("\n")
          @errorlog.truncated = debug

          resolve()
        catch err
          reject(err)
      )
    )

  init: ->
    @form = JSON.parse(Zotero.File.getContentsFromURL('https://github.com/retorquere/zotero-better-bibtex/releases/download/update.rdf/error-report.json'))
    @key = Zotero.Utilities.generateObjectKey()
    @timestamp = (new Date()).toISOString().replace(/\..*/, '').replace(/:/g, '.')

    wizard = document.getElementById('zotero-error-report')
    continueButton = wizard.getButton('next')
    continueButton.disabled = true

    @params = window.arguments[0].wrappedJSObject
    if @params.references
      document.getElementById('betterbibtex.errorReport.references').hidden = false
      document.getElementById('zotero-error-references').value = @params.references.substring(0, 5000)
    else
      document.getElementById('betterbibtex.errorReport.references').hidden = true
      document.getElementById("zotero-error-include-references").checked = false

    @getSystemInfo().then(=>
      document.getElementById('zotero-error-context').value = @errorlog.info
      document.getElementById('zotero-error-errors').value = @errorlog.errors
      document.getElementById('zotero-error-log').value = @errorlog.truncated

      continueButton.disabled = false
      continueButton.focus()
      return
    )

  config: ->
    enabled = false
    for part in ['context', 'errors', 'log', 'references']
      continue unless document.getElementById("zotero-error-include-#{part}").checked
      enabled = part
      break
    Zotero.BetterBibTeX.debug('selectReportPart:', enabled)
    wizard = document.getElementById('zotero-error-report')
    continueButton = wizard.getButton('next')
    continueButton.disabled = !enabled

  sendErrorReport: ->
    wizard = document.getElementById('zotero-error-report')
    continueButton = wizard.getButton('next')
    continueButton.disabled = true

    if document.getElementById("zotero-error-include-context").checked
      errorlog = @errorlog.info
    else
      errorlog = "Zotero: #{ZOTERO_CONFIG.VERSION}, Better BibTeX: #{Zotero.BetterBibTeX.release}"

    if document.getElementById("zotero-error-include-errors").checked
      errorlog += "\n\n" + @errorlog.errors

    if document.getElementById("zotero-error-include-log").checked
      errorlog += "\n\n" + @errorlog.full

    @submit('errorlog.txt', errorlog).then(=>
      if @params.references
        return @submit('references.json', @params.references)
      else
        return Promise.resolve()
    ).then(=>
      wizard.advance()
      wizard.getButton('cancel').disabled = true
      wizard.canRewind = false

      document.getElementById('zotero-report-id').setAttribute('value', @key)
      document.getElementById('zotero-report-result').hidden = false
    ).catch((e) ->
      ps = Components.classes['@mozilla.org/embedcomp/prompt-service;1'].getService(Components.interfaces.nsIPromptService)
      ps.alert(null, Zotero.getString('general.error'), e)
      wizard.rewind() if wizard.rewind
    )
