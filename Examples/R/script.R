# Requires the httr and jsonlite packages: install.packages(c("httr", "jsonlite"))
library(httr)
library(jsonlite)

base_url <- "https://ironbrew1.com"
api_key <- "IB1-APIKEYHERE"

input_path <- "input.lua"
output_path <- "output.lua"

options <- list(
  platform = "roblox",
  aggressiveOptimizations = "0",
  intenseVmScrambling = "false",
  enableVmCompression = "false"
)

retry_delay <- 5
max_wait <- 240
max_fails <- 3

fail <- function(message) {
  message(message)
  quit(status = 1)
}

queue_response <- POST(
  paste0(base_url, "/obfuscate"),
  query = options,
  add_headers(Key = api_key),
  content_type("text/plain"),
  body = readBin(input_path, "raw", file.info(input_path)$size)
)
if (http_error(queue_response)) fail(paste("Unable to queue obfuscation:", status_code(queue_response)))

queued <- fromJSON(content(queue_response, "text", encoding = "UTF-8"))
cat("Obfuscation started with GUID:", queued$uploadGuid, "\n")

elapsed <- 0
fails <- 0
wait <- 0

repeat {
  wait <- wait + retry_delay
  Sys.sleep(wait)
  elapsed <- elapsed + wait

  status_response <- GET(paste0(base_url, queued$statusUrl), add_headers(Key = api_key))
  if (http_error(status_response)) {
    fails <- fails + 1
    cat(sprintf("Status check failed with status: %d (%d/%d)\n", status_code(status_response), fails, max_fails))
    if (fails >= max_fails || elapsed >= max_wait) {
      fail(sprintf("Obfuscation failed (fails: %d | elapsed time: %d)", fails, elapsed))
    }
    next
  }

  status <- fromJSON(content(status_response, "text", encoding = "UTF-8"))

  if (status$status == "completed") {
    cat(sprintf("Obfuscation completed in %d seconds\n", elapsed))
    download <- GET(paste0(base_url, status$downloadUrl), add_headers(Key = api_key))
    if (http_error(download)) fail(paste("Download failed with status:", status_code(download)))
    writeBin(content(download, "raw"), output_path)
    cat("Saved obfuscated script to", output_path, "\n")
    break
  }

  if (status$status == "failed" || elapsed >= max_wait) {
    fail(sprintf("Obfuscation failed (status: %s | elapsed time: %d)", status$status, elapsed))
  }

  cat(sprintf("Obfuscation is still in progress. Elapsed time: %d seconds. Checking again in %d seconds.\n",
              elapsed, retry_delay + wait))
}
