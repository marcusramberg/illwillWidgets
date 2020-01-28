import os, strutils
import illwill
import macros

macro preserveColor*(pr: untyped): typed =
  result = newProc()
  let oldbody = pr.body
  result.name = pr.name
  result.params = pr.params
  result.body = quote do:
    let oldFg = tb.getForegroundColor
    let oldBg = tb.getBackgroundColor
    tb.setForegroundColor wid.color
    tb.setBackgroundColor wid.bgcolor
    `oldbody`
    tb.setForegroundColor oldFg
    tb.setBackgroundColor oldBg
  # echo repr result

type
  Event = enum
    Hover, MouseUp, MouseDown
  Events = set[Event]
  Widget = object of RootObj
    x: int
    y: int
    color: ForegroundColor
    bgcolor: BackgroundColor
  Button = object of Widget
    text: string
    pressed: bool
    boxBuffer: BoxBuffer
    w: int
    h: int
  Checkbox = object of Widget
    text: string
    checked: bool
    textChecked: string
    textUnchecked: string
  # RadioButton = object of Checkbox
  #   linked: set[RadioButton]
  InfoBox = object of Widget
    text: string
    w: int
  ChooseBox = object of Widget
    bgcolorChoosen: BackgroundColor
    choosenidx: int
    w: int
    h: int
    elements: seq[string]
  TextBox = object of Widget
    text: string
    placeholder: string
    focus: bool
    w: int
    caretIdx: int

# proc newRadioButtinGroup(radioButtons: seq[RadioButton]) =
#   for radioButton in radioButton:
#     radioButton.linked = radioButtons
  # RadioButton = object of Widget
  #   text: string
  #   checked: bool
  
  # ComboBox[Key] = object of Widget
  #   open: bool
  #   current: Key
  #   elements: Table[Key, string]
  #   w: int
  #   color: ForegroundColor

# proc newComboBox[Key](x,y: int, w = 10): ComboBox =
#   result = ComboBox[Key](
#     open: false,

#   )

#########################################################################################################
# InfoBox
#########################################################################################################
proc newInfoBox(text: string, x, y: int, w = 10, color = fgBlack, bgcolor = bgWhite): InfoBox =
  result = InfoBox(
    text: text,
    x: x,
    y: y,
    w: w,
    color: color,
    bgcolor: bgcolor,
  )

proc render(tb: var TerminalBuffer, wid: InfoBox) {.preserveColor.} =
  # TODO save old text to only overwrite the len of the old text
  tb.write(wid.x, wid.y, wid.text.alignLeft(wid.w))

proc inside(wid: InfoBox, mi: MouseInfo): bool =
  return (mi.x in wid.x .. wid.x+wid.w) and (mi.y == wid.y)

proc dispatch(tb: var TerminalBuffer, wid: InfoBox, mi: MouseInfo): Events {.discardable.} = 
  if wid.inside(mi) and mi.action == Pressed: result.incl MouseDown
  if wid.inside(mi) and mi.action == Released: result.incl MouseUp

#########################################################################################################
# Checkbox
#########################################################################################################
proc newCheckbox(text: string, x, y: int, color = fgBlue): Checkbox =
  result = Checkbox(
    text: text,
    x: x,
    y: y,
    color: color,
    textChecked: "[X] ",
    textUnchecked: "[ ] "
  )

proc render(tb: var TerminalBuffer, wid: Checkbox) {.preserveColor.} =
  let check = if wid.checked: wid.textChecked else: wid.textUnchecked
  tb.write(wid.x, wid.y, check & wid.text)

proc inside(wid: Checkbox, mi: MouseInfo): bool =
  return (mi.x in wid.x .. wid.x+wid.text.len + 3) and (mi.y == wid.y)

proc dispatch(tr: var TerminalBuffer, wid: var Checkbox, mi: MouseInfo): Events {.discardable.} = 
  if not wid.inside(mi): return
  if wid.inside(mi) and mi.action == Pressed:
    result.incl MouseDown
  if wid.inside(mi) and mi.action == Released:
    wid.checked = not wid.checked
    result.incl MouseUp

#########################################################################################################
# RadioBox
#########################################################################################################
proc newRadioBox(text: string, x, y: int, color = fgBlue): Checkbox =
  ## Radio box is actually a checkbox, you need to add the checkbox to a radio button group
  result = newCheckbox(text, x, y, color)
  result.textChecked = "(X) "
  result.textUnchecked = "( ) "

# proc

#########################################################################################################
# Button
#########################################################################################################
proc newButton(text: string, x, y, w, h: int, color = fgBlue): Button = #, cb = ButtonCallback): Button = 
  result = Button(
    text: text,
    pressed: false,
    x: x,
    y: y,
    w: w,
    h: h,
    color: color,
  )

proc render(tb: var TerminalBuffer, wid: Button) {.preserveColor.} =
  tb.fill(wid.x, wid.y, wid.x+wid.w, wid.y+wid.h)
  tb.write(
    wid.x+1 + wid.w div 2 - wid.text.len div 2 , 
    wid.y+1, 
    wid.text
  )
  tb.drawRect(
    wid.x, 
    wid.y,
    wid.x + wid.w, 
    wid.y + wid.h, 
    doubleStyle=wid.pressed, 
  )

proc inside(wid: Button, mi: MouseInfo): bool =
  return (mi.x in wid.x .. wid.x+wid.w) and (mi.y in wid.y .. wid.y+wid.h)

proc dispatch(tr: var TerminalBuffer, wid: var Button, mi: MouseInfo): Events {.discardable.} = 
  ## if the mouse clicks this button 
  result = {}
  if not wid.inside(mi): 
    wid.pressed = false
    return
  case mi.action
  of Pressed:
    wid.pressed = true
    result.incl MouseDown
  of Released:
    wid.pressed = false
    result.incl MouseUp

#########################################################################################################
# ChooseBox
#########################################################################################################
proc grow(wid: var ChooseBox) =
  if wid.elements.len >= wid.h: wid.h = wid.elements.len+1 # TODO allowedToGrow

proc add(wid: var ChooseBox, elem: string) = 
  ## adds element to the list, grows the box immediately
  wid.elements.add(elem)
  wid.grow()

proc newChooseBox(elements: seq[string], x, y, w, h: int, color = fgBlue, label = "", choosenidx = 0): ChooseBox =
  result = ChooseBox(
    elements: elements,
    choosenidx: choosenidx,
    x: x,
    y: y,
    w: w,
    h: h,
    color: color,
  )
  result.grow()

proc choosenElement(wid: ChooseBox): string =
  return wid.elements[wid.choosenidx]

template setWidgetColor(tb: var TerminalBuffer, wid: typed) =
  tb.setForegroundColor wid.color
  tb.setBackgroundColor wid.bgcolor

proc render(tb: var TerminalBuffer, wid: ChooseBox) {.preserveColor.} =
  tb.fill(wid.x, wid.y, wid.x+wid.w, wid.y+wid.h)
  for idx, elemRaw in wid.elements:
    let elem = elemRaw.alignLeft(wid.w)
    if idx == wid.choosenidx:
      tb.write resetStyle
      tb.write(wid.x+1, wid.y+ 1 + idx, wid.color, wid.bgcolor, styleReverse, elem)
    else:
      tb.write resetStyle
      tb.write(wid.x+1, wid.y+ 1 + idx, wid.color, wid.bgcolor, elem)
  tb.write resetStyle
  tb.setWidgetColor(wid)
  tb.drawRect(
    wid.x, 
    wid.y,
    wid.x + wid.w, 
    wid.y + wid.h, 
  )

proc inside(wid: ChooseBox, mi: MouseInfo): bool =
  return (mi.x in wid.x .. wid.x+wid.w) and (mi.y in wid.y .. wid.y+wid.h)

proc dispatch(tr: var TerminalBuffer, wid: var ChooseBox, mi: MouseInfo): Events {.discardable.} = 
  result = {}
  wid.grow()
  if not wid.inside(mi): 
    return
  case mi.action
  of Pressed:
    result.incl MouseDown
  of Released:
    wid.choosenidx = clamp( (mi.y - wid.y)-1 , 0, wid.elements.len-1)
    result.incl MouseUp  

#########################################################################################################
# TextBox
#########################################################################################################
proc newTextBox(text: string, x, y: int, w = 10, color = fgBlack, bgcolor = bgCyan, placeholder = ""): TextBox =
  ## TODO a good textbox is COMPLICATED, this is a VERY basic one!! PR's welcome ;)
  result = TextBox(
    text: text,
    x: x,
    y: y,
    w: w,
    color: color,
    bgcolor: bgcolor,
    placeholder: placeholder
  )

proc render(tb: var TerminalBuffer, wid: TextBox) {.preserveColor.} =
  # TODO save old text to only overwrite the len of the old text
  tb.write(wid.x, wid.y, repeat(" ", wid.w))
  if wid.caretIdx == wid.text.len():
    tb.write(wid.x, wid.y, wid.text)
    if wid.text.len < wid.w:
      tb.write(wid.x + wid.caretIdx, wid.y, styleReverse, " ", resetStyle)
  else:
    tb.write(wid.x, wid.y,
      wid.text[0..wid.caretIdx-1], 
      styleReverse, $wid.text[wid.caretIdx],
      
      resetStyle,
      wid.color, wid.bgcolor,
      wid.text[wid.caretIdx+1..^1], 
      resetStyle
      )

proc inside(wid: TextBox, mi: MouseInfo): bool =
  return (mi.x in wid.x .. wid.x+wid.w) and (mi.y == wid.y)

proc dispatch(tb: var TerminalBuffer, wid: var TextBox, mi: MouseInfo): Events {.discardable.} = 
  if wid.inside(mi) and mi.action == Pressed: 
    result.incl MouseDown
  if wid.inside(mi) and mi.action == Released: 
    wid.focus = true
    result.incl MouseUp
  if not wid.inside(mi) and mi.action == Released:
    wid.focus = false

proc handleKey(tb: var TerminalBuffer, wid: var TextBox, key: Key): bool {.discardable.} = 
  ## if this function return "true" the textbox lost focus by enter
  result = false

  template incCaret() =
    wid.caretIdx.inc
    wid.caretIdx = clamp(wid.caretIdx, 0, wid.text.len)
  template decCaret() =
    wid.caretIdx.dec
    wid.caretIdx = clamp(wid.caretIdx, 0, wid.text.len)

  if key == Mouse: return false
  if key == None: return false

  case key
  of Enter:
    return true
  of Escape:
    wid.focus = false
    return
  of End:
    wid.caretIdx = wid.text.len
  of Home:
    wid.caretIdx = 0
  of Backspace:
    try:
      delete(wid.text, wid.caretIdx-1, wid.caretIdx-1)
      decCaret
    except:
      discard
  of Right:
    incCaret
  of Left:
    decCaret
  else:
    # Add ascii representation
    var ch = $key.char
    if wid.text.len < wid.w:
      wid.text.insert(ch, wid.caretIdx)
      wid.caretIdx.inc
      wid.caretIdx = clamp(wid.caretIdx, 0, wid.text.len)    

template setKeyAsHandled(key: Key) = 
  ## call this on key when the key was handled by a textbox
  if key != Key.Mouse:
    key = None 

when isMainModule:
  import strformat
  import asyncdispatch, httpclient# for async demonstration

  proc exitProc() {.noconv.} =
    illwillDeinit()
    showCursor()
    quit(0)

  illwillInit(fullscreen=true, mouse=true)
  setControlCHook(exitProc)
  hideCursor()

  var tb = newTerminalBuffer(terminalWidth(), terminalHeight())

  
  var btnAsyncHttp = newButton("async http", 21, 3, 15, 2)
  var btnTest = newButton("fill", 38, 3, 15, 2)
  var btnClear = newButton("clear", 38, 6, 15, 2)
  var chkTest = newCheckbox("Some content", 38, 9)
  var chkTest2 = newCheckbox("Fill Color", 38, 10)
  chkTest2.textUnchecked = ":)  "
  chkTest2.textChecked =   ":(  "

  var chkDraw = newCheckbox("Draw?", 38, 11)
  
  # Info box
  var infoBox = newInfoBox("",0 ,0, terminalWidth())
  var infoBoxMouse = newInfoBox("",0 ,0, terminalWidth())
  var infoBoxAsync = newInfoBox("",0 ,1, terminalWidth())

  # Radio buttons
  var chkRadA = newRadioBox("Radio Box Option A", 56, 4)
  var chkRadB = newRadioBox("Radio Box Option B", 56, 5)
  var chkRadC = newRadioBox("Radio Box Option C", 56, 6)

  var chooseBox = newChooseBox(@[" ", "#", "@", "§"], 81, 3, 10, 5, choosenidx=2)

  var textBox = newTextBox("foo", 38, 13, 42, placeholder = "Some placeholder")

  proc asyncDemo(): Future[void] {.async.} =
    var idx = 0
    while true:
      idx.inc
      infoBoxAsync.text = "Async Demo: " & $idx
      await sleepAsync(1000)
  asyncCheck asyncDemo()

  proc httpCall(): Future[void] {.async.} =
    var client = newHttpClient()
    infoBox.text = client.getContent("http://ip.code0.xyz").strip()

  proc funDraw(tb: var TerminalBuffer, coords: MouseInfo) = 
    if coords.action == MouseButtonAction.Pressed:
      tb.write coords.x, coords.y, fgRed, "♥"
    else:
      tb.write coords.x, coords.y, fgGreen, "⌀"


  while true:
    var key = getKey()

    # Must be done for every textbox
    if textBox.focus:
      if tb.handleKey(textBox, key):
        tb.write(0,2, bgYellow, fgBlue, textBox.text)
        chooseBox.add(textBox.text)
      key.setKeyAsHandled() # If the key input was handled by the textbox
    
    case key
    of Key.None: discard
    of Key.Escape, Key.Q: exitProc()
    of Key.Mouse: #, Key.None: # TODO Key.None here does not work with checkbox
      let coords = getMouse()
      infoBoxMouse.text = $coords
      var ev: Events

      ev = tb.dispatch(btnAsyncHttp, coords)
      if ev.contains MouseUp:
        asyncCheck httpCall()
      if ev.contains MouseDown:
        infoBox.text = "http call to http://ip.code0.xyz to get your public ip!"


      ev = tb.dispatch(btnClear, coords)
      if ev.contains MouseUp:
        tb.clear()
      if ev.contains MouseDown:
        infoBox.text = "CLEARS THE SCREEN!"
      
      ev = tb.dispatch(btnTest, coords)
      if ev.contains MouseUp:
        tb.clear(chooseBox.choosenElement)
      if ev.contains MouseDown:
        infoBox.text = "Fills the screen!!"

      ev = tb.dispatch(chkTest, coords)
      if ev.contains MouseUp:
        infoBox.text = "chk test is: " & $chkTest.checked
      
      ev = tb.dispatch(chkTest2, coords)
      if ev.contains MouseUp:
        if chkTest2.checked:
          infoBox.text = "red"
          tb.setForegroundColor fgRed
          chkTest2.color = fgRed
        else:
          infoBox.text = "green"
          chkTest2.color = fgGreen
          tb.setForegroundColor fgGreen

      ev = tb.dispatch(chkDraw, coords)
      if ev.contains MouseDown:
        infoBox.text = "Enables/Disables drawing"

      ev = tb.dispatch(infoBox, coords)
      if ev.contains MouseDown:
        infoBox.text &= "#"
      if ev.contains MouseUp:
        infoBox.text &= "^"

      ev = tb.dispatch(chooseBox, coords)
      if ev.contains MouseUp:
        infoBox.text = fmt"Choose box choosenidx: {chooseBox.choosenidx} -> {chooseBox.choosenElement()}"
      
      # Textbox is special! (see above for `handleKey`)
      ev = tb.dispatch(textBox, coords)
  
      # We enable / disable drawing based on checkbox value
      if chkDraw.checked:
        tb.funDraw(coords)

    else:
      infoBox.text = $key
      discard
    
    tb.render(btnAsyncHttp)
    tb.render(btnClear)
    tb.render(btnTest)
    tb.render(chkTest)
    tb.render(chkTest2)
    tb.render(chkDraw)

    tb.render(chkRadA)
    tb.render(chkRadB)
    tb.render(chkRadC)

    # Update the info box position to always be on the bottom
    infoBox.w = terminalWidth()
    infoBox.y = terminalHeight()-1
    tb.render(infoBox)
    
    tb.render(infoBoxMouse) # No need to update position (is at the top)
    tb.render(infoBoxAsync)
    tb.render(chooseBox)
    tb.render(textBox)
    
    tb.display()

    poll(30) # for the async demo code (keep poll low), use sleep below for non async.
    # sleep(50) # when no async code used, just call sleep(50)
# 