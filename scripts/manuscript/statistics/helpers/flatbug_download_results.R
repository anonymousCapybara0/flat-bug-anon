library(furrr)
library(RCurl)

if (!dir.exists("data")) dir.create("data")


# Compare backbone sizes / Deployment models
plan(multisession, workers = round(availableCores() / 2))

tibble(
  size = c("L", "M", "S", "N") %>% 
    factor(., .),
  local_old = paste0("data/compare_backbone_sizes_", size, ".csv"),
  local_full = paste0("data/compare_backbone_sizes_", size, "_full.csv"),
  remote_old = train_repository %>% 
    paste0("/", size) %>% 
    paste0("_ucloud_done_V2/compare_backbone_sizes/eval/combined_results.csv"),
  remote_full = train_repository %>% 
    paste0("/", size) %>% 
    paste0(
      "_ucloud_done_V2/compare_backbone_sizes/eval/fb_compare_backbone_sizes_",
      size,
      "/eval/combined_results.csv"
    )
) %>% 
  mutate(
    result_old = future_map2(local_old, remote_old, function(local, path) {
      if (file.exists(local)) return(invisible())
      local <- CFILE(local, "wb")
      curlPerform(url = path, writedata = local@ref, noprogress = T)
      close(local)
      return(invisible())
    }, .progress = show_progress()),
    result_full = future_map2(local_full, remote_full, function(local, path) {
      if (file.exists(local)) return(invisible())
      local <- CFILE(local, "wb")
      curlPerform(url = path, writedata = local@ref, noprogress = T)
      close(local)
      return(invisible())
    }, .progress = show_progress())
  )

plan(sequential)

# Leave-one-out
paste0(
  train_repository,
  "/leave_one_out_cv_and_finetuning_done/leave_one_out_cv_and_finetuning/eval/combined_results.csv"
) %>% 
  download.file(
    destfile = "data/leave_one_out_combined.csv", 
    quiet = T
  )

plan(multisession, workers = round(availableCores() / 2))

"data/leave_one_out_combined.csv" %>% 
  read_csv(show_col_types = F) %>%
  pull(model) %>%
  unique %>%
  str_split("/") %>%
  map_chr(~ .x[5]) %>% 
  future_map(function(name) {
    f <- paste0("data/", name, ".csv")
    if (file.exists(f)) return(invisible())
    f <- CFILE(f, "wb")
    r <- paste0(
      train_repository,
      "/leave_one_out_cv_and_finetuning_done/leave_one_out_cv_and_finetuning/eval/", 
      name,
      "/eval/combined_results.csv"
    )
    curlPerform(url = r, writedata = f@ref, noprogress = T)
    close(f)
    return(invisible())
  }, .progress = show_progress()) %>% 
  invisible()

plan(sequential)

# Leave-two-out
paste0(
  train_repository,
  "/leave_two_out_dataset_mapping_done/leave_two_out_dataset_mapping/eval/combined_results.csv"
) %>%
  download.file(
    destfile = "data/leave_two_out_combined.csv",
    quiet = T
  )

plan(multisession, workers = round(availableCores() / 2))

"data/leave_two_out_combined.csv" %>% 
  read_csv(show_col_types = F) %>%
  pull(model) %>%
  unique %>%
  str_split("/") %>%
  map_chr(~ .x[5]) %>% 
  future_map(function(name) {
    f <- paste0("data/", name, ".csv")
    if (file.exists(f)) return(invisible())
    f <- CFILE(f, "wb")
    r <- paste0(
      train_repository,
      "/leave_two_out_dataset_mapping_done/leave_two_out_dataset_mapping/eval/", 
      name,
      "/eval/combined_results.csv"
    )
    curlPerform(url = r, writedata = f@ref, noprogress = T)
    close(f)
    return(invisible())
  }, .progress = show_progress()) %>% 
  invisible()

plan(sequential)

# Precomputed recomputed statistics
precomputed_files <- c(
  "leave_two_out_combined_recomputed_clean.csv",
  "leave_two_out_combined_recomputed_clean.rds",
  "leave_two_out_combined_recomputed.csv",
  "leave_one_out_combined_recomputed.csv",
  "compare_backbone_sizes_combined_recomputed.csv"
)

list(
  str_c(fb_repository, "manuscript", "data", precomputed_files, sep = "/"),
  file.path("data", precomputed_files)
) %>% 
  pmap(function(src, dst, ...) {
    if (file.exists(dst)) return(invisible())
    f <- CFILE(dst, "wb")
    r <- src
    curlPerform(url = r, writedata = f@ref, noprogress = T)
    close(f)
    return(invisible())
  }, .progress = "progressr") %>% 
  invisible()

# Move or download ROI tiles and pyramid visualization

get_local_or_remote <- function(
    name, local_dst_dir, local_src_dir, remote_src_dir, 
    local_proc=identity, remote_proc=identity
  ) {
  dst <- file.path(local_dst_dir, name)
  if (file.exists(dst)) return("skip")
  # Manually created figure
  local <- file.path(local_src_dir, local_proc(name))
  if (file.exists(local) && file.copy(local, dst)) return("local")
  # Pregenerated remote figure
  f <- CFILE(dst, "wb")
  r <- str_c(remote_src_dir, remote_proc(name), sep="/")
  curlPerform(url = r, writedata = f@ref, noprogress = T)
  close(f)
  return("remote")
}

pyramid_files <- c(
  "full_prediction.png",
  "test_image.jpg",
  "tile_and_pred_1.00.png",
  "tile_and_pred_0.52.png",
  "tile_and_pred_0.26.png"
)

pyramid_dir <- file.path("figures", "pyramid")
if (!dir.exists(pyramid_dir)) dir.create(pyramid_dir, recursive=T)

pyramid_files %>% 
  map_chr(
    get_local_or_remote,
    local_dst_dir=pyramid_dir,
    local_src_dir=file.path("..", "pyramid_visualization"),
    remote_src_dir=str_c(fb_repository, "manuscript", "figures", "pyramid", sep="/"),
    .progress = if (show_progress()) "progressr" else F
  )

tile_files <- c(
  "ABR.jpg",
  "ALU.jpg",
  "AMA.jpg",
  "AMI.jpg",
  "AMT.jpg",
  "ATO.jpg",
  "ATX.jpg",
  "BDA.jpg",
  "BIS.jpg",
  "CAI.jpg",
  "CAO.jpg",
  "DIR.jpg",
  "DIS.jpg",
  "DPS.jpg",
  "GER.jpg",
  "MOI.jpg",
  "NBC.jpg",
  "PIN.jpg",
  "PME.jpg",
  "SIT.jpg",
  "SPI.jpg",
  "UPT.jpg",
  "USC.jpg"
)

tile_dir <- "tiles"
if (!dir.exists(tile_dir)) dir.create(tile_dir)

tile_files %>% 
  map_chr(
    get_local_or_remote,
    local_dst_dir = tile_dir,
    local_src_dir = file.path("..", "figure_tiles", "raw_tiles"),
    remote_src_dir = str_c(fb_repository, "manuscript", "tiles", sep="/"),
    .progress = if (show_progress()) "progressr" else F
  ) 

example_bbox_figure <- "example_bbox_vs_contour.png"
get_local_or_remote(
  name = example_bbox_figure,
  local_dst_dir = "figures",
  local_src_dir = "..",
  remote_src_dir = str_c(fb_repository, "manuscript", "figures", sep="/")
)

mosaic_files <- c(
  "prediction_mosaic.jpg",
  "annotation_mosaic.jpg",
  "raw_mosaic.jpg"
)
mosaic_files %>% 
  map_chr(
    get_local_or_remote,
    local_dst_dir = "figures",
    local_src_dir = file.path("..", "figure_tiles", "mosaic"),
    remote_src_dir = str_c(fb_repository, "manuscript", "figures", sep="/"),
    local_proc = function(x) str_remove(x, "_mosaic")
  )

invisible()

