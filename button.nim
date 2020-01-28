import os, strutils
import illwill

proc exitProc() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)

illwillInit(fullscreen=true, mouse=true)
setControlCHook(exitProc)
hideCursor()

var tb = newTerminalBuffer(terminalWidth(), terminalHeight())


type
  Event = enum
    Hover, MouseUp, MouseDown
  Events = set[Event]
  Widget = object of RootObj
  # ButtonCallback = proc (tr: var TerminalBuffer)
    x: int
    y: int
  Button = object of Widget
    text: string
    pressed: bool
    boxBuffer: BoxBuffer
    color: ForegroundColor
    w: int
    h: int
    # cb: ButtonCallback 
  Checkbox = object of Widget
    text: string
    checked: bool
    color: ForegroundColor
    textChecked: string
    textUnchecked: string
  # RadioButton = object of Checkbox
  #   linked: set[RadioButton]
  InfoBox = object of Widget
    text: string
    color: ForegroundColor
    bgcolor: BackgroundColor
    w: int
  ChooseBox = object of Widget
    color: ForegroundColor
    bgcolor: BackgroundColor
    bgcolorChoosen: BackgroundColor
    choosenidx: int
    w: int
    h: int
    elements: seq[string]

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

proc render(tb: var TerminalBuffer, wid: InfoBox) =
  let oldFg = tb.getForegroundColor
  let oldBg = tb.getBackgroundColor
  tb.setForegroundColor wid.color
  tb.setBackgroundColor wid.bgcolor
  tb.write(wid.x, wid.y, wid.text.alignLeft(wid.w))
  tb.setForegroundColor oldFg
  tb.setBackgroundColor oldBg

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

proc render(tb: var TerminalBuffer, wid: Checkbox) =
  let oldFg = tb.getForegroundColor
  tb.setForegroundColor wid.color
  let check = if wid.checked: wid.textChecked else: wid.textUnchecked
  tb.write(wid.x, wid.y, check & wid.text)
  tb.setForegroundColor oldFg

proc inside(wid: Checkbox, mi: MouseInfo): bool =
  return (mi.x in wid.x .. wid.x+wid.text.len + 3) and (mi.y == wid.y)

proc dispatch(tr: var TerminalBuffer, wid: var Checkbox, mi: MouseInfo): Events {.discardable.} = 
  ## if the mouse clicks this button 
  # result = false
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

proc render(tb: var TerminalBuffer, wid: Button) =
  let oldFg = tb.getForegroundColor
  tb.setForegroundColor wid.color
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
  tb.setForegroundColor oldFg

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

proc newChooseBox(elements: seq[string], x, y, w, h: int, color = fgBlue, label = "", choosenidx = 0): ChooseBox = #, cb = ButtonCallback): Button = 
  result = ChooseBox(
    # label: label,
    elements: elements,
    choosenidx: choosenidx,
    x: x,
    y: y,
    w: w,
    h: h,
    color: color,
  )

proc choosenElement(wid: ChooseBox): string =
  return wid.elements[wid.choosenidx]

template setWidgetColor(tb: var TerminalBuffer, wid: typed) =
  tb.setForegroundColor wid.color
  tb.setBackgroundColor wid.bgcolor

proc render(tb: var TerminalBuffer, wid: ChooseBox) =
  let oldFg = tb.getForegroundColor
  tb.setForegroundColor wid.color
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
    # doubleStyle=wid.pressed, 
  )
  tb.setForegroundColor oldFg

proc inside(wid: ChooseBox, mi: MouseInfo): bool =
  return (mi.x in wid.x .. wid.x+wid.w) and (mi.y in wid.y .. wid.y+wid.h)

proc dispatch(tr: var TerminalBuffer, wid: var ChooseBox, mi: MouseInfo): Events {.discardable.} = 
  ## if the mouse clicks this button 
  result = {}
  if not wid.inside(mi): 
    # wid.pressed = false
    return
  case mi.action
  of Pressed:
    result.incl MouseDown
  of Released:
    wid.choosenidx = clamp( (mi.y - wid.y)-1 , 0, wid.elements.len-1)
    result.incl MouseUp  


when isMainModule:
  import strformat

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

  # Radio buttons
  var chkRadA = newRadioBox("OptionA", 56, 4)
  var chkRadB = newRadioBox("OptionB", 56, 5)
  var chkRadC = newRadioBox("OptionC", 56, 6)

  var chooseBox = newChooseBox(@[" ", "#", "@", "§"], 70, 3, 10, 5, choosenidx=2)

  while true:
    var key = getKey()
    case key
    of Key.None: discard
    of Key.Escape, Key.Q: exitProc()
    of Key.Mouse:
      let coords = getMouse()
      infoBoxMouse.text = $coords
      var ev: Events

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

      if tb.dispatch(chkTest, coords).contains MouseUp:
        infoBox.text = "chk test is: " & $chkTest.checked
      
      if tb.dispatch(chkTest2, coords).contains MouseUp:
        if chkTest2.checked:
          infoBox.text = "red"
          tb.setForegroundColor fgRed
        else:
          infoBox.text = "green"
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
      
  
      if chkDraw.checked:
        if coords.action == MouseButtonAction.Pressed:
          tb.write coords.x, coords.y, fgRed, "♥"
        else:
          tb.write coords.x, coords.y, fgGreen, "⌀"
        
    else:
      echo key
      discard
    
    tb.render(btnClear)
    tb.render(btnTest)
    tb.render(chkTest)
    tb.render(chkTest2)
    tb.render(chkDraw)

    tb.render(chkRadA)
    tb.render(chkRadB)
    tb.render(chkRadC)

    # Update the info box to always be on the bottom
    infoBox.w = terminalWidth()
    infoBox.y = terminalHeight()-1
    tb.render(infoBox)
    
    # No need to update
    tb.render(infoBoxMouse)

    tb.render(chooseBox)

    tb.display()
    sleep(20)
