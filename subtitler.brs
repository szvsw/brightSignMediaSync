function createSubtitler(parent)
  subtitler = createObject("roAssociativeArray")

  ' Widget Creation
  videoMode = createObject("roVideoMode")
  xAnchor = videoMode.getSafeX()+10
  yAnchor = videoMode.GetSafeY()+videoMode.GetSafeHeight()-170
  width = videoMode.getSafeWidth()-20
  height = 160
  subtitleRectangle = createObject("roRectangle",xAnchor,yAnchor,width,height)
  params = {Alignment:1, TextMode:2, PauseTime:0, LineCount:2}

  subtitleWidget = createObject("roTextWidget",subtitleRectangle,2,2,params) ' lines, mode, pausetime
  subtitleWidget.setBackgroundColor(&Ha0000000)
  subtitleWidget.setForegroundColor(&Hffffffff)

  subtitler.rect = subtitleRectangle
  subtitler.widget = subtitleWidget
  subtitler.activationState = "inactive"
  subtitler.thresholdState = "waitingToCrossNextStart"
  subtitler.update = subtitleMachine
  subtitler.activate = activateSubtitles
  subtitler.deactivate = deactivateSubtitles
  subtitler.video = parent.video ' ref to parent engine's roVideoPlayer
  subtitler.parent = parent ' ref to parent engine
  subtitler.currentIndex = 0
  subtitler.determineCurrentIndex = determineCurrentIndex
  subtitler.metronome = createObject("roTimer") ' for polling 
  subtitler.metronomeTrigger = createObject("roMessagePort") ' Port which will receive events to trigger get requests
  subtitler.metronome.setPort(subtitler.metronomeTrigger)
  subtitler.metronome.setElapsed(5,0)
  subtitler.metronome.start()

  subtitler.srtFetcher = createObject("roUrlTransfer")
  subtitler.srtFetcher.setUrl(parent.config.syncUrl+"/api/work/"+parent.config.workId.toStr())
  subtitler.srtResponse = createObject("roMessagePort")
  subtitler.srtFetcher.setPort(subtitler.srtResponse)

  ' Set up polling for subtitle toggling
  subtitler.statePoller = createObject("roUrlTransfer")
  subtitler.statePoller.setUrl(parent.apiEndpoint+"/work")
  subtitler.statePollerResponsePort = createObject("roMessagePort")
  subtitler.statePoller.setPort(subtitler.statePollerResponsePort)
  subtitler.pollingState = "waitingToPoll"

  if parent.config.updateSubtitles then
    subtitler.srtFetcher.asyncGetToString()
    res = subtitler.srtResponse.waitMessage(3000)
    if res <> invalid then
      if res.getResponseCode() = 200 then
        data = parseJSON(res.getString())
        parsedSrt = data.parsedSrt
        WriteAsciiFile("subtitles.json",FormatJSON(parsedSrt))
        subtitler.events = parsedSrt
      else 
        subtitler.events = ParseJSON(ReadAsciiFile("subtitles.json"))
      end if
    else
      subtitler.events = ParseJSON(ReadAsciiFile("subtitles.json"))
    end if
  end if
  return subtitler
end function 

function subtitleMachine()
  if m.activationState = "starting" then
    print("starting up onscreen subtitles!")
    m.determineCurrentIndex()
    m.activationState = "active"
  else if m.activationState = "active" then
    if m.thresholdState = "waitingToCrossNextStart" then
      if m.video.getPlaybackPosition() >= m.events[m.currentIndex].start*1000 then
        m.widget.clear()
        m.widget.pushString(m.events[m.currentIndex].text)
        m.thresholdState = "waitingToCrossNextEnd"
      end if
    else if m.thresholdState = "waitingToCrossNextEnd" then
      if m.video.getPlaybackPosition() >= m.events[m.currentIndex].end*1000 then
        m.widget.clear()
        if m.currentIndex = m.events.count()-1 then
          m.thresholdState = "waitingToFinishLoop"
        else
          m.currentIndex = m.currentIndex + 1
          m.thresholdState = "waitingToCrossNextStart"
        end if
      end if
    else if m.thresholdState = "waitingToFinishLoop" then
      if m.video.getPlaybackPosition() < m.events[m.currentIndex].end*1000 then
        m.currentIndex = 0
        m.thresholdState = "waitingToCrossNextStart"
        if m.parent.config.autoShutoffSubtitles then
          m.deactivate()
        end if
      end if
    end if
  else if m.activationState = "inactive"
  end if

  ' subtitle state polling engine
  if m.parent.config.pollForSubtitleState then
    if m.video.getPlaybackPosition() > 1000 or m.video.getPlaybackPosition() < m.parent.duration - 3000 then
      if m.pollingState = "waitingToPoll"
        msg = m.metronomeTrigger.getMessage()
        if msg <> invalid then
          m.statePoller.asyncGetToString()
          m.metronome.setElapsed(1,0)
          m.metronome.start()
          m.pollingState = "waitingForResponse"
        end if
      else if m.pollingState = "waitingForResponse"
        msg = m.statePollerResponsePort.getMessage()
        if msg <> invalid
          if msg.getResponseCode() = 200 then
            data = ParseJSON(msg.getString())
            if data.work.onScreenSubtitles  then
              if m.activationState = "inactive" then
                print("activating on screen subtitles")
                m.activate()
              end if
            else 
              if m.activationState <> "inactive"
                print("deactivating on screen subtitles")
                m.deactivate()
              end if
            end if
          end if
          m.pollingState="waitingToPoll"
        end if
      end if

    else 
      ' block api requests during critical sync windows
    end if
  end if
end function

function activateSubtitles()
  m.widget.clear()
  m.widget.show()
  m.activationState = "starting"
end function

function deactivateSubtitles()
  m.widget.clear()
  m.widget.hide()
  m.activationState = "inactive"
end function

function determineCurrentIndex()
  m.currentIndex = 0
  currentTime = m.video.getPlaybackPosition()
  while m.currentIndex < m.events.count()-1
    if currentTime < m.events[m.currentIndex].end*1000
      print("Subtitles activating at index"+m.currentIndex.toStr())
      EXIT WHILE
    end if
    m.currentIndex = m.currentIndex + 1 
  end while
  m.thresholdState = "waitingToCrossNextStart"
  if m.currentIndex = m.events.count()-1 and currentTime > m.events[m.currentIndex].end*1000 then
    m.thresholdState = "waitingToFinishLoop"
  end if


end function