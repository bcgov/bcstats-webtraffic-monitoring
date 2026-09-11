# Copyright 2026 Province of British Columbia
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Purpose: Extract BC Data Catalogue (BCDC) traffic metrics from CMS Lite data.
# Outputs:
# - bcdc_top_50_clicks.csv (URL-level ranking)
# - bcdc_priority_datasets.csv (dataset-level ranking)
# - bcdc_asset_downloads.csv (BCDC URLs in asset downloads)
# - km_priority_urls_combined.csv (KM URL-level combined ranking)
# - km_priority_bcdc_datasets.csv (KM dataset-level ranking)
# - bcdc_final_comparison_all.csv (CMS + KM combined dataset ranking)
# - bcdc_top_5_final_priority.csv (final top 5 datasets)

source("R/00-setup.R")

library(dplyr)
library(readr)
library(stringr)

source("R/functions/gdx-web-analysis-functions.R")

if (!exists("govstats_click")) {
  stop(
    "govstats_click not found in environment. Run R/gdx-02-analyze.R first.",
    call. = FALSE
  )
}

# 1) URL-level: top 50 clicked BCDC target URLs
bcdc_top_50_clicks <- analyze_bcdc_click(govstats_click, top_n = 50)
write_csv(
  bcdc_top_50_clicks,
  file.path(OUTPUT_TABLES, "bcdc_top_50_clicks.csv")
)

# 2) Dataset-level: top 50 BCDC datasets by aggregated clicks
# Difference vs URL-level output:
# - URL-level table keeps each distinct target_url.
# - Dataset-level table aggregates all URLs mapped to dataset_uuid.
bcdc_priority_datasets <- govstats_click |>
  filter(
    str_detect(
      target_url,
      regex("catalogue\\.data\\.gov\\.bc\\.ca", ignore_case = TRUE)
    )
  ) |>
  mutate(
    dataset_uuid = str_match(
      target_url,
      "catalogue\\.data\\.gov\\.bc\\.ca/dataset/([^/?#]+)"
    )[, 2]
  ) |>
  filter(!is.na(dataset_uuid)) |>
  summarise(
    total_clicks = sum(clicks, na.rm = TRUE),
    example_url = first(target_url),
    .by = dataset_uuid
  ) |>
  arrange(desc(total_clicks)) |>
  slice(1:50) |>
  mutate(
    priority_rank = row_number(),
    dataset_url = paste0(
      "https://catalogue.data.gov.bc.ca/dataset/",
      dataset_uuid
    ),
    .before = dataset_uuid
  ) |>
  select(priority_rank, dataset_uuid, dataset_url, total_clicks, example_url)

write_csv(
  bcdc_priority_datasets,
  file.path(OUTPUT_TABLES, "bcdc_priority_datasets.csv")
)


# 3) KM-provided CSV section (data_KM)
km_dir_candidates <- c(file.path(PROJECT_ROOT, "data_KM"), "data_KM")
km_dir <- km_dir_candidates[file.exists(km_dir_candidates)][1]

if (is.na(km_dir)) {
  stop("data_KM folder not found.", call. = FALSE)
}

km_paths <- c(
  asset = file.path(km_dir, "Top Asset Downloads.csv"),
  downloaded = file.path(km_dir, "Top Downloaded Clicks (1).csv"),
  offsite = file.path(km_dir, "Top Offsite Link Clicks.csv")
)

if (!all(file.exists(km_paths))) {
  stop("One or more KM CSV files are missing in data_KM.", call. = FALSE)
}

km_asset <- read_csv(km_paths[["asset"]], show_col_types = FALSE) |>
  rename(
    rank = ...1,
    file_name = `File Name`,
    url = `Asset URL`,
    count = `Download Count`,
    share = `% of Downloads`
  ) |>
  mutate(source = "asset_downloads") |>
  filter(!is.na(rank), !is.na(url), !is.na(count))

km_downloaded <- read_csv(km_paths[["downloaded"]], show_col_types = FALSE) |>
  rename(
    rank = ...1,
    url = `Downloaded File`,
    count = `Download Click Count`,
    share = `% of Downloads`
  ) |>
  mutate(source = "download_clicks") |>
  filter(!is.na(rank), !is.na(url), !is.na(count))

km_offsite <- read_csv(km_paths[["offsite"]], show_col_types = FALSE) |>
  rename(
    rank = ...1,
    url = `Offsite Links`,
    count = `Offsite Click Count`,
    share = `% of Offsite Clicks`
  ) |>
  mutate(source = "offsite_clicks") |>
  filter(!is.na(rank), !is.na(url), !is.na(count))

km_unified <- bind_rows(
  km_asset |> select(source, rank, url, count),
  km_downloaded |> select(source, rank, url, count),
  km_offsite |> select(source, rank, url, count)
)

km_priority_urls <- km_unified |>
  summarise(
    total_count = sum(count, na.rm = TRUE),
    appears_in = n_distinct(source),
    .by = url
  ) |>
  arrange(desc(total_count))

km_priority_bcdc <- km_unified |>
  mutate(
    dataset_uuid = str_match(
      url,
      "catalogue\\.data\\.gov\\.bc\\.ca/dataset/([^/?#]+)"
    )[, 2]
  ) |>
  filter(!is.na(dataset_uuid)) |>
  summarise(
    total_count = sum(count, na.rm = TRUE),
    contributing_sources = paste(sort(unique(source)), collapse = ", "),
    .by = dataset_uuid
  ) |>
  arrange(desc(total_count)) |>
  mutate(
    dataset_url = paste0(
      "https://catalogue.data.gov.bc.ca/dataset/",
      dataset_uuid
    ),
    .before = total_count
  )

write_csv(
  km_priority_urls,
  file.path(OUTPUT_TABLES, "km_priority_urls_combined.csv")
)

write_csv(
  km_priority_bcdc,
  file.path(OUTPUT_TABLES, "km_priority_bcdc_datasets.csv")
)

# 4) Final comparison and top 5 priority datasets (CMS + KM)
bcdc_cms_final <- read_csv(
  file.path(OUTPUT_TABLES, "bcdc_priority_datasets.csv"),
  show_col_types = FALSE
) |>
  rename(cms_clicks = total_clicks, cms_rank = priority_rank) |>
  select(cms_rank, dataset_uuid, dataset_url, cms_clicks)

km_bcdc_final <- read_csv(
  file.path(OUTPUT_TABLES, "km_priority_bcdc_datasets.csv"),
  show_col_types = FALSE
) |>
  rename(km_clicks = total_count, km_sources = contributing_sources) |>
  select(dataset_uuid, km_clicks, km_sources)

bcdc_final_comparison <- bcdc_cms_final |>
  full_join(km_bcdc_final, by = "dataset_uuid") |>
  mutate(
    cms_clicks = coalesce(cms_clicks, 0),
    km_clicks = coalesce(km_clicks, 0),
    combined_clicks = cms_clicks + km_clicks,
    appears_in_both = !is.na(cms_rank) & !is.na(km_sources)
  ) |>
  arrange(desc(combined_clicks)) |>
  mutate(final_rank = row_number()) |>
  select(
    final_rank,
    dataset_uuid,
    dataset_url,
    cms_clicks,
    km_clicks,
    combined_clicks,
    km_sources,
    appears_in_both
  )

bcdc_top_5_final <- bcdc_final_comparison |>
  slice(1:5)

write_csv(
  bcdc_final_comparison,
  file.path(OUTPUT_TABLES, "bcdc_final_comparison_all.csv")
)

write_csv(
  bcdc_top_5_final,
  file.path(OUTPUT_TABLES, "bcdc_top_5_final_priority.csv")
)
