## The cockpit's quick menu: a tap on the left menu button opens a short list; the control scheme
## is an item here now. Desktop uses the release pause overlay for Esc. The view supplies the items
## and acts on them: each is {key, label, value (a String, shown), }.
##   var m := MainMenu.new()
##   m.items = [...]; m.open = true
##   m.move(1)              the next item (wraps)
##   m.key()                the key of the item the cursor's on
##   m.text()               the panel's lines, the cursor on its item
## A page of the menu with more lines than a panel holds (the cockpit's holds ROWS: an eleventh runs off
## it) is laid out as panels:
##   m.items = m.lay([[...], [...]], {"key": "back", "label": "BACK"})
## Each list begins a panel of its own, a list too long for one runs on to the next, and every panel ends
## with the foot line, which says where stepping on past it goes. `items` is then the panel that is up,
## `page` which one that is, and nothing else about the menu changes: the cursor, key() and the lines are
## that panel's. move() steps off a panel's last line onto the next panel's first (and off its first onto
## the one before's last); round the last panel it comes back to the first. Asking lay() again (a line's
## value has changed) keeps the panel that is up. A menu given plain items has no panels and is as it was.
extends RefCounted

const ROWS := 10                # the lines a panel holds
var open := false
var at := 0
var items: Array = []
var title := "FLIGHT HOLD"      # the panel's first line (the headset's second page is OPTIONS)
var pages: Array = []           # the panels lay() made (each a list of items); empty for a plain menu
var page := 0                   # the panel that is up


## `lists` laid out as panels of at most `rows` lines, each ending with `foot`. -> the items of the panel
## that is up (`page`, kept inside what there is now).
func lay(lists: Array, foot: Dictionary, rows := ROWS) -> Array:
	var bodies: Array = []
	for list: Array in lists:
		var k := 0
		while k < list.size():
			bodies.append(list.slice(k, k + rows - 1))
			k += rows - 1
	if bodies.is_empty():
		bodies.append([])
	pages = []
	for k in bodies.size():
		var last: Dictionary = foot.duplicate()
		if bodies.size() > 1:      # where stepping on from the foot goes
			last["value"] = "(DOWN: PAGE %d)" % ((k + 1) % bodies.size() + 1)
		var panel: Array = bodies[k]
		panel.append(last)
		pages.append(panel)
	page = clampi(page, 0, pages.size() - 1)
	items = pages[page]      # (up from now: whoever asked need not have given it back)
	return items


## Is the panel that is up one of several? (`items` is then lay()'s own list, not a plain one given since.)
func paged() -> bool:
	return pages.size() > 1 and page < pages.size() and is_same(items, pages[page])


func move(d: int) -> void:
	if items.is_empty():
		return
	var to := at + d
	if paged() and (to < 0 or to >= items.size()):
		page = posmod(page + (1 if d > 0 else -1), pages.size())
		items = pages[page]
		at = 0 if d > 0 else items.size() - 1
		return
	at = posmod(to, items.size())


func key() -> String:
	return String(items[at].key) if at >= 0 and at < items.size() else ""


func text() -> String:
	var out := PackedStringArray([title + ("   %d / %d" % [page + 1, pages.size()] if paged() else ""), ""])
	for k in items.size():
		var it: Dictionary = items[k]
		var v := String(it.get("value", ""))
		out.append("%s %s%s" % [">" if k == at else " ", it.label, ("   " + v) if v != "" else ""])
	return "\n".join(out)
