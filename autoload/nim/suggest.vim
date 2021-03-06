" nimsuggest management routines
"
" Copyright 2019 Leorize <leorize+oss@disroot.org>
"
" Licensed under the terms of the ISC license,
" see the file "license.txt" included within this distribution.

let s:suggestInstances = {}

function! s:NewInstance(project, file)
  " connectQueue = [function(failed: bool)] called after port is available
  let result = {
      \         'job': -1,
      \         'port': -1,
      \         'connectQueue': []
      \        }

  function! OnEvent(job, data, event) abort dict
    if a:event == 'stdout' && self.instance.port == -1
      let self.buffer[-1] .= a:data[0]
      call extend(self.buffer, a:data[1:])
      if len(self.buffer) > 1
        let self.instance.port = str2nr(self.buffer[0])
        for F in self.instance.connectQueue
          call F(v:false)
        endfor
        unlet self.instance.connectQueue
      endif
    elseif a:event == 'exit'
      echomsg 'nimsuggest instance for project: `' . self.file . "'" .
      \       ' exited with exitcode: ' . a:data
      let self.instance.job = -1
      let self.instance.port = -1
      if has_key(self.instance, 'connectQueue')
        for F in self.instance.connectQueue
          call F(v:true)
        endfor
      endif
    endif
  endfunction

  let result.job =
      \   jobstart(['nimsuggest', '--autobind', '--address:localhost', a:file],
      \            {'on_stdout': function('OnEvent'),
      \             'on_exit': function('OnEvent'),
      \             'buffer': [''],
      \             'instance': result,
      \             'file': a:project})
  if result.job == -1
    echoerr 'Unable to launch nimsuggest for file: `' . a:file . "'"
  endif

  return result
endfunction

function! s:FindProjectInstance(file)
  if empty(a:file)
    return ''
  endif
  let result = ''
  for key in keys(s:suggestInstances)
    let file = expand(a:file)
    if stridx(file, key) == 0 && strlen(key) > strlen(result)
      let result = key
    endif
  endfor
  if empty(result) || s:suggestInstances[result].job == -1
    return ''
  endif
  return result
endfunction

function! nim#suggest#FindInstance(...)
  let projectFile = a:0 >= 1 ? fnamemodify(a:1, ':p') : expand('%:p')
  if empty(projectFile)
    echomsg 'nimsuggest is only available to files on disk'
    return {}
  endif
  let projectDir = s:FindProjectInstance(projectFile)
  if empty(projectDir)
    return {}
  endif
  return {'directory': projectDir, 'instance': s:suggestInstances[projectDir]}
endfunction

function! nim#suggest#ProjectFileStart(file)
  let projectFile = fnamemodify(a:file, ':p')
  if !filereadable(projectFile)
    echomsg 'nimsuggest is only available to files on disk'
    return {}
  endif
  let projectDir = fnamemodify(projectFile, ':h')
  if has_key(s:suggestInstances, projectDir) &&
  \  s:suggestInstances[projectDir].job != -1
    echomsg 'An instance of nimsuggest has already been started for this project'
    return {'directory': projectDir, 'instance': s:suggestInstances[projectDir]}
  endif
  let s:suggestInstances[projectDir] = s:NewInstance(projectDir, projectFile)
  return {'directory': projectDir, 'instance': s:suggestInstances[projectDir]}
endfunction

function! nim#suggest#ProjectStart()
  return nim#suggest#ProjectFileStart(expand('%'))
endfunction

function! nim#suggest#ProjectStop()
  let projectDir = expand('%:p:h')
  call jobstop(s:suggestInstances[projectDir].job)
  unlet s:suggestInstances[projectDir]
endfunction

function! nim#suggest#ProjectFindOrStart()
  let projectFile = expand('%:p')
  if empty(projectFile)
    echomsg 'nimsuggest is only available to files on disk'
    return {}
  endif
  let projectDir = s:FindProjectInstance(projectFile)
  if empty(projectDir)
    return nim#suggest#ProjectStart()
  endif
  return {'directory': projectDir, 'instance': s:suggestInstances[projectDir]}
endfunction

function! nim#suggest#RunAfterReady(instance, Func)
  if empty(a:instance)
    return
  endif
  if a:instance.port == -1
    call add(a:instance.connectQueue, a:Func)
  else
    call a:Func(v:false)
  endif
endfunction

function! nim#suggest#Connect(instance, opts)
  if empty(a:instance) || a:instance.port == -1
    echoerr 'invalid instance specified'
    return 0
  endif
  let channel = 0
  try
    let channel = sockconnect('tcp', 'localhost:' . a:instance.port, a:opts)
  finally
    if channel == 0
      return 0
    endif
    return channel
  endtry
endfunction
