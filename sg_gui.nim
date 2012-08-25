import
  sfml, sfml_vector, sfml_colors,
  input
{.deadCodeElim: on.}
type
  PGuiContainer* = ref TGuiContainer
  TGuiContainer* = object of TObject
    position: TVector2f
    activeEntry: PTextEntry
    widgets: seq[PGuiObject]
    buttons: seq[PButton]
    renderState*: PRenderStates
  PGuiObject* = ref TGuiObject
  TGuiObject* = object of TObject
  PButton* = ref TButton
  TButton* = object of TGuiObject
    enabled: bool
    bg: sfml.PRectangleShape
    text: PText
    onClick*: TButtonClicked
    bounds: TFloatRect
  PButtonCollection* = ref TButtonCollection
  TButtonCollection* = object of TGuiContainer
  PTextEntry* = ref TTextEntry
  TTextEntry* = object of TButton
    inputClient: input.PTextInput
  PMessageArea* = ref TMessageArea
  TMessageArea* = object of TGuiObject
    pos: TVector2f
    messages: seq[PText]
  TButtonClicked = proc(button: PButton)
var
  guiFont* = newFont("data/fnt/LiberationMono-Regular.ttf")
  messageProto* = newText("", guiFont, 16)
let
  vectorZeroF* = vec2f(0.0, 0.0)

proc newGuiContainer*(): PGuiContainer
proc free*(container: PGuiContainer)
proc add*(container: PGuiContainer; widget: PGuiObject)
proc clearButtons*(container: PGuiContainer)
proc click*(container: PGuiContainer; position: TVector2f)
proc setActive*(container: PGuiContainer; entry: PTextEntry)

proc update*(container: PGuiContainer; dt: float)
proc draw*(window: PRenderWindow; container: PGuiContainer) {.inline.}

proc newMessageArea*(container: PGuiContainer; position: TVector2f): PMessageArea {.discardable.}
proc add*(m: PMessageArea; text: string): PText {.discardable.}

proc draw*(window: PRenderWindow; b: PButton; rs: PRenderStates) {.inline.}
proc click*(b: PButton; p: TVector2f)
proc setPosition*(b: PButton; p: TVector2f)
proc setString*(b: PButton; s: string) {.inline.}

proc newButton*(container: PGuiContainer; text: string; position: TVector2f; 
  onClick: TButtonClicked; startEnabled: bool = true): PButton {.discardable.}
proc init(b: PButton; text: string; position: TVector2f; onClick: TButtonClicked)
proc disable*(b: PButton)
proc enable*(b: PButton)

proc newTextEntry*(container: PGuiContainer; text: string;
                    position: TVector2f): PTextEntry {.discardable.}
proc init(t: PTextEntry; text: string)
proc draw*(window: PRenderWindow, t: PTextEntry) {.inline.}
proc setActive*(t: PTextEntry) {.inline.}
proc getText*(t: PTextEntry): string {.inline.}

template containerWrapper(procname: expr; args: expr): stmt {.immediate.} =
  result = procname(args)
  add(container, result)

if guiFont == nil:
  echo("Could not load font, crying softly to myself.")
  quit(1)

proc newGuiContainer*(): PGuiContainer =
  new(result, free)
  result.widgets = @[]
  result.buttons = @[]
  result.renderState = cast[PRenderStates](alloc0(sizeof(TRenderStates)))
  result.renderState.transform = identityMatrix ##transformFromMatrix(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
proc free*(container: PGuiContainer) = 
  dealloc(container.renderState)
proc add*(container: PGuiContainer; widget: PGuiObject) =
  container.widgets.add(widget)
proc add*(container: PGuiContainer; button: PButton) =
  container.buttons.add(button)
proc clearButtons*(container: PGuiContainer) =
  container.buttons.setLen 0
proc click*(container: PGuiContainer; position: TVector2f) =
  for b in container.buttons:
    click(b, position)
proc setActive*(container: PGuiContainer; entry: PTextEntry) =
  container.activeEntry = entry
  setActive(entry)
proc setPosition*(container: PGuiContainer; position: TVector2f) =
  container.position = position


proc update*(container: PGuiContainer; dt: float) =
  if not container.activeEntry.isNil:
    container.activeEntry.setString(container.activeEntry.getText())
proc draw*(window: PRenderWindow; container: PGuiContainer) =
  for b in container.buttons:
    window.draw(b, container.renderState)

proc free(c: PButton) =
  c.bg.destroy()
  c.text.destroy()
  c.bg = nil
  c.text = nil
  c.onClick = nil
proc newButton*(container: PGuiContainer; text: string;
                 position: TVector2f; onClick: TButtonClicked;
                 startEnabled: bool = true): PButton =
  new(result, free)
  init(result, text, position + container.position, onClick)
  if not startEnabled: disable(result)
  container.add result
proc init(b: PButton; text: string; position: TVector2f; onClick: TButtonClicked) =
  b.bg = newRectangleShape()
  b.bg.setSize(vec2f(80.0, 16.0))
  b.bg.setFillColor(color(20, 30, 15))
  b.text = newText(text, guiFont, 16)
  b.onClick = onClick
  b.setPosition(position)
  b.enabled = true
proc copy*(c: PButton): PButton =
  new(result, free)
  result.bg = c.bg.copy()
  result.text = c.text.copy()
  result.onClick = c.onClick
  result.setPosition(result.bg.getPosition())

proc enable*(b: PButton) =
  b.enabled = true
  b.text.setColor(White)
proc disable*(b: PButton) =
  b.enabled = false
  b.text.setColor(Gray)
proc draw*(window: PRenderWindow; b: PButton; rs: PRenderStates) =
  window.draw(b.bg, rs)
  window.draw(b.text, rs)
proc setPosition*(b: PButton, p: TVector2f) =
  b.bg.setPosition(p)
  b.text.setPosition(p)
  b.bounds = b.text.getGlobalBounds()
proc setString*(b: PButton; s: string) =
  b.text.setString(s)
proc click*(b: PButton, p: TVector2f) = 
  if b.enabled and (addr b.bounds).contains(p.x, p.y): 
    b.onClick(b)

proc free(obj: PTextEntry) =
  free(PButton(obj))
proc newTextEntry*(container: PGuiContainer; text: string; 
                    position: TVector2F): PTextEntry =
  new(result, free)
  init(PButton(result), text, position + container.position, proc(b: PButton) = setActive(PTextEntry(b)))
  init(result, text)
  container.add result
proc init(t: PTextEntry, text: string) =
  t.inputClient = newTextInput(text, text.len)
proc draw(window: PRenderWindow; t: PTextEntry) =
  draw(window, PButton(t), nil)
proc getText*(t: PTextEntry): string =
  return t.inputClient.text
proc setActive*(t: PTextEntry) =
  if not t.isNil and not t.inputClient.isNil:
    input.setActive(t.inputClient)


proc newMessageArea*(container: PGuiContainer; position: TVector2f): PMessageArea =
  new(result)
  result.messages = @[]
  result.pos = position
  container.add(result)
proc add*(m: PMessageArea, text: string): PText =
  result = messageProto.copy()
  result.setString(text)
  m.messages.add(result)
  let nmsgs = len(m.messages)
  var pos   = vec2f(m.pos.x, m.pos.y)
  for i in countdown(nmsgs - 1, max(nmsgs - 30, 0)):
    setPosition(m.messages[i], pos)
    pos.y -= 16.0

proc draw*(window: PRenderWindow; m: PMessageArea) =
  let nmsgs = len(m.messages) 
  if nmsgs == 0: return
  for i in countdown(nmsgs - 1, max(nmsgs - 30, 0)):
    window.draw(m.messages[i])


