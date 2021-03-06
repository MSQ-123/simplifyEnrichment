
# == title
# Calculate word frequency
#
# == param
# -go_id A vector of GO IDs.
# -term The corresponding names or description of terms if the input are not GO terms.
# -exclude_words The words that should be excluded.
#
# == details
# The input can be simply set with a vector of GO id to ``go_id`` argument that the GO names
# are automatically extracted. If the input are not GO terms, users need to provide a vector of long names/descriptions by ``term`` argument.
#
# If the input is GO id, the following words are excluded: ``c("via", "protein", "factor", "side", "type", "specific")``.
# They are analyzed by ``simplifyEnrichment:::all_GO_word_count()``.
#
# The text preprocessing followings the instructions from http://www.sthda.com/english/wiki/word-cloud-generator-in-r-one-killer-function-to-do-everything-you-need .
#
# == value
# A data frame with words and frequencies.
#
# == example
# \donttest{
# go_id = random_GO(500)
# head(count_word(go_id))
# }
count_word = function(go_id, term = NULL, exclude_words = NULL) {
	
	if(is.null(term)) {
		if(is_GO_id(go_id[1])) {
			suppressMessages(term <- select(GO.db::GO.db, keys = go_id, columns = "TERM")$TERM)
		} else {
			stop_wrap("Cannot automatically retrieve the term names by the input ID, please set values for `term` argument manually.")
		}
	}

	# http://www.sthda.com/english/wiki/word-cloud-generator-in-r-one-killer-function-to-do-everything-you-need

	# Load the text as a corpus
	suppressWarnings({
		docs = Corpus(VectorSource(term))
		# Convert the text to lower case
		docs = tm_map(docs, content_transformer(tolower))
		# Remove numbers
		docs = tm_map(docs, removeNumbers)
		# Remove stopwords for the language 
		docs = tm_map(docs, removeWords, stopwords())
		# Remove punctuations
		docs = tm_map(docs, removePunctuation)
		# Eliminate extra white spaces
		docs = tm_map(docs, stripWhitespace)
		# Remove your own stopwords
		docs = tm_map(docs, removeWords, c(exclude_words, GO_EXCLUDE_WORDS))
		
		# Create term-document matrix
		tdm = TermDocumentMatrix(docs)
	})

	v = sort(slam::row_sums(tdm), decreasing = TRUE)
	d = data.frame(word = names(v), freq = v, stringsAsFactors = FALSE)
	d
}

is_GO_id = function(x) {
	grepl("^GO:[0-9]+$", x)
}


# generate excluded words that are too general
all_GO_word_count = function() {
	all_go = as.list(GO.db::GOTERM)

	ontology = vapply(all_go, slot, "Ontology", "a")
	term = vapply(all_go, slot, "Term", "a")

	lt = tapply(term, ontology, function(x) {
		df = count_word(term = x)
		df = df[order(df$freq, decreasing = TRUE)[seq_len(min(50, nrow(df)))], ]
	})
	lt[c("BP", "CC", "MF")]
}

GO_EXCLUDE_WORDS = c("via", "protein", "factor", "side", "type", "specific")

# == title
# A simple grob for the word cloud
#
# == param
# -text A vector of words.
# -fontsize The corresponding font size. With the frequency of the words known, `scale_fontsize` can be used to linearly interpolate frequencies to font sizes.
# -line_space Space between lines. The value can be a `grid::unit` object or a numeric scalar which is measured in mm.
# -word_space Space between words. The value can be a `grid::unit` object or a numeric scalar which is measured in mm.
# -max_width The maximal width of the viewport to put the word cloud. The value can be a `grid::unit` object or a numeric scalar which is measured in mm.
#        Note this might be larger than the final width of the returned grob object.
# -col Colors for the words. The value can be a vector, in numeric or character, which should have the same
#      length as ``text``. Or it is a self-defined function that takes the font size vector as 
#      the only argument. The function should return a color vector. See Examples.
# -test Internally used. It basically adds borders to the words and the viewport.
#
# == value
# A `grid::grob` object. The width and height of the grob can be get by `grid::grobWidth` and `grid::grobHeight`.
#
# == example
# # very old R versions do not have strrep() function
# if(!exists("strrep")) {
#     strrep = function(x, i) paste(rep(x, i), collapse = "")
# }
# words = sapply(1:30, function(x) strrep(sample(letters, 1), sample(3:10, 1)))
# require(grid)
# gb = word_cloud_grob(words, fontsize = runif(30, min = 5, max = 30), 
#     max_width = 100)
# grid.newpage(); grid.draw(gb)
#
# # color as a single scalar
# gb = word_cloud_grob(words, fontsize = runif(30, min = 5, max = 30), 
#     max_width = 100, col = 1)
# grid.newpage(); grid.draw(gb)
#
# # color as a vector
# gb = word_cloud_grob(words, fontsize = runif(30, min = 5, max = 30), 
#     max_width = 100, col = 1:30)
# grid.newpage(); grid.draw(gb)
#
# # color as a function
# require(circlize)
# col_fun = colorRamp2(c(5, 17, 30), c("blue", "black", "red"))
# gb = word_cloud_grob(words, fontsize = runif(30, min = 5, max = 30), 
#     max_width = 100, col = function(fs) col_fun(fs))
# grid.newpage(); grid.draw(gb)
#
word_cloud_grob = function(text, fontsize, 
	line_space = unit(4, "pt"), word_space = unit(4, "pt"), max_width = unit(80, "mm"), 
	col = function(fs) circlize::rand_color(length(fs), luminosity = "dark"),
	test = FALSE) { # width in mm

	if(length(text) != length(fontsize)) {
		stop_wrap("`text` and `fontsize` should the same length.")
	}
	
	od = order(fontsize, decreasing = TRUE)
	text = text[od]
	fontsize = fontsize[od]

	if(Sys.info()["sysname"] == "Darwin" && dev.interactive()) {
		ComplexHeatmap:::dev.null()
		on.exit(ComplexHeatmap:::dev.off2())
	}

	n = length(text)
	text_gb_lt = lapply(seq_len(n), function(i) textGrob(text[i], gp = gpar(fontsize = fontsize[i])))
	text_width = vapply(text_gb_lt, function(gb) convertWidth(grobWidth(gb), "mm", valueOnly = TRUE), 0)
	text_height = vapply(text_gb_lt, function(gb) convertHeight(grobHeight(gb), "mm", valueOnly = TRUE), 0)

	if(is.unit(line_space)) line_space = convertHeight(line_space, "mm", valueOnly = TRUE)
	if(is.unit(word_space)) word_space = convertWidth(word_space, "mm", valueOnly = TRUE)

	x = numeric(n)
	y = numeric(n)
	current_line_height = 0
	current_line_width = 0

	# the first text
	current_line_height = text_height[1]
	current_line_width = text_width[1]
	x[1] = 0
	y[1] = 0

	w = text_width[1]
	h = text_height[1]

	if(is.unit(max_width)) {
		max_width = convertWidth(max_width, "mm", valueOnly = TRUE)
	} 

	for(i in seq_len(n)[-1]) {
		# the next text can be put on the same line
		if(current_line_width + text_width[i] <= max_width) {
			x[i] = current_line_width + word_space
			y[i] = y[i-1] # same as previous one
			current_line_width = x[i] + text_width[i]
			w = max(w, current_line_width)
			h = max(h, y[i] + text_height[i])
		} else { # the next text need to be put on the next line
			x[i] = 0
			y[i] = current_line_height + line_space
			current_line_width = text_width[i]
			current_line_height = y[i] + text_height[i]
			w = max(w, current_line_width)
			h = max(h, current_line_height)
		}
	}

	if(is.character(col) || is.numeric(col)) {
		if(length(col) == 1) col = rep(col, n)
		col_fun = function(fontsize) return(col)
	} else if(is.function(col)) {
		col_fun = col
	} else {
		stop_wrap("`col` can only be a function or a character vector.")
	}

	if(test) {
		gl = gList(
			rectGrob(),
			textGrob(text, x = x, y = y, gp = gpar(fontsize = fontsize, col = col_fun(fontsize)), 
				default.units = "mm", just = c(0, 0)),
			rectGrob(x = x, y = y, width = text_width, height = text_height, default.units = "mm", just = c(0, 0))

		)
	} else {
		gl = gList(
			textGrob(text, x = x, y = y, gp = gpar(fontsize = fontsize, col = col_fun(fontsize)), 
				default.units = "mm", just = c(0, 0))
		)
	}

	gb = gTree(children = gl, cl = "word_cloud", vp = viewport(width = unit(w, "mm"), height = unit(h, "mm")))
	return(gb)
}

# == title
# Width for word_cloud grob
#
# == param
# -x The ``word_cloud`` grob returned by `word_cloud_grob`.
#
# == value
# A `grid::unit` object.
widthDetails.word_cloud = function(x) {
	x$vp$width
}

# == title
# Height for word_cloud grob
#
# == param
# -x The ``word_cloud`` grob returned by `word_cloud_grob`.
#
# == value
# A `grid::unit` object.
heightDetails.word_cloud = function(x) {
	x$vp$height
}

	