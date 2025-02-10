# File: yen_to_euro.R
# Install required packages if not already installed
if (!requireNamespace("httr", quietly = TRUE)) install.packages("httr")
if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite")
if (!requireNamespace("emayili", quietly = TRUE)) install.packages("emayili")
if (!requireNamespace("dotenv", quietly = TRUE)) install.packages("dotenv")

library(httr)
library(jsonlite)
library(emayili)

# Enhanced logging function
log_message <- function(message, type = "INFO") {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  log_entry <- sprintf("[%s] %s: %s\n", type, timestamp, message)
  write(log_entry, "exchange_rate_log.txt", append = TRUE)
}

# Validate environment variables
validate_env_vars <- function() {
  required_vars <- c(
    "EXCHANGE_API_KEY",
    "SMTP_SERVER",
    "SMTP_PORT",
    "SMTP_USER",
    "SMTP_PASSWORD",
    "RECIPIENT_EMAIL",
    "PRICE_THRESHOLD"
  )
  
  for (var in required_vars) {
    if (Sys.getenv(var) == "") {
      log_message(paste(var, "is missing"), "ERROR")
      stop(paste("Missing", var, "environment variable"))
    }
  }
  
  # Validate numeric values
  if (is.na(as.numeric(Sys.getenv("SMTP_PORT")))) {
    stop("SMTP_PORT must be a number")
  }
  if (is.na(as.numeric(Sys.getenv("PRICE_THRESHOLD")))) {
    stop("PRICE_THRESHOLD must be a number")
  }
}

# Function to get exchange rate with improved error handling
get_exchange_rate <- function(max_retries = 3) {
  api_key <- Sys.getenv("EXCHANGE_API_KEY")
  url <- paste0("https://v6.exchangerate-api.com/v6/", api_key, "/pair/JPY/EUR")
  
  for (attempt in 1:max_retries) {
    tryCatch({
      response <- GET(url, 
                      add_headers(
                        "Accept" = "application/json",
                        "User-Agent" = "R Exchange Rate Client"
                      )
      )
      
      # Check HTTP status
      if (status_code(response) == 200) {
        data <- fromJSON(rawToChar(response$content))
        
        # Validate response structure
        if (!is.null(data$conversion_rate)) {
          log_message(sprintf("Successfully retrieved rate: %f", data$conversion_rate))
          return(data$conversion_rate)
        } else {
          log_message("Unexpected API response format", "WARNING")
        }
      } else if (status_code(response) == 429) {
        # Rate limit handling
        log_message("Rate limit encountered. Waiting before retry.", "WARNING")
        Sys.sleep(5 * attempt)  # Exponential backoff
      } else {
        log_message(sprintf("API error with status code: %d", status_code(response)), "ERROR")
      }
    }, error = function(e) {
      log_message(paste("Connection error:", e$message), "ERROR")
    })
  }
  
  stop("Failed to retrieve exchange rate after maximum retries")
}

# Function to send email
send_notification <- function(rate, previous_rate = NULL) {
  # Get email credentials from environment variables
  smtp_server <- Sys.getenv("SMTP_SERVER")
  smtp_port <- as.numeric(Sys.getenv("SMTP_PORT"))
  smtp_user <- Sys.getenv("SMTP_USER")
  smtp_password <- Sys.getenv("SMTP_PASSWORD")
  recipient_email <- Sys.getenv("RECIPIENT_EMAIL")
  
  # Create email body
  body <- sprintf("Current JPY to EUR exchange rate: %f\n", rate)
  if (!is.null(previous_rate)) {
    change_percent <- ((rate - previous_rate) / previous_rate) * 100
    body <- paste0(body, sprintf("\nChange from previous: %.2f%%", change_percent))
  }
  
  # Create email
  email <- envelope(
    to = recipient_email,
    from = smtp_user,
    subject = "JPY/EUR Exchange Rate Alert"
  ) %>%
    text(body)
  
  # Configure SMTP server
  smtp <- server(
    host = smtp_server,
    port = smtp_port,
    username = smtp_user,
    password = smtp_password,
    protocol = "smtp+starttls"  # Important for Hotmail
  )
  
  # Send email
  smtp(email)
}

# Function to read previous rate from log
get_previous_rate <- function() {
  if (file.exists("exchange_rate_log.txt")) {
    lines <- readLines("exchange_rate_log.txt")
    if (length(lines) > 0) {
      last_line <- lines[length(lines)]
      # Extract rate from log entry format "YYYY-MM-DD HH:MM:SS: Rate = X.XXXXX"
      rate <- as.numeric(sub(".*Rate = ([0-9.]+).*", "\\1", last_line))
      return(rate)
    }
  }
  return(NULL)
}

# Main function
main <- function() {
  # Read the threshold from environment variable
  threshold <- as.numeric(Sys.getenv("PRICE_THRESHOLD"))
  
  # Get current rate
  current_rate <- get_exchange_rate()
  
  # Get previous rate from log
  previous_rate <- get_previous_rate()
  
  # Write to log file for tracking
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  log_entry <- sprintf("%s: Rate = %f\n", timestamp, current_rate)
  write(log_entry, "exchange_rate_log.txt", append = TRUE)
  
  # Check if rate is below threshold
  if (current_rate < threshold) {
    send_notification(current_rate, previous_rate)
  }
}

# Main execution
tryCatch({
  # Validate environment variables first
  validate_env_vars()
  
  # Run main function
  main()
}, error = function(e) {
  # Log any unhandled errors
  log_message(paste("Unhandled error:", e$message), "CRITICAL")
})