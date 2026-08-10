class_name ChatFilter
extends RefCounted

# List of banned words. We keep this simple to update by just editing this array.
const BANNED_WORDS: PackedStringArray = [
	"fuck", "shit", "ass", "bitch", "damn", "crap", "dick", "bastard",
	"nigger", "nigga", "faggot", "retard", "slut", "whore", "cock", "pussy", "cunt"
]

# We store the compiled RegEx objects here to reuse them
var _regexes: Array[RegEx] = []

func _init() -> void:
	# Compile regexes for each banned word when the object is created
	for word in BANNED_WORDS:
		# Build a regex pattern that matches the word with optional separators
		# \b ensures we only match whole words, not partial matches within larger words
		var pattern: String = "\\b"
		
		# Insert an optional separator class between each character
		for i in range(word.length()):
			pattern += word[i]
			# Allow optional dots, spaces, hyphens, or underscores between letters
			if i < word.length() - 1:
				pattern += "[\\.\\s\\-_]*"
		
		pattern += "\\b"
		
		# Compile the regex. (?i) makes it case-insensitive.
		var regex := RegEx.new()
		var error := regex.compile("(?i)" + pattern)
		
		if error == OK:
			_regexes.append(regex)
		else:
			push_error("Failed to compile regex for banned word: " + word)

# Filters the text, replacing any matched banned words with '***'
func filter(text: String) -> String:
	var filtered_text := text
	for regex in _regexes:
		# Replace matches with '***'
		filtered_text = regex.sub(filtered_text, "***", true)
	return filtered_text
