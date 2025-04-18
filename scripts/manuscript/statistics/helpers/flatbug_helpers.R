train_repository <- "https://anon.erda.au.dk/share_redirect/OzZk71Y5SS"
fb_repository <- "https://anon.erda.au.dk/share_redirect/Bb0CR1FHG6"

chr_equal <- function(a, b) {
  return(as.character(a) == as.character(b))
}

show_progress <- function() !isTRUE(getOption("full_analysis_running"))

# Auto select email if possible
"
dataset,short_name
abram2023,ABR
ALUS,ALU
amarathunga2022,AMA
AMI-traps,AMI
AMT,AMT
anTraX,ATX
ArTaxOr,ATO
biodiscover-arm,BDA
BIOSCAN,BIS
blair2020,BLR
cao2022,CAO
CollembolAI,CAI
Diopsis,DPS
DIRT,DIR
DiversityScanner,DIS
gernat2018,GER
https://www.mdpi.com/2077-0472/12/11/1967,IUL
InsectCV,ICV
mosquitos-citizen-science,MCS
Mothitor,MOI
NHM-beetles-crops,NBC
PeMaToEuroPep,PME
pinoy2023,PIN
sittinger2023,SIT
STARdbi,STA
sticky-pi,SPI
ubc-pitfall-traps,UPT
ubc-scanned-sticky-cards-2023,USC
vespAI,VES
" %>% 
  read_csv(show_col_types = F) -> short_index

short_name <- Vectorize(
  memoise::memoise(function(x, dict=short_index) {
    if (is.na(x) || !(is.character(x) || is.factor(x)) || nchar(as.character(x)) == 0) return(NA_character_)
    left_match <- stringr::str_detect(dict$dataset, stringr::regex(stringr::str_escape(x), ignore_case = T))
    right_match <- stringr::str_detect(x, stringr::regex(stringr::str_escape(dict$dataset), ignore_case = T))
    any_match <- left_match | right_match
    which_match <- which(any_match)
    if (length(which_match) != 1) {
      return(NA_character_)
    }
    return(dict$short_name[which_match])
  }
), USE.NAMES = FALSE)

# post-hoc statistics for leave-one-out and compare backbone size experiment
# figures

confint_element <- function(x, position = c("edge", "center"), expand = c(0.1, 0), labels = scales::label_number(2), sep = c(" ", ", ")) {
  position <- match.arg(position, c("edge", "center"))
  if (position == "edge") {
    p <- max(abs(x[sign(x) == sign(x[2])])) * sign(x[2])  
  }
  else if (position == "center") {
    p <- x[2]
  }
  else {
    stop("Undefined position of confint element")
  }
  p <- p * (1 + expand[1]) + sign(p) * expand[2]
  x <- labels(x)
  l <- str_c(x[2], sep[1], "[", x[1], sep[2], x[3], "]")
  return(tibble(position = p, label = l))
}

findoutlier <- function(x, w=NULL, na.rm = T) {
  na_action <- if (na.rm) na.omit else na.fail
  # quantreg::rq(y ~ 1, weights = weight, data = data, tau = qs)
  if (is.null(w)) {
    q1 <- quantile(x, 0.25, na.rm = na.rm)
    q3 <- quantile(x, 0.75, na.rm = na.rm) 
  }
  else {
    q1 <- quantreg::rq(x ~ 1, weights = w, tau = 0.25, na.action = na_action)
    q3 <- quantreg::rq(x ~ 1, weights = w, tau = 0.75, na.action = na_action)
    q1 <- coef(q1)
    q3 <- coef(q3)
  }
  iqr <- q3 - q1
  lower <- q1 - 1.5 * iqr
  upper <- q3 + 1.5 * iqr
  outlier <- (x < lower | x > upper)
  # hinge_min <- min(x[!outlier], na.rm = na.rm)
  # hinge_max <- max(x[!outlier], na.rm = na.rm)
  # outlier & (x < hinge_min | x > hinge_max)
  return(outlier)
}

quantile_ranges <- function(q) {
  # Calculates the "ranges" between a set of quantiles:
  # The range for a quantile is given by the distances between the midpoints with neighbouring quantiles
  # Note: Edge-conditions are accounted for.
  ord <- order(q)
  q <- q[ord]
  n <- length(q)
  lag_q <- lag(q, default = 0)[1:n]
  lead_q <- lead(q, default = 1)[1:n]
  
  qr <- (q - lag_q) * c(1, rep(0.5, n - 1)) + 
    (lead_q - q) * c(rep(0.5, n - 1), 1)
  
  qr[order(ord)]
}

weighted_cl_boot <- function(x, w=rep(1, length(x)), conf.int=.95, boot=1000, na.rm=T) {
  if (na.rm) {
    nas <- is.na(x) | is.na(w)
    x <- x[!nas]
    w <- w[!nas]
  }
  cf <- (1 - conf.int) / 2
  w <- w / sum(w)
  rx <- sapply(seq(boot), function(...) mean(sample(x, length(x), T, prob=w)))
  est <- weighted.mean(x, w)
  correct <- max(table(factor(sign(rx), c(-1, 0, 1))))
  incorrect <- boot - correct
  lu_ci <- coxed::bca(rx - est, conf.int) + est
  
  tibble(
    ymin = lu_ci[1],
    y = est,
    ymax = lu_ci[2],
    pval = (incorrect + 1)/(boot + 1)
  )
}

weighted_median <- function(x, w=rep(1, length(x))) {
  w <- w / mean(w)
  ord <- order(x)
  
  x <- x[ord]
  w <- w[ord]
  
  cdf <- cumsum(w)
  
  return(x[first(which(cdf >= 0.5))])
}

## Plotting

label_pvalue <- function(x, accuracy = 0.0001, signif.symbol="*", ns="ns") {
  nf <- function(n) scales::number(n, accuracy, drop0trailing=T)
  xr <- nf(x)
  xr[x < accuracy] = str_c("<", nf(accuracy))
  symbols <- log10(x / 0.05)
  symbols <- symbols - 0.01 * (symbols %% 1 == 0)
  symbols <- pmin(abs(floor(symbols)), 3)
  symbols <- sapply(symbols, function(s) if (s == 0) str_c(" ", ns) else str_c(rep(signif.symbol, s), collapse=""))
  str_c(xr, symbols)
}

image_circlecut <- function(image, r=1, border=F, thickness=1){
  # Extract width/height
  info <- magick::image_info(image)
  w <- info$width
  h <- info$height
  circ <- floor((w - 3 - thickness)*r/2)
  
  # Circle mask
  mask <- magick::image_draw(magick::image_blank(w, h))
  symbols(x = w/2, y = h/2, circles = circ, inches = FALSE,
          bg = "black", add = TRUE)
  dev.off()
  
  # Add opacity to original image
  image <- magick::image_composite(image, mask, operator = "CopyOpacity")
  
  # Border
  if (border & thickness > 0) {
    l <- ceiling((thickness - 1)/2)
    r <- floor((thickness - 1)/2)
    thickness_offset <- -l:r
    
    mask <- magick::image_draw(mask)
    symbols(x = rep(w/2, thickness), y = rep(h/2, thickness), circles = circ + rev(thickness_offset), inches = FALSE,
            bg = "white", fg = "black", add = TRUE)
    dev.off()
    
    image <- magick::image_composite(image, mask, operator = "Multiply")
  }
  image
}

close_neighbor_dir <- function(x, y, t=0.01, what="y") {
  n <- length(x)
  w <- if (what == "y") y else x
  dm <- dist(matrix(c(x,y), ncol = 2)) %>% 
    as.matrix
  n <- apply(dm, 1, function(z) which(z == min(abs(z[z != 0])))[1])
  d <- w - w[n]
  sign(d) * (abs(d) <= t)
}

nice_limits <- function(x) {
  s <- sign(x)
  if (s[1] == s[2]) {
    if (s[1] == -1) s[2] <- 0
    if (s[1] == 1) s[1] <- 0
  }
  r <- max(abs(x))
  if (0 %in% s) {
    r <- pmax(r, 1)
  }
  r * s
}

plot_matrix <- function(mat, limits=nice_limits, title=NULL, text=F) {
  d <- as.data.frame(mat) %>% 
    rownames_to_column("left") %>% 
    as_tibble %>%
    pivot_longer(!left, names_to = "right", values_to = "rel_delta") %>% 
    mutate(across(c(left, right), ~factor(.x, sort(unique(as.character(left))))))
  
  p <- d %>% 
    ggplot(aes(left, right, fill = rel_delta)) +
    geom_raster() +
    scale_fill_flatbug_c(palette = "RdWiBu", limits = limits, expand = expansion()) +
    coord_equal(expand = F) +
    labs(x = NULL, y = NULL, title = title) +
    theme(axis.text.x = element_text(hjust = 1, vjust = 0.5, angle = 90))
  
  if (text) {
    p <- p +
      geom_text(
        aes(label = str_remove(scales::label_percent(1)(rel_delta), "%")), 
        size = 2,
        hjust = 0.5, 
        fontface = "bold", 
        family = "CMU Serif"
      )
  }
  
  p
}


## Latex data management
start_pattern <- "% ### <NAME> ###"
end_pattern   <- "% ### </NAME> ###"

make_data_file <- function(file="experiment_results_latex.tex", clear=TRUE, header=c("% Automatically generated data file", "")) {
  write_lines(header, file, append = !clear)
  invisible()
}

find_group <- function(name, lines) {
  start <- str_replace(start_pattern, "NAME", name)
  end <- str_replace(end_pattern, "NAME", name)
  start <- which(str_detect(lines, str_escape(start))) 
  if (length(start) == 0) stop(str_c("Unable to find group (", name, ") in data."))
  if (length(start) > 1) stop(str_c("Found duplicate entries for group (", name, ") in data"))
  end <- which(str_detect(lines, str_escape(end)))
  if (length(end) == 0) stop(str_c("Unable to find end-of-group (", name, ") in data."))
  if (length(end) > 1) stop(str_c("Found duplicate entries for end-of-group (", name, ") in latex data file (", file, ")"))
  if (end <= start) stop(str_c("Found invalid start- and end-of-group (", name, ") in latex data file (", file, ")"))
  return(c(start, end))
}

add_group <- function(name, file="experiment_results_latex.tex") {
  group_exists <- tryCatch({
    find_group(name, read_lines(file))
    TRUE
  }, error = function(x) FALSE)
  if (group_exists) stop(str_c("Group (", name, ") already exists in latex data file (", file, "). If you are updating the values it is best practice to clear the data file; run `make_data_file()`."))
  start <- str_replace(start_pattern, "NAME", name)
  end <- str_replace(end_pattern, "NAME", name)
  write_lines(c("", start, "", end), file, append = TRUE)
}

get_data <- function(name, file="experiment_results_latex.tex") {
  if (!file.exists(file)) stop(str_c("Latex data file (", file, ") does not exist. Perhaps call `make_data_file`."))
  lines <- read_lines(file)
  SE <- find_group(name, lines)
  return(lines[(SE[1] + 1):(SE[2] - 1)])
}

write_data <- function(name, data, file="experiment_results_latex.tex") {
  if (!file.exists(file)) stop(str_c("Latex data file (", file, ") does not exist. Perhaps call `make_data_file`."))
  lines <- read_lines(file)
  SE <- find_group(name, lines)
  lines <- c(lines[1:SE[1]], data, lines[SE[2]:length(lines)])
  write_lines(lines, file)
  return(invisible(lines))
}


