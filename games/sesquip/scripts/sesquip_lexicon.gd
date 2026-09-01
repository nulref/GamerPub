class_name SesquipLexicon
extends RefCounted
## In-memory prefix tree used by Sesquip. The source word list stays local so
## every legality check is immediate and the game has no network dependency.

const TERMINAL_KEY := "$"

var word_count := 0
var _root: Dictionary = {}


func _init(words: PackedStringArray = PackedStringArray()) -> void:
	for word in words:
		add_word(word)


func add_word(raw_word: String) -> bool:
	var word := normalize(raw_word)
	if word.length() < 3:
		return false

	var node := _root
	for index in range(word.length()):
		var letter := word.substr(index, 1)
		if not node.has(letter):
			node[letter] = {}
		node = node[letter]

	if bool(node.get(TERMINAL_KEY, false)):
		return false
	node[TERMINAL_KEY] = true
	word_count += 1
	return true


func is_prefix(raw_prefix: String) -> bool:
	var prefix := normalize(raw_prefix)
	if prefix.is_empty():
		return raw_prefix.strip_edges().is_empty() and not _root.is_empty()
	return not _node_for(prefix).is_empty()


func is_word(raw_word: String) -> bool:
	var word := normalize(raw_word)
	if word.is_empty():
		return false
	var node := _node_for(word)
	return not node.is_empty() and bool(node.get(TERMINAL_KEY, false))


func legal_letters(raw_prefix: String) -> PackedStringArray:
	var prefix := normalize(raw_prefix)
	if not raw_prefix.strip_edges().is_empty() and prefix.is_empty():
		return PackedStringArray()
	var node := _root if prefix.is_empty() else _node_for(prefix)
	var letters := PackedStringArray()
	for key in node.keys():
		var letter := String(key)
		if letter != TERMINAL_KEY:
			letters.append(letter)
	letters.sort()
	return letters


func has_continuations(raw_prefix: String) -> bool:
	return not legal_letters(raw_prefix).is_empty()


func is_terminal_word(raw_word: String) -> bool:
	return is_word(raw_word) and not has_continuations(raw_word)


func completion_count(raw_prefix: String) -> int:
	var prefix := normalize(raw_prefix)
	if not raw_prefix.strip_edges().is_empty() and prefix.is_empty():
		return 0
	var node := _root if prefix.is_empty() else _node_for(prefix)
	if node.is_empty():
		return 0
	return _count_terminals(node)


static func normalize(raw_value: String) -> String:
	var value := raw_value.strip_edges().to_upper()
	for index in range(value.length()):
		var codepoint := value.unicode_at(index)
		if codepoint < 65 or codepoint > 90:
			return ""
	return value


func _node_for(prefix: String) -> Dictionary:
	var node := _root
	for index in range(prefix.length()):
		var letter := prefix.substr(index, 1)
		if not node.has(letter):
			return {}
		node = node[letter]
	return node


func _count_terminals(node: Dictionary) -> int:
	var count := 1 if bool(node.get(TERMINAL_KEY, false)) else 0
	for key in node.keys():
		if String(key) != TERMINAL_KEY:
			count += _count_terminals(node[key])
	return count
