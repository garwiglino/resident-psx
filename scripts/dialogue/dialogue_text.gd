extends RefCounted

static func plain(text: String) -> String:
	var accented := "àáâäãåçèéêëìíîïñòóôöõùúûüýÿÀÁÂÄÃÅÇÈÉÊËÌÍÎÏÑÒÓÔÖÕÙÚÛÜÝŸ"
	var basic := "aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUYY"
	for index in accented.length():text=text.replace(accented[index],basic[index])
	return text.replace("œ","oe").replace("Œ","OE").replace("’","'").replace("‘","'").replace("—","-").replace("–","-").replace("…","...").replace("\r\n","\n").replace("\r","\n").replace("\t"," ")

static func paginate(text: String,font: Font,font_size: int,width: float,lines_per_page: int) -> Array[String]:
	var result: Array[String]=[]
	var normalized := plain(text).strip_edges()
	if normalized.is_empty():return result
	var available := maxf(width,16)
	var wrapped: Array[String]=[]
	# Whitespace is the only optional break: apostrophes and hyphens stay
	# with their word. Pre-wrap the full page before revealing any glyph.
	for paragraph in normalized.split("\n"):
		var row := ""
		for word in paragraph.split(" ",false):
			# Refuse an impossible layout instead of cutting or hiding a word.
			if font.get_string_size(word,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>available:return []
			var candidate := word if row.is_empty() else row+" "+word
			if not row.is_empty() and font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>available:
				wrapped.append(row);row=word
			else:row=candidate
		wrapped.append(row)
	var rows: PackedStringArray=[]
	for row in wrapped:
		rows.append(row)
		if rows.size()>=maxi(lines_per_page,1):result.append("\n".join(rows));rows.clear()
	if not rows.is_empty():result.append("\n".join(rows))
	return result

static func is_letter(character: String) -> bool:
	if character.is_empty():return false
	var code := character.unicode_at(0)
	return (code>=65 and code<=90) or (code>=97 and code<=122) or (code>=48 and code<=57)
