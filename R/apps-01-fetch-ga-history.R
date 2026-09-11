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

# Purpose: Download raw data from GA4 and save it locally (caching)

source("R/00-setup.R")


# Get daily usage data (for timeline & rolling averages)
daily_usage_raw <- ga_data(
  propertyId = GA_PROPERTY_ID,
  date_range = c(GA_DATE_START, GA_DATE_END),
  metrics = c(
    "totalUsers", # The number of distinct users who have logged at least one event, regardless of whether the site or app was in use when that event was logged.
    "activeUsers", # The number of distinct users who visited your site or app.
    "sessions", # The number of sessions that began on your site or app (event triggered: session_start).
    "engagedSessions", # The number of sessions that lasted longer than 10 seconds, or had a key event, or had 2 or more screen views.
    "engagementRate", # The percentage of engaged sessions (engagedSessions/sessions).
    "averageSessionDuration", # The average duration (in seconds) of users` sessions.
    "userEngagementDuration" # The total amount of time (in seconds) your website or app was in the foreground of users` devices.
  ),
  dimensions = c("date", "pageTitle", "pagePath"), # Page title:The web page titles used on your site. Page path: The portion of the URL between the hostname and query string for web pages visited.
  limit = -1
)
# --- USER METRICS ---
# totalUsers  : The "Raw Headcount". Counts any device that triggered ANY event,
#               including background pings or immediate bounces.
# activeUsers : The "Engaged Headcount". The primary KPI for reporting. Counts
#               users who had an engaged session (lasted >10 seconds, viewed 2+
#               pages/screens, or triggered a key event).
# Note: totalUsers will always be >= activeUsers. The difference between the
# two represents background noise and "bounce" traffic.

# --- SESSION METRICS ---
# sessions       : The "Raw Visits". Counts every single time a user opens the app,
#                  including accidental clicks where they close the tab immediately.
# engagedSessions: The "Quality Visits". Counts only the sessions that actually
#                  demonstrated intent (lasted >10s, viewed 2+ pages/screens, or
#                  triggered a key event).
# engagementRate : The percentage of sessions that were engaged
#                  (engagedSessions / sessions).
# Note: sessions will always be >= engagedSessions. The difference between the
# two represents the "bounce rate" (visits that yielded no meaningful interaction).

# Determine the end date for the last fully completed ISO week (Monday to Sunday)
# %u returns 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun
# Subtracting this from GA_DATE_END will always roll back to the most recent Sunday
day_of_week_iso <- as.integer(format(as.Date(GA_DATE_END), "%u"))
end_date_weekly <- as.character(as.Date(GA_DATE_END) - day_of_week_iso)

# Get weekly usage data (for accurate weekly unique users)
weekly_usage_raw <- ga_data(
  propertyId = GA_PROPERTY_ID,
  # USE end_date_weekly HERE INSTEAD OF GA_DATE_END
  date_range = c(GA_DATE_START, end_date_weekly),
  metrics = c(
    "totalUsers",
    "activeUsers",
    "sessions",
    "engagedSessions",
    "engagementRate",
    "averageSessionDuration",
    "userEngagementDuration"
  ),
  dimensions = c("isoYearIsoWeek", "pageTitle", "pagePath"), # ISO week of ISO year: The combined values of isoWeek and isoYear. where each week starts on Monday and ends on Sunday.
  limit = -1
)

# geo
geo_data_raw <- ga_data(
  propertyId = GA_PROPERTY_ID,
  date_range = c(GA_DATE_START, GA_DATE_END),
  metrics = c("totalUsers", "activeUsers"),
  dimensions = c("date", "pageTitle", "pagePath", "country", "city", "region"),
  limit = -1
)

# tech
tech_data_raw <- ga_data(
  propertyId = GA_PROPERTY_ID,
  date_range = c(GA_DATE_START, GA_DATE_END),
  metrics = c("totalUsers", "activeUsers"),
  dimensions = c(
    "date",
    "pageTitle",
    "pagePath",
    "deviceCategory",
    "operatingSystem",
    "browser",
    "screenResolution"
  ),
  limit = -1
)

# get downloads (file downloads)
download_data_raw <- ga_data(
  propertyId = GA_PROPERTY_ID,
  date_range = c(GA_DATE_START, GA_DATE_END),
  metrics = c("eventCount"),
  dimensions = c(
    "date",
    "pageTitle",
    "pagePath",
    "eventName",
    "fileName",
    "customEvent:event_label"
  ),
  dim_filters = ga_data_filter(eventName == "file_download"),
  limit = -1
) |>
  rename(event_label = `customEvent:event_label`) |>
  mutate(
    file_label = coalesce(na_if(fileName, ""), na_if(event_label, ""))
  )


# # Save raw data to an RData file so we don't have to hit the API repeatedly while coding
# save(
#   daily_usage_raw,
#   weekly_usage_raw,
#   geo_data_raw,
#   tech_data_raw,
#   download_data_raw,
#   file = file.path(DATA_RAW, "ga_raw_data.RData")
# )

# Also save each table as .rds for simpler reuse
saveRDS(daily_usage_raw, file = file.path(DATA_RAW, "daily_usage_raw.rds"))
saveRDS(weekly_usage_raw, file = file.path(DATA_RAW, "weekly_usage_raw.rds"))
saveRDS(geo_data_raw, file = file.path(DATA_RAW, "geo_data_raw.rds"))
saveRDS(tech_data_raw, file = file.path(DATA_RAW, "tech_data_raw.rds"))
saveRDS(download_data_raw, file = file.path(DATA_RAW, "download_data_raw.rds"))

message("Data fetched and saved to 'data/*.rds' files.")
