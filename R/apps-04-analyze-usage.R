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

# Purpose: Generate the "Snapshot" report for Business Owners

if (!exists("required_packages")) {
  source("R/00-setup.R")
}

# # Load the data we fetched in apps-01-fetch-ga-history.R
# load(file.path(DATA_RAW, "ga_raw_data.RData"))

# load rds files if you want to work with individual tables:
daily_usage_raw <- readRDS(file.path(DATA_RAW, "daily_usage_raw.rds"))
weekly_usage_raw <- readRDS(file.path(DATA_RAW, "weekly_usage_raw.rds"))
geo_data_raw <- readRDS(file.path(DATA_RAW, "geo_data_raw.rds"))
tech_data_raw <- readRDS(file.path(DATA_RAW, "tech_data_raw.rds"))
download_data_raw <- readRDS(file.path(DATA_RAW, "download_data_raw.rds"))

# Only 11 apps are kept since other apps are archived or private
apps_keep <- c(
  "LAEP",
  "Student Outcomes",
  "popApp",
  "BC Small Business",
  "LFS app",
  "Economic-Indicators",
  "BCDS-DIP Linkage Rates",
  "Household Projections",
  "Country Trade Profiles",
  "Interprovincial Migration",
  "BC Retail Sales"
)

# Filter raw data to only include these apps, add column details
daily_usage_raw <- daily_usage_raw |>
  filter(pageTitle %in% apps_keep)
# column definitions:
# - date: Reporting date (YYYY-MM-DD). Each row is one app on one day.
# - pageTitle: App name
# - totalUsers: Unique users for that app on that date (device/cookie-based).
#              Caution: do NOT sum across days to get weekly/monthly unique users.
#              Summing across days yields “total daily uniques,” which can double-count.
# - activeUsers: Unique users with an engaged session on that date. Engaged sessions last >10s,
#                have 2+ pageviews, or trigger key events. This is the primary KPI for reporting.
# - sessions: Number of sessions (visits) for that app on that date.
#             A session ends after ~30 minutes of inactivity; returning later counts again.
# - engagedSessions: Number of sessions that were "engaged" (lasted >10s, had 2+ pageviews, or triggered key events).
# - engagementRate: Percentage of sessions that were engaged (engagedSessions / sessions).
# - averageSessionDuration: Mean session length in seconds.
#                           GA4 can include background time; may overstate active use.
# - userEngagementDuration: Total engaged time in seconds for that app on that date.
#                           This is a SUM, not an average. It counts foreground time.
#                           To estimate average engaged time per user:
#                           avg_engaged_seconds = userEngagementDuration / Users

geo_data_raw <- geo_data_raw |>
  filter(pageTitle %in% apps_keep)

tech_data_raw <- tech_data_raw |>
  filter(pageTitle %in% apps_keep)

download_data_raw <- download_data_raw |>
  filter(pageTitle %in% apps_keep)

# Rolling average windows (adjust as needed)
rolling_week_window <- 4
rolling_month_window <- 3

weekly_usage_raw <- weekly_usage_raw |>
  filter(pageTitle %in% apps_keep)

# Summarize weekly data
weekly_usage <- weekly_usage_raw |>
  summarize(
    total_weekly_active_users = sum(activeUsers, na.rm = TRUE), # Used sum instead of max here because pagePath dimension can cause users to be split across rows; summing gives total unique users for the week
    total_sessions = sum(sessions, na.rm = TRUE),
    total_engaged_sessions = sum(engagedSessions, na.rm = TRUE),
    total_engaged_seconds = sum(userEngagementDuration, na.rm = TRUE),
    .by = c(pageTitle, isoYearIsoWeek)
  ) |>
  mutate(
    avg_engaged_seconds_per_user = total_engaged_seconds /
      pmax(total_weekly_active_users, 1)
  ) |>
  select(-total_engaged_seconds) |>
  complete(
    pageTitle = apps_keep,
    isoYearIsoWeek,
    fill = list(
      total_weekly_active_users = 0,
      total_sessions = 0,
      total_engaged_sessions = 0,
      avg_engaged_seconds_per_user = 0
    )
  ) |>
  arrange(pageTitle, isoYearIsoWeek) |>
  # Add rolling averages
  group_by(pageTitle) |>
  mutate(
    rolling_users_week = slide_dbl(
      total_weekly_active_users,
      mean,
      .before = rolling_week_window - 1,
      .complete = TRUE
    ),
    rolling_sessions_week = slide_dbl(
      total_sessions,
      mean,
      .before = rolling_week_window - 1,
      .complete = TRUE
    ),
    rolling_engaged_sessions_week = slide_dbl(
      total_engaged_sessions,
      mean,
      .before = rolling_week_window - 1,
      .complete = TRUE
    )
  ) |>
  ungroup()

# Add week/month buckets for rollups; keep original daily granularity
daily_usage_clean <- daily_usage_raw |>
  mutate(
    date = as.Date(date),
    week = floor_date(date, unit = "week", week_start = 1),
    # Format directly to YYYY-MM string here:
    month = format(date, "%Y-%m")
  )

# MONTHLY ROLLUPS
# Monthly: totals for usage, weighted durations per app-month
monthly_usage <- daily_usage_clean |>
  summarize(
    total_daily_active_users = sum(activeUsers, na.rm = TRUE),
    total_sessions = sum(sessions, na.rm = TRUE),
    total_engaged_sessions = sum(engagedSessions, na.rm = TRUE),
    avg_session_duration = weighted.mean(
      averageSessionDuration,
      w = sessions,
      na.rm = TRUE
    ),

    # Avg engaged seconds per user (monthly)
    avg_engaged_seconds_per_user = sum(userEngagementDuration, na.rm = TRUE) /
      pmax(sum(activeUsers, na.rm = TRUE), 1),

    .by = c(pageTitle, month)
  ) |>
  complete(
    pageTitle = apps_keep,
    month,
    fill = list(
      total_daily_active_users = 0,
      total_sessions = 0,
      total_engaged_sessions = 0,
      avg_session_duration = 0,
      avg_engaged_seconds_per_user = 0
    )
  ) |>
  arrange(pageTitle, month) |>
  group_by(pageTitle) |>
  mutate(
    rolling_users_month = slide_dbl(
      total_daily_active_users,
      mean,
      .before = rolling_month_window - 1,
      .complete = TRUE
    ),
    rolling_sessions_month = slide_dbl(
      total_sessions,
      mean,
      .before = rolling_month_window - 1,
      .complete = TRUE
    ),
    rolling_engaged_sessions_month = slide_dbl(
      total_engaged_sessions,
      mean,
      .before = rolling_month_window - 1,
      .complete = TRUE
    )
  ) |>
  ungroup()

# SUMMARY TABLES (per app)
# Latest week/month stats + rolling averages in one row per app
latest_week <- max(weekly_usage$isoYearIsoWeek, na.rm = TRUE)

# Use last completed calendar month relative to today
# Calculate last completed month, then format it as a string to match the data
latest_month <- format(
  floor_date(Sys.Date(), unit = "month") %m-% months(1),
  "%Y-%m"
)

usage_summary <- weekly_usage |>
  filter(isoYearIsoWeek == latest_week) |>
  select(
    pageTitle,
    recent_week_users = total_weekly_active_users,
    recent_week_sessions = total_sessions,
    recent_week_engaged_sessions = total_engaged_sessions,
    rolling_users_week,
    rolling_sessions_week,
    rolling_engaged_sessions_week,
    avg_engaged_seconds_per_user
  ) |>
  left_join(
    monthly_usage |>
      filter(month == latest_month) |>
      select(
        pageTitle,
        recent_month_users = total_daily_active_users,
        recent_month_sessions = total_sessions,
        recent_month_engaged_sessions = total_engaged_sessions,
        rolling_users_month,
        rolling_sessions_month,
        rolling_engaged_sessions_month
      ),
    by = "pageTitle"
  )

# Top 10 locations per app by total users
location_summary <- geo_data_raw |>
  summarize(
    total_active_users = sum(activeUsers, na.rm = TRUE),
    .by = c(pageTitle, country, region, city)
  ) |>
  arrange(pageTitle, desc(total_active_users)) |>
  group_by(pageTitle) |>
  slice_head(n = 10) |>
  ungroup()

# Tech profile per app (device/OS/browser)
tech_summary <- tech_data_raw |>
  summarize(
    total_active_users = sum(activeUsers, na.rm = TRUE),
    .by = c(pageTitle, deviceCategory, operatingSystem, browser)
  ) |>
  arrange(pageTitle, desc(total_active_users))

# Tech profile summaries (per app) with percentages
device_summary <- tech_data_raw |>
  summarize(
    total_active_users = sum(activeUsers, na.rm = TRUE),
    .by = c(pageTitle, deviceCategory)
  ) |>
  mutate(
    pct_users = total_active_users / sum(total_active_users),
    .by = pageTitle
  ) |>
  arrange(pageTitle, desc(total_active_users))

os_summary <- tech_data_raw |>
  summarize(
    total_active_users = sum(activeUsers, na.rm = TRUE),
    .by = c(pageTitle, operatingSystem)
  ) |>
  mutate(
    pct_users = total_active_users / sum(total_active_users),
    .by = pageTitle
  ) |>
  arrange(pageTitle, desc(total_active_users))

browser_summary <- tech_data_raw |>
  summarize(
    total_active_users = sum(activeUsers, na.rm = TRUE),
    .by = c(pageTitle, browser)
  ) |>
  mutate(
    pct_users = total_active_users / sum(total_active_users),
    .by = pageTitle
  ) |>
  arrange(pageTitle, desc(total_active_users))


# Downloads per app and file
download_summary <- download_data_raw |>
  select(-fileName, -event_label) |>
  summarize(
    total_downloads = sum(eventCount, na.rm = TRUE),
    .by = c(pageTitle, file_label)
  ) |>
  arrange(desc(total_downloads))


# Compare apps: share of users and rank (based on recent week users)
usage_comparison <- usage_summary |>
  mutate(
    share_recent_week_users = recent_week_users /
      sum(recent_week_users, na.rm = TRUE),
    rank_recent_week_users = min_rank(desc(replace_na(recent_week_users, 0)))
  ) |>
  select(
    pageTitle,
    recent_week_users,
    share_recent_week_users,
    rank_recent_week_users
  ) |>
  arrange(rank_recent_week_users)

# Min/Max weekly visits, time, and downloads summary table
# Aggregate downloads to attach to the summary table
downloads_by_app <- download_summary |>
  summarize(
    total_downloads = sum(total_downloads, na.rm = TRUE),
    .by = pageTitle
  )

visits_minmax_summary <- weekly_usage |>
  summarize(
    # raw visits metrics
    min_weekly_visits = min(total_sessions[total_sessions > 0], na.rm = TRUE),
    median_weekly_visits = median(
      total_sessions[total_sessions > 0],
      na.rm = TRUE
    ),
    avg_weekly_visits = round(mean(total_sessions, na.rm = TRUE), 1),
    max_weekly_visits = max(total_sessions, na.rm = TRUE),

    # engaged visits metrics
    min_weekly_visits_engaged = min(
      total_engaged_sessions[total_engaged_sessions > 0],
      na.rm = TRUE
    ),
    median_weekly_visits_engaged = median(
      total_engaged_sessions[total_engaged_sessions > 0],
      na.rm = TRUE
    ),
    avg_weekly_visits_engaged = round(
      mean(total_engaged_sessions, na.rm = TRUE),
      1
    ),
    max_weekly_visits_engaged = max(total_engaged_sessions, na.rm = TRUE),

    # Ignore 0s when determining minimum active time
    min_time_min = round(
      min(avg_engaged_seconds_per_user[total_sessions > 0], na.rm = TRUE) / 60,
      1
    ),
    avg_time_min = round(
      mean(avg_engaged_seconds_per_user[total_sessions > 0], na.rm = TRUE) / 60,
      1
    ),
    max_time_min = round(
      max(avg_engaged_seconds_per_user, na.rm = TRUE) / 60,
      1
    ),

    # Only count weeks where the app was actually used
    weeks_active = sum(total_sessions > 0, na.rm = TRUE),
    .by = pageTitle
  ) |>
  left_join(downloads_by_app, by = "pageTitle") |>
  mutate(
    total_downloads = replace_na(total_downloads, 0),
    avg_weekly_downloads = round(total_downloads / pmax(weeks_active, 1), 1),

    # Clean up Inf, NA, and NaN values if an app had zero active weeks
    min_weekly_visits = if_else(
      is.infinite(min_weekly_visits),
      0,
      min_weekly_visits
    ),
    min_weekly_visits_engaged = if_else(
      is.infinite(min_weekly_visits_engaged),
      0,
      min_weekly_visits_engaged
    ),
    min_time_min = if_else(is.infinite(min_time_min), 0, min_time_min),

    median_weekly_visits = replace_na(median_weekly_visits, 0),
    median_weekly_visits_engaged = replace_na(median_weekly_visits_engaged, 0),

    avg_time_min = if_else(is.nan(avg_time_min), 0, avg_time_min)
  ) |>
  select(-weeks_active, -total_downloads) |>
  arrange(desc(max_weekly_visits))


# OUTPUT LISTS
summary_tables <- list(
  usage_summary = usage_summary,
  location_summary = location_summary,
  tech_summary = tech_summary,
  download_summary = download_summary,
  usage_comparison = usage_comparison,
  weekly_usage = weekly_usage,
  visits_minmax_summary = visits_minmax_summary
)

tech_breakdowns <- list(
  device_summary = device_summary,
  os_summary = os_summary,
  browser_summary = browser_summary
)

# WRITE SUMMARY CSVs
# comment out the imap loops below to avoid overwriting CSVs during development

imap(summary_tables, \(x, name) {
  if (!is.null(x)) {
    write_csv(x, file = file.path(OUTPUT_TABLES, paste0(name, ".csv")))
  }
})

imap(tech_breakdowns, \(x, name) {
  write_csv(x, file = file.path(OUTPUT_TABLES, paste0(name, ".csv")))
})
