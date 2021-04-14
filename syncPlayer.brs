LIBRARY "time.brs"

function createSyncPlayer(_config as Object) as Object
  player = createObject("roAssociativeArray")
  player.id = _config.id
  player.videopath = _config.filepath



  ' Set up the sync API communications
  player.url = _config.syncURL
  player.password = _config.password
  player.request = createObject("roUrlTransfer")
  player.request.setUrl(player.url+"/api/work/"+player.id+"/timestamp")
  player.responsePort = createObject("roMessagePort")
  player.request.setPort(player.responsePort)

  ' Give the player methods
  player.submitTimestamp = submitTimestamp
  player.markLocalStart = markLocalStart
  player.loop = loop
  player.handleUDP = handleUDP

  ' Video timing fields
  player.lastCycleStartedAt = 0
  player.duration = 0

  ' Screen resolution settings
  player.mode = CreateObject("roVideoMode")
  player.mode.setMode("auto")

  ' Create a clock and sync it
  player.clock = createClock(player.url,player.password)


  ' Video port for events
  player.videoPort = createObject("roMessagePort")

  ' Init the first copy of video
  player.video = createObject("roVideoPlayer")
  player.video.setPort(player.videoPort)
  player.video.setViewMode(1) ' centered and letterboxed
  player.video.setVolume(15) ' see config stuff in master from zachpoff
  Print "Preloading video..."
  print "Preload status:", player.video.preloadFile(player.videopath)
  ok = player.video.addEvent(1, player.video.getDuration() - 20000) ' Throw an event for resynchronization 20s before film end
  player.duration = player.video.getDuration()-20

  print "Updating duration on server..."
  player.updateDurationRequest = createObject("roUrlTransfer")
  player.updateDurationRequest.setUrl(player.url+"/api/work/"+player.id+"/duration")
  updateDurationData = "password="+player.password+"&"
  updateDurationData = updateDurationData+"duration="+player.duration.toStr()
  player.updateDurationRequest.asyncPostFromString(updateDurationData)

  print "Setting up udp port", _config.commandPort.toInt()
  player.udpReceiver = createObject("roDatagramReceiver",_config.commandPort.toInt() )
  player.udpPort = createObject("roMessagePort") 
  player.udpReceiver.setPort(player.udpPort)
 
  return player
end function

function markLocalStart()
  m.lastCycleStartedAt = m.clock.getEpochAsMSString()
end function

function submitTimestamp() as String
  postString = "password="+m.request.escape(m.password)+"&"
  postString = postString+"lastTimestamp="+m.request.escape(m.clock.synchronizeTimestamp(m.lastCycleStartedAt))
  m.request.asyncPostFromString(postString)
  response = m.responsePort.waitMessage(1000)
  if not response = invalid then
    response = response.getString()
    return response
  else 
    return "invalid"
  end if
end function

function loop()
  print "Beginning seamless synchronized looping..."
  while true
    m.video.play()
    sleep(35) ' TODO: DEAL WITH THIS MAGIC NUMBER!! 1 frame delay?
    m.markLocalStart()
    m.submitTimestamp()
    print "New loop just started."

    ' wait until 20s before the end, then resynchronize to the server
    while (m.video.getPlaybackPosition() < m.video.getDuration()-25000):
      m.handleUDP() 
    end while
    print "NTP sync beginning..."
    m.clock.ntpSync()

    ' Wait until the end of the file, then seek to the beginning.
    ' This seems much more reliable than auto-looping.
    ' Potentially not seamless though?
    print "NTP sync completed."
    
    while (m.video.getPlaybackPosition() < m.duration-1000):
      m.hanldeUDP()
    end while
    
    while (m.video.getPlaybackPosition() < m.duration):
      sleep(1) 'wait 
    end while
    
    m.video.seek(0)
  end while
end function

function handleUDP()
  msg = m.udpPort.getMessage() 
  if msg="pause" then
      m.video.pause()
  else if msg="play" then
    m.video.resume()
  else if msg="restart" then
    m.video.seek(0)
  else if msg="seekforward" then
    m.video.seek(m.video.getPlaybackPosition()+5000)
  else if msg="seekbackward" then
    m.video.seek(m.video.getPlaybackPosition()-5000)
  else if msg="ff" then
    m.video.setPlaybackSpeed(2)
  else if msg="fff" then
    m.video.setPlaybackSpeed(8)
  else if msg="rr" then
    m.video.setPlaybackSpeed(-2)
  else if msg="rrr" then
    m.video.setPlaybackSpeed(-8)
  else if msg="defaultspeed" then
    m.video.setPlaybackSpeed(1)
  else if msg="debug" then
    STOP
  end if
end function