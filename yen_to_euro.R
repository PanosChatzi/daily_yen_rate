# Install required packages if not already installed
if (!requireNamespace("httr", quietly = TRUE)) install.packages("httr")
if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite")
if (!requireNamespace("emayili", quietly = TRUE)) install.packages("emayili")

library(httr)
library(jsonlite)
library(emayili)

# Function to get exchange rate with fallback APIs
get_exchange_rate <- function() {
  # List of APIs to try
  apis <- list(
    list(
      url = "https://api.exchangerate-api.com/v4/latest/JPY",
      path = c("rates", "EUR")
    ),
    list(
      url = "https://api.exchangerate.host/latest?base=JPY&symbols=EUR",
      path = c("rates", "EUR")
    )
  )
  
  for (api in apis) {
    tryCatch({
      # Make the request
      response <- GET(api$url)
      
      # Check if request was successful
      if (status_code(response) == 200) {
        # Parse response
        data <- fromJSON(rawToChar(response$content))
        
        # Extract rate using the appropriate path
        rate <- data[[api$path[1]]][[api$path[2]]]
        
        if (!is.null(rate)) {
          return(rate)
        }
      }
    }, error = function(e) {
      warning(paste("Error with", api$url, ":", e$message))
    })
  }
  
  stop("Could not get exchange rate from any API endpoint")
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

# Run main function with error handling
tryCatch({
  main()
}, error = function(e) {
  message("Error in main function: ", e$message)
})