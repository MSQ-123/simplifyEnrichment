
dend_max_depth = function(dend) {
	max(unlist(dend_node_apply(dend, function(d, index) {
		length(index) + 1
	})))
}

# cluster the similarity matrix and assign scores to nodes
cluster_mat = function(mat, value_fun = median) {

	env = new.env()
	env$value_fun = value_fun
	.cluster_mat(mat, dist_mat = dist(mat), .env = env)

	dend = env$dend
	max_d = dend_max_depth(dend)
	dend = dendrapply(dend, function(d) {
		attr(d, "height") = max_d - attr(d, "height")
		d
	})

	# to correctly assign midpoint for each node
	dend2 = as.dendrogram(as.hclust(dend))
	dend = edit_node(dend, function(d, index) {
		if(is.null(index)) {  # top node
			if(!is.leaf(d)) {
				attr(d, "midpoint") = attr(dend2, "midpoint")
			}
		} else {
			if(!is.leaf(d)) {
				attr(d, "midpoint") = attr(dend2[[index]], "midpoint")
			}
		}
		return(d)
	})

	## s2 = max(s, s_child_none_leaf)
	dend = edit_node(dend, function(d, index) {
		s = attr(d, "score")
		if(is.leaf(d)) {
			attr(d, "score2") = s
		} else {
			l = sapply(d, is.leaf)
			if(all(l)) {
				attr(d, "score2") = s
			} else {
				attr(d, "score2") = max(s, sapply(d[!l], function(x) attr(x, "score")))
			}
		}

		return(d)
	})

	return(dend)
}

.cluster_mat = function(mat, dist_mat = dist(mat), .env, index = seq_len(nrow(mat)), 
	depth = 0, dend_index = NULL) {

	if(nrow(mat) == 1) {
		.env$dend[[dend_index]] = index
		attributes(.env$dend[[dend_index]]) = list(
			members = 1,
			label = "",
			leaf = TRUE,
			height = depth,
			score = 0.5,
			index = dend_index,
			class = "dendrogram"
		)
		return(NULL)
	}

	if(nrow(mat) == 2) {
		cl = c(1, 2)
	} else {
		# cl = cutree(hclust(dist_mat), k = 2)
		suppressWarnings(cl <- kmeans(mat, centers = 2)$cluster)
	}
	l1 = cl == 1
	l2 = cl == 2
	x11 = .env$value_fun(mat[l1, l1])
	x12 = .env$value_fun(mat[l1, l2])
	x21 = .env$value_fun(mat[l2, l1])
	x22 = .env$value_fun(mat[l2, l2])

	s = (x11 + x22)/(x11 + x12 + x21 + x22)
	if(is.na(s)) s = 1

	sr = numeric(1)
	for(i in 1:10) {
		clr = sample(cl, length(cl))
		l1r = clr == 1
		l2r = clr == 2
		x11r = sample(as.vector(mat[l1r, l1r]), 1)
		x12r = sample(as.vector(mat[l1r, l2r]), 1)
		x21r = sample(as.vector(mat[l2r, l1r]), 1)
		x22r = sample(as.vector(mat[l2r, l2r]), 1)

		sr[i] = (x11r + x22r)/(x11r + x12r + x21r + x22r)
		if(is.na(sr[i])) sr[i] = 1
	}
	sr = mean(sr)

	if(is.null(dend_index)) {
		.env$dend = list()
		attributes(.env$dend) = list(
			members = nrow(mat),
			height = depth,
			score = s,
			random_score = sr,
			index = NULL,
			class = "dendrogram"
		)
	} else {
		.env$dend[[dend_index]] = list()
		attributes(.env$dend[[dend_index]]) = list(
			members = nrow(mat),
			height = depth,
			score = s,
			random_score = sr,
			index = dend_index,
			class = "dendrogram"
		)
	}

	.cluster_mat(mat[l1, l1, drop = FALSE], as.dist(as.matrix(dist_mat)[l1, l1, drop = FALSE]), 
		.env, index = index[l1], depth = depth + 1, dend_index = c(dend_index, 1))
	.cluster_mat(mat[l2, l2, drop = FALSE], as.dist(as.matrix(dist_mat)[l2, l2, drop = FALSE]), 
		.env, index = index[l2], depth = depth + 1, dend_index = c(dend_index, 2))
}

cut_dend = function(dend, cutoff = 0.8, field = "score2") {

	children_score = function(dend, field) {
		if(is.leaf(dend)) {
			-Inf
		} else {
			d1 = dend[[1]]
			d2 = dend[[2]]
			c(attr(d1, field), attr(d2, field))
		}
	}

	dont_split = function(dend, field, cutoff) {
		s = attr(dend, field)

		if(s >= cutoff) {
			return(FALSE)
		} else {
			s_children = children_score(dend, field)
			all(s_children < cutoff)
		}
	}

	# if the top node
	if(dont_split(dend, field, cutoff)) {
		dend2 = dendrapply(dend, function(d) {
			attr(d, "height") = 0
			d
		})
		if(plot) {
			plot(dend)
			box()
		}
		return(dend2)
	}

	dend2 = edit_node(dend, function(d, index) {
		if(dont_split(d, field, cutoff)) {
			attr(d, "height") = 0
		}
		d
	})

	## make sure all sub-nodes having height 0 if the node is 0 height
	is_parent_zero_height = function(index) {
		h = sapply(seq_along(index), function(i) {
			attr(dend2[[ index[1:i] ]], "height")
		})
		any(h == 0)
	}
	dend2 = edit_node(dend2, function(d, index) {
		if(is_parent_zero_height(index)) {
			attr(d, "height") = 0
			attr(d, "nodePar") = NULL
		}
		d
	})

	cutree(as.hclust(dend2), h = 0.1)
}

plot_dend = function(dend, field = "score2", cutoff = 0.8) {
	col_fun = colorRamp2(c(0.5, 0.75, 1), c("blue", "yellow", "red"))
	dend = edit_node(dend, function(d, index) {
		if(is.null(index)) {
			if(!is.leaf(d)) {
				if(attr(dend, "height") > 0) {
					s = attr(d, field)
					attr(d, "nodePar") = list(pch = ifelse(s > cutoff, 16, 4), cex = 0.5, col = col_fun(s))
				}
			}
		} else {
			if(!is.leaf(d)) {
				if(attr(dend[[index]], "height") > 0) {
					s = attr(d, field)
					attr(d, "nodePar") = list(pch = ifelse(s > cutoff, 16, 4), cex = 0.5, col = col_fun(s))
				}
			}
		}
		return(d)
	})
	
	plot(dend)
	box()
}

binary_cut = function(mat, value_fun = median, cutoff = 0.8, n_run = 1) {
	if(n_run == 1) {
		dend = cluster_mat(mat, value_fun = value_fun)
		cl = cut_dend(dend, cutoff)
		return(cl)
	} else {
		partition_list = lapply(seq_len(n_run), function(i) {
			dend = cluster_mat(mat, value_fun = value_fun)
			cl = cut_dend(dend, cutoff)
            as.cl_hard_partition(cl)
        })
        partition_list = cl_ensemble(list = partition_list)
        partition_consensus = cl_consensus(partition_list)
        as.vector(cl_class_ids(partition_consensus)) 
	}
}

