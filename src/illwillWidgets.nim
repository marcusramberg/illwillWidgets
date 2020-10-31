## A small widget library for illwill,

import illwill, macros, strutils
import strformat, os

macro preserveColor(pr: untyped) =
  ## this pragma saves the style before a render proc,
  ## and resets the style after a render proc
  result = newProc()
  result[0] = pr[0]
  let oldbody = pr.body
  result.params = pr.params
  result.body = quote do:
    let oldFg = tb.getForegroundColor()
    let oldBg = tb.getBackgroundColor()
    let oldStyle = tb.getStyle()
    tb.setForegroundColor(wid.color)
    tb.setBackgroundColor(wid.bgcolor)
    `oldbody`
    tb.setForegroundColor oldFg
    tb.setBackgroundColor oldBg
    tb.setStyle oldStyle

type
  Percent* = range[0.0..100.0]
  Event* = enum
    MouseHover, MouseUp, MouseDown
  Orientation* = enum
    Horizontal, Vertical
  Events* = set[Event]
  Widget* = object of RootObj
    x*: int
    y*: int
    color*: ForegroundColor
    bgcolor*: BackgroundColor
    style*: Style
    highlight*: bool
    autoClear*: bool
    shouldBeCleared: bool
  Button* = object of Widget
    text*: string
    w*: int
    h*: int
    border*: bool
  Checkbox* = object of Widget
    text*: string
    checked*: bool
    textChecked*: string
    textUnchecked*: string
  RadioBoxGroup* = object of Widget
    radioButtons*: seq[Checkbox]
  InfoBox* = object of Widget
    text*: string
    w*: int
    h*: int
  ChooseBox* = object of Widget
    bgcolorChoosen*: BackgroundColor
    choosenidx*: int
    w*: int
    h*: int
    elements*: seq[string]
    highlightIdx*: int
    chooseEnabled*: bool
    title*: string
    shouldGrow*: bool
  TextBox* = object of Widget
    text*: string
    placeholder*: string
    focus*: bool
    w*: int
    caretIdx*: int
  ProgressBar* = object of Widget
    text*: string
    l*: int ## the length (length instead of width for vertical)
    maxValue*: float
    value*: float
    orientation*: Orientation
    bgTodo*: BackgroundColor
    bgDone*: BackgroundColor
    colorText*: ForegroundColor

# Cannot do this atm because of layering!
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

# ########################################################################################################
# Widget
# ########################################################################################################
proc clear*(wid: var Widget) {.inline.} =
  wid.shouldBeCleared = true

# ########################################################################################################
# InfoBox
# ########################################################################################################
proc newInfoBox*(text: string, x, y: int, w = 10, h = 1, color = fgBlack, bgcolor = bgWhite): InfoBox =
  result = InfoBox(
    text: text,
    x: x,
    y: y,
    w: w,
    h: h,
    color: color,
    bgcolor: bgcolor,
  )

proc render*(tb: var TerminalBuffer, wid: InfoBox) {.preserveColor.} =
  # TODO save old text to only overwrite the len of the old text
  let  lines = wid.text.splitLines()
  for idx in 0..lines.len-1:
    tb.write(wid.x, wid.y+idx, lines[idx].alignLeft(wid.w))

proc inside(wid: InfoBox, mi: MouseInfo): bool =
  return (mi.x in wid.x .. wid.x+wid.w) and (mi.y == wid.y)

proc dispatch*(tb: var TerminalBuffer, wid: InfoBox, mi: MouseInfo): Events {.discardable.} =
  if not wid.inside(mi): return
  case mi.action
  of mbaPressed: result.incl MouseDown
  of mbaReleased: result.incl MouseUp
  of mbaNone: result.incl MouseHover

# ########################################################################################################
# Checkbox
# ########################################################################################################
proc newCheckbox*(text: string, x, y: int, color = fgBlue): Checkbox =
  result = Checkbox(
    text: text,
    x: x,
    y: y,
    color: color,
    textChecked: "[X] ",
    textUnchecked: "[ ] "
  )

proc render*(tb: var TerminalBuffer, wid: Checkbox) {.preserveColor.} =
  let check = if wid.checked: wid.textChecked else: wid.textUnchecked
  tb.write(wid.x, wid.y, check & wid.text)

proc inside(wid: Checkbox, mi: MouseInfo): bool =
  return (mi.x in wid.x .. wid.x+wid.text.len + 3) and (mi.y == wid.y)

proc dispatch*(tr: var TerminalBuffer, wid: var Checkbox, mi: MouseInfo): Events {.discardable.} =
  if not wid.inside(mi): return
  result.incl MouseHover
  case mi.action
  of mbaPressed:
    result.incl MouseDown
  of mbaReleased:
    wid.checked = not wid.checked
    result.incl MouseUp
  of mbaNone: discard

# ########################################################################################################
# RadioBox
# ########################################################################################################
proc newRadioBox*(text: string, x, y: int, color = fgBlue): Checkbox =
  ## Radio box is actually a checkbox, you need to add the checkbox to a radio button group
  result = newCheckbox(text, x, y, color)
  result.textChecked = "(X) "
  result.textUnchecked = "( ) "

proc newRadioBoxGroup*(radioButtons: seq[Checkbox]): RadioBoxGroup =
  ## Create a new radio box, add radio boxes to the group,
  ## then call the *groups* `render` and `dispatch` proc.
  result = RadioBoxGroup(
    radioButtons: radioButtons
  )

proc render*(tb: var TerminalBuffer, wid: RadioBoxGroup) {.preserveColor.} =
  for radioButton in wid.radioButtons:
    tb.render(radioButton)

proc dispatch*(tb: var TerminalBuffer, wid: var RadioBoxGroup, mi: MouseInfo): Events {.discardable.} =
  var insideSome = false
  for radioButton in wid.radioButtons.mitems:
    if radioButton.inside(mi): insideSome = true
  if (not insideSome) or (mi.action != mbaReleased): return
  for radioButton in wid.radioButtons.mitems:
    radioButton.checked = false
  for radioButton in wid.radioButtons.mitems:
    let ev = tb.dispatch(radioButton, mi)
    result.incl ev

proc element*(wid: RadioBoxGroup): Checkbox =
  ## returns the currect selected element of the `RadioBoxGroup`
  for radioButton in wid.radioButtons:
    if radioButton.checked:
      return radioButton

# ########################################################################################################
# Button
# ########################################################################################################
proc newButton*(text: string, x, y, w, h: int, border = true, color = fgBlue): Button =
  result = Button(
    text: text,
    highlight: false,
    x: x,
    y: y,
    w: w,
    h: h,
    border: border,
    color: color,
  )


proc render*(tb: var TerminalBuffer, wid: Button) {.preserveColor.} =
  if wid.border:
    if wid.autoClear or wid.shouldBeCleared: tb.fill(wid.x, wid.y, wid.x+wid.w, wid.y+wid.h)
    tb.drawRect(
      wid.x,
      wid.y,
      wid.x + wid.w,
      wid.y + wid.h,
      doubleStyle=wid.highlight,
    )
    tb.write(
      wid.x+1 + wid.w div 2 - wid.text.len div 2 ,
      wid.y+1,
      wid.text
    )
  else:
    var style = if wid.highlight: styleBright else: styleDim
    tb.write(
      wid.x + wid.w div 2 - wid.text.len div 2 ,
      wid.y,
      style, wid.text
    )

proc inside(wid: Button, mi: MouseInfo): bool =
  return (mi.x in wid.x .. wid.x+wid.w) and (mi.y in wid.y .. wid.y+wid.h)

proc dispatch*(tr: var TerminalBuffer, wid: var Button, mi: MouseInfo): Events {.discardable.} =
  ## if the mouse clicks this button
  if not wid.inside(mi):
    wid.highlight = false
    return
  result.incl MouseHover
  case mi.action
  of mbaPressed:
    wid.highlight = true
    result.incl MouseDown
  of mbaReleased:
    wid.highlight = false
    result.incl MouseUp
  of mbaNone:
    wid.highlight = true

# ########################################################################################################
# ChooseBox
# ########################################################################################################
proc grow*(wid: var ChooseBox) =
  ## call this to grow the box if you've added or removed a element
  ## from the `wid.elements` seq.
  if wid.elements.len >= wid.h: wid.h = wid.elements.len+1 # TODO allowedToGrow

proc add*(wid: var ChooseBox, elem: string) =
  ## adds element to the list, grows the box immediately
  wid.elements.add(elem)
  wid.grow()

proc newChooseBox*(elements: seq[string], x, y, w, h: int,
      color = fgBlue, label = "", choosenidx = 0, shouldGrow = true): ChooseBox =
  ## a list of text items to choose from, sometimes also called listbox
  ## if `shouldGrow == true` the chooseBox grows automatically when elements added
  result = ChooseBox(
    elements: elements,
    choosenidx: choosenidx,
    x: x,
    y: y,
    w: w,
    h: h,
    color: color,
  )
  result.highlightIdx = -1
  result.chooseEnabled = true
  if shouldGrow: result.grow()

proc setChoosenIdx*(wid: var ChooseBox, idx: int) =
  ## sets the choosen idex to a valid value
  wid.choosenidx = idx.clamp(0, wid.elements.len - 1)

proc nextChoosenidx*(wid: var ChooseBox, num = 1) =
  wid.setChoosenIdx(wid.choosenidx + num)

proc prevChoosenidx*(wid: var ChooseBox, num = 1) =
  wid.setChoosenIdx(wid.choosenidx - num)

proc element*(wid: ChooseBox): string =
  ## returns the currently selected element text
  try:
    return wid.elements[wid.choosenidx]
  except:
    return ""

proc clear(tb: var TerminalBuffer, wid: var ChooseBox) {.inline.} =
  tb.fill(wid.x, wid.y, wid.x+wid.w, wid.y+wid.h) # maybe not needet?
  wid.shouldBeCleared = false

proc render*(tb: var TerminalBuffer, wid: var ChooseBox) {.preserveColor.} =
  # if wid.autoClear or wid.shouldBeCleared:
  tb.clear(wid)
  for idx, elemRaw in wid.elements:
    if not wid.shouldGrow:
      if idx >= wid.h: continue # do not draw additional elements but render scrollbar
    let elem = elemRaw.alignLeft(wid.w)
    if idx == wid.choosenidx and wid.chooseEnabled:
      tb.write resetStyle
      tb.write(wid.x+1, wid.y+ 1 + idx, wid.color, wid.bgcolor, styleReverse, elem)
    else:
      tb.write resetStyle
      if idx == wid.highlightIdx:
        tb.write(wid.x+1, wid.y+ 1 + idx, wid.color, wid.bgcolor, styleBright, elem)
      else:
        tb.write(wid.x+1, wid.y+ 1 + idx, wid.color, wid.bgcolor, elem)
  tb.write resetStyle
  tb.drawRect(
    wid.x,
    wid.y,
    wid.x + wid.w,
    wid.y + wid.h,
    wid.highlight
  )
  if wid.title.len > 0:
    tb.write(wid.x + 2, wid.y, "| " & wid.title & " |")

proc inside(wid: ChooseBox, mi: MouseInfo): bool =
  return (mi.x in wid.x .. wid.x+wid.w) and (mi.y in wid.y .. wid.y+wid.h)

proc dispatch*(tr: var TerminalBuffer, wid: var ChooseBox, mi: MouseInfo): Events {.discardable.} =
  result = {}
  if wid.shouldGrow: wid.grow()
  if not wid.inside(mi): return
  result.incl MouseHover
  case mi.action
  of mbaPressed:
    result.incl MouseDown
  of mbaReleased:
    wid.choosenidx = clamp( (mi.y - wid.y)-1 , 0, wid.elements.len-1)
    result.incl MouseUp
  of mbaNone: discard

# ########################################################################################################
# TextBox
# ########################################################################################################
proc newTextBox*(text: string, x, y: int, w = 10,
      color = fgBlack, bgcolor = bgCyan, placeholder = ""): TextBox =
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

proc render*(tb: var TerminalBuffer, wid: TextBox) {.preserveColor.} =
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

proc dispatch*(tb: var TerminalBuffer, wid: var TextBox, mi: MouseInfo): Events {.discardable.} =
  if wid.inside(mi):
    result.incl MouseHover
    case mi.action
    of mbaPressed:
      result.incl MouseDown
    of mbaReleased:
      wid.focus = true
      result.incl MouseUp
    of mbaNone: discard
  elif not wid.inside(mi) and (mi.action == mbaReleased or mi.action == mbaPressed):
    wid.focus = false

proc handleKey*(tb: var TerminalBuffer, wid: var TextBox, key: Key): bool {.discardable.} =
  ## if this function return "true" the textbox lost focus by enter
  result = false

  template incCaret() =
    wid.caretIdx.inc
    wid.caretIdx = clamp(wid.caretIdx, 0, wid.text.len)
  template decCaret() =
    wid.caretIdx.dec
    wid.caretIdx = clamp(wid.caretIdx, 0, wid.text.len)

  if key == Key.Mouse: return false
  if key == Key.None: return false

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

template setKeyAsHandled*(key: Key) =
  ## call this on key when the key was handled by a textbox
  if key != Key.Mouse:
    key = Key.None

# ########################################################################################################
# ProgressBar
# ########################################################################################################
proc newProgressBar*(text: string, x, y: int, l = 10, value = 0.0, maxValue = 100.0,
    orientation = Horizontal, bgDone = bgGreen , bgTodo = bgRed): ProgressBar =
  result = ProgressBar(
    text: text,
    x: x,
    y: y,
    l: l,
    value: value,
    maxValue: maxValue,
    orientation: orientation,
    bgDone: bgDone,
    bgTodo: bgTodo
  )

proc percent*(wid: ProgressBar): float =
  ## Gets the percentage the progress bar is filled
  return (wid.value / wid.maxValue) * 100

proc `percent=`*(wid: var ProgressBar, val: float) =
  ## sets the percentage the progress bar should be filled
  # if val < 0
  wid.value = (val * wid.maxValue / 100.0).clamp(0.0, wid.maxValue)

proc render*(tb: var TerminalBuffer, wid: ProgressBar) {.preserveColor.} =
  # tb.write(wid.x, wid.y+1, fmt              ")
  # let num:int = ((wid.w-1).float * (percent)).int
  let num = (wid.l.float / 100.0).float * wid.percent
  if wid.orientation == Horizontal:
    let done = "=".repeat(num.int.clamp(0, int.high)) # [0..num]
    let todo = "-".repeat((wid.l - num.int).clamp(0, int.high)) # [num+1..^1]
    tb.write(wid.x, wid.y, wid.color, wid.bgDone, done, wid.bgTodo, todo)
    if wid.text.len == 0: return
    let tx = (wid.x + (wid.l div 2) ) - wid.text.len div 2
    tb.write(tx, wid.y, wid.colorText, wid.bgTodo, wid.text ) # TODO
    # tb.write(tx, wid.y, fgBlack, wid.bgTodo, wid.text[] )
    # tb.write(tx, wid.y, fgBlack, wid.bgDone, wid.text )
  elif wid.orientation == Vertical:
    discard
    # raise
    # DUMMY
    for idx in 0..wid.l:
      tb.write(wid.x-1, wid.y + idx, "O")
    # IMPL
    for todoIdx in 0..(wid.l - num.int):
      tb.write(wid.x, wid.y + num.int + todoIdx, bgRed, "-")
    for doneIdx in 0..num.int:
      let rest = wid.l - num.int
      tb.write(wid.x, wid.y + rest + doneIdx, bgGreen, "=")

proc inside(wid: ProgressBar, mi: MouseInfo): bool =
  return (mi.x in wid.x .. wid.x+wid.l) and (mi.y == wid.y)

# proc percentOnPos*(wid: ProgressBar, mi: MouseInfo): float =
#   let cell = ((mi.x - wid.x))
#   return (cell / wid.w)

proc valueOnPos*(wid: ProgressBar, mi: MouseInfo): float =
  if not wid.inside(mi): return 0.0
  let cell = ((mi.x - wid.x))
  return (cell / wid.l) * wid.maxValue

proc dispatch*(tb: var TerminalBuffer, wid: var ProgressBar, mi: MouseInfo): Events {.discardable.} =
  if not wid.inside(mi): return
  result.incl MouseHover
  case mi.action
  of mbaPressed:
    result.incl MouseDown
  of mbaReleased:
    result.incl MouseUp
  of mbaNone: discard