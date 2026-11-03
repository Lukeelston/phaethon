## The main menu (Luke: "add an option to the main menu"): a short list you step through, on a panel in
## the flat view (Esc) and in the cockpit (a tap on the left menu button; it used to cycle the control
## scheme, which is an item here now). The flight waits while it's open. The view supplies the items
## and acts on them: each is {key, label, value (a String, shown), }.
##   var m := MainMenu.new()
##   m.items = [...]; m.open = true
##   m.move(1)              the next item (wraps)
##   m.key()                the key of the item the cursor's on
##   m.text()               the panel's lines, the cursor on its item
extends RefCounted

var open := false
var at := 0
var items: Array = []


func move(d: int) -> void:
	if not items.is_empty():
		at = posmod(at + d, items.size())


func key() -> String:
	return String(items[at].key) if at < items.size() else ""


func text() -> String:
	var out := PackedStringArray(["MAIN MENU", ""])
	for k in items.size():
		var it: Dictionary = items[k]
		var v := String(it.get("value", ""))
		out.append("%s %s%s" % [">" if k == at else " ", it.label, ("   " + v) if v != "" else ""])
	return "\n".join(out)
