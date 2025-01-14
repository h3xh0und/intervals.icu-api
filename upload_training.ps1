<#
.SYNOPSIS
    Upload trainings from a JSON file to Intervals.icu

.DESCRIPTION
    This script reads a local "trainings.json" file, formats each training according 
    to the Intervals.icu API specifications, and uploads them via a bulk endpoint.

    Make sure to update:
      - $ATHLETE_ID
      - $API_KEY
      - $BASE_URL (if needed)
      - $zoneType (HR, Pace, or whichever you need)
#>

# --- Configuration ---
$ATHLETE_ID = "ID"                 # Replace with your Intervals.icu athlete ID
$API_KEY    = "API_KEY"            # Replace with your Intervals.icu API key
$BASE_URL   = "https://intervals.icu/api/v1/athlete"
$zoneType   = "HR"  # e.g. "HR" or "Pace"

# --- Functions ---

function Encode-Auth($apiKey) {
    # Creates a Base64-encoded string "API_KEY:{YourKey}" for the Authorization header
    $token = "API_KEY:$apiKey"
    return [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($token))
}

function Load-Trainings($filePath) {
    # Reads the JSON file and returns its contents as a PowerShell object
    if (-Not (Test-Path $filePath)) {
        throw "File '$filePath' not found."
    }
    Get-Content $filePath | ConvertFrom-Json
}

function Format-TrainingData($trainings) {
    # Converts each training entry into the JSON structure expected by Intervals.icu
    $formattedData = @()

    foreach ($training in $trainings.trainings) {
        # Build a detailed description from each step
        $descriptionLines = @()
        foreach ($step in $training.steps) {
            # Common lines for each step
            $descriptionLines += $step.description
            $descriptionLines += "- $($step.duration) in $($step.zone) $zoneType"
            $descriptionLines += "" # blank line for readability
        }

        # Calculate total moving_time (in seconds) by summing each step’s duration
        # If the step ends with "m" -> multiply numeric part by 60
        # If the step ends with "km"/"s" -> handle accordingly
        $movingTime = 0
        foreach ($step in $training.steps) {
            $cleanDuration = ($step.duration -replace "[^0-9]", "")  # numeric part only
            switch -Wildcard ($step.duration) {
                "*km" { $movingTime += [int]$cleanDuration * 60 * 6 }  # Example: 1 km might equate to 6 min, adjust as needed
                "*m"  { $movingTime += [int]$cleanDuration * 60 }
                "*s"  { $movingTime += [int]$cleanDuration }
                default { $movingTime += [int]$cleanDuration } # Fallback
            }
        }

        # Determine workout type
        $workoutType = if ($training.name -match "Bike") { "Ride" }
                       elseif ($training.name -match "Run")  { "Run" }
                       else                                  { "Swim" }

        # Build the object expected by Intervals.icu
        $event = [ordered]@{
            start_date_local = $training.date + "T00:00:00"
            category         = "WORKOUT"
            name             = $training.name
            description      = ($descriptionLines -join "`n").Trim()
            type             = $workoutType
            moving_time      = $movingTime
            steps            = @()
        }

        # Add each step to the steps array
        foreach ($step in $training.steps) {
            $stepObject = [ordered]@{
                description = $step.description
                duration    = $step.duration
                target_type = "zone"
                target_value= $step.zone
                cadence     = if ($null -ne $step.cadence) { $step.cadence } else { "Free" }
            }
            $event.steps += $stepObject
        }

        $formattedData += $event
    }

    return $formattedData
}

function Upload-Trainings($data) {
    # Sends a POST request to the Intervals.icu /events/bulk endpoint with the formatted data
    $url = "$BASE_URL/$ATHLETE_ID/events/bulk"
    $headers = @{
        Authorization = "Basic " + (Encode-Auth $API_KEY)
        "Content-Type" = "application/json"
    }

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body (ConvertTo-Json $data)
        if ($response) {
            Write-Host "Trainings uploaded successfully."
        }
    }
    catch {
        Write-Host "Failed to upload trainings: $($_.Exception.Message)"
    }
}

# --- Main Execution ---

try {
    # 1. Load training data from "trainings.json" (adjust if necessary)
    $trainings = Load-Trainings "trainings.json"

    # 2. Format the data according to Intervals.icu requirements
    $formattedData = Format-TrainingData $trainings

    # 3. Upload the data
    Upload-Trainings $formattedData
}
catch {
    Write-Host "Error: $($_.Exception.Message)"
}
