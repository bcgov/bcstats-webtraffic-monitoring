# Shared helpers for monthly GDX web dashboard runs

library(stringr)
library(glue)

resolve_target_month <- function(
  month = NULL,
  mode = c("previous", "explicit")
) {
  mode <- match.arg(mode)

  env_month <- Sys.getenv("GDX_TARGET_MONTH", unset = "")
  env_month <- if (nzchar(env_month)) env_month else NULL

  target <- month %||% env_month

  if (is.null(target)) {
    if (mode == "explicit") {
      stop("Target month is required in explicit mode.", call. = FALSE)
    }
    # Default: previous calendar month from current system date.
    target <- format(
      seq.Date(
        as.Date(format(Sys.Date(), "%Y-%m-01")),
        by = "-1 month",
        length.out = 2
      )[2],
      "%Y-%m"
    )
  }

  if (!str_detect(target, "^\\d{4}-\\d{2}$")) {
    stop(
      glue("Invalid target month '{target}'. Expected format YYYY-MM."),
      call. = FALSE
    )
  }

  target
}

# Map a reporting month to its S3 selection rule.
#
# Returns a list with:
#   subfolder   - top-level drop folder, or "" when not applicable
#   key_pattern - regex applied to the key relative to the S3 prefix, or ""
#   rule        - short human-readable label for logging
#
# Historical months used one-off delivery structures and are pinned explicitly.
# From 2026-09 onward the provider runs an automated job on the 4th of the
# following month, writing to {report_name}/v01_auto/. See
# docs/BC_STATS_S3_FILE_GUIDE.md for the authoritative mapping.
resolve_s3_selection <- function(target_month) {
  if (!str_detect(target_month, "^\\d{4}-\\d{2}$")) {
    stop(
      glue("Invalid target month '{target_month}'. Expected format YYYY-MM."),
      call. = FALSE
    )
  }

  historical <- list(
    "2026-05" = list(
      subfolder = "UAT_20260708",
      key_pattern = "",
      rule = "May 2026 revised UAT drop folder"
    ),
    "2026-06" = list(
      subfolder = "",
      key_pattern = "/v00_manual/.*_20260729T\\d{6}_part\\d{3}\\.csv$",
      rule = "June 2026 manual run generated 2026-07-29"
    ),
    "2026-07" = list(
      subfolder = "",
      key_pattern = "/v00_manual/.*_20260910T22\\d{4}_part\\d{3}\\.csv$",
      rule = "July 2026 manual backfill generated 2026-09-10"
    ),
    "2026-08" = list(
      subfolder = "",
      key_pattern = "/v01_auto/.*_20260910T0[12]\\d{4}_part\\d{3}\\.csv$",
      rule = "August 2026 automated test run generated 2026-09-10"
    )
  )

  if (target_month %in% names(historical)) {
    return(historical[[target_month]])
  }

  if (target_month < "2026-09") {
    stop(
      glue(
        "No S3 selection rule defined for month {target_month}. ",
        "Set BCSTATS_S3_SOURCE_SUBFOLDER or BCSTATS_S3_KEY_PATTERN explicitly."
      ),
      call. = FALSE
    )
  }

  # Regular schedule: files are generated in the month AFTER the reporting month.
  gen_month <- format(
    seq.Date(
      as.Date(paste0(target_month, "-01")),
      by = "1 month",
      length.out = 2
    )[2],
    "%Y%m"
  )

  list(
    subfolder = "",
    key_pattern = glue(
      "/v01_auto/.*_{gen_month}\\d{{2}}T\\d{{6}}_part\\d{{3}}\\.csv$"
    ) |>
      as.character(),
    rule = glue(
      "scheduled v01_auto run generated in {gen_month} for reporting month {target_month}"
    ) |>
      as.character()
  )
}

assert_cmslite_reports_present <- function(raw_dir) {
  all_csv <- list.files(
    raw_dir,
    pattern = "\\.csv$",
    recursive = TRUE,
    full.names = TRUE
  )
  files <- basename(all_csv)

  expected <- list(
    outcomes = c("pageview", "click", "referurl", "platform", "geoloc"),
    antiracism = c("pageview", "click", "referurl", "platform", "geoloc"),
    govstats = c(
      "pageview",
      "click",
      "referurl",
      "platform",
      "geoloc",
      "asset",
      "search",
      "google"
    )
  )

  missing <- c()

  for (site in names(expected)) {
    for (report in expected[[site]]) {
      pat <- paste0("webdata_bcstats_", site, "_", report, "_monthly")
      if (!any(str_detect(files, fixed(pat)))) {
        missing <- c(missing, paste0(site, ":", report))
      }
    }
  }

  if (length(missing) > 0) {
    stop(
      glue(
        "Missing expected report files in {raw_dir}: {paste(missing, collapse = ', ')}"
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

assert_monthly_outputs <- function(output_dir) {
  required_core <- c(
    "cmslite_daily",
    "cmslite_clicks_daily",
    "cmslite_top_referrers",
    "cmslite_by_os",
    "cmslite_by_geo",
    "cmslite_top_pages"
  )

  required_govstats <- c(
    "cmslite_asset_downloads_daily",
    "cmslite_search_terms",
    "cmslite_google_queries"
  )

  check_one <- function(name, required = TRUE) {
    f <- list.files(
      output_dir,
      pattern = paste0("^", name, "_\\d{4}-\\d{2}\\.csv$"),
      full.names = TRUE
    )
    if (length(f) == 0) {
      if (required) {
        stop(
          glue("Missing required output table: {name} in {output_dir}"),
          call. = FALSE
        )
      } else {
        warning(
          glue("Optional govstats table not found: {name} in {output_dir}"),
          call. = FALSE
        )
        return(invisible(FALSE))
      }
    }

    x <- readr::read_csv(f[1], show_col_types = FALSE)
    if (nrow(x) == 0) {
      if (required) {
        stop(
          glue("Required output table is empty: {basename(f[1])}"),
          call. = FALSE
        )
      } else {
        warning(
          glue("Optional govstats table is empty: {basename(f[1])}"),
          call. = FALSE
        )
      }
    }

    invisible(TRUE)
  }

  purrr::walk(required_core, check_one, required = TRUE)
  purrr::walk(required_govstats, check_one, required = FALSE)

  invisible(TRUE)
}

assert_data_month <- function(df, target_month, label, date_col = "date") {
  if (!date_col %in% names(df)) {
    warning(
      glue(
        "{label}: date column '{date_col}' not found; skipping month check."
      ),
      call. = FALSE
    )
    return(invisible(TRUE))
  }

  raw <- as.character(df[[date_col]])
  raw <- raw[!is.na(raw) & nzchar(raw)]

  # Reports come at two granularities: full dates (page views, clicks, assets)
  # and bare YYYY-MM month strings (site search, Google search). The latter are
  # not parseable by as.Date(), so read the month directly.
  is_month_only <- length(raw) > 0 && all(str_detect(raw, "^\\d{4}-\\d{2}$"))

  months_present <- if (is_month_only) {
    sort(unique(raw))
  } else {
    dates <- suppressWarnings(lubridate::ymd(raw))
    dates <- dates[!is.na(dates)]
    if (length(dates) == 0) {
      warning(
        glue("{label}: no parseable dates found; skipping month check."),
        call. = FALSE
      )
      return(invisible(TRUE))
    }
    sort(unique(format(dates, "%Y-%m")))
  }

  if (length(months_present) == 0) {
    warning(
      glue("{label}: no parseable dates found; skipping month check."),
      call. = FALSE
    )
    return(invisible(TRUE))
  }
  bad <- months_present[months_present != target_month]
  if (length(bad) > 0) {
    stop(
      glue(
        "{label}: expected month {target_month}, found month(s): {paste(months_present, collapse = ', ')}"
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

# Resolve the column carrying the reporting period for a loaded report.
# Most reports normalize to `date`; the two search reports keep a month column
# whose name is prefixed by its source table.
find_period_col <- function(df) {
  if ("date" %in% names(df)) {
    return("date")
  }
  month_cols <- names(df)[str_detect(names(df), "month$")]
  if (length(month_cols) > 0) {
    return(month_cols[1])
  }
  NA_character_
}

# Check every loaded report in a named list against the target month.
assert_reports_month <- function(reports, target_month) {
  purrr::iwalk(reports, \(df, label) {
    col <- find_period_col(df)
    if (is.na(col)) {
      warning(
        glue(
          "{label}: no reporting-period column found; skipping month check."
        ),
        call. = FALSE
      )
      return(invisible(NULL))
    }
    assert_data_month(df, target_month, label, date_col = col)
  })
  invisible(TRUE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
