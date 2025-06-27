#!/bin/bash

# Array of FIO job YAML files
FIO_JOBS=(
    "fio-job-read-256.yaml"
    "fio-job-read-512.yaml"
    "fio-job-write-256.yaml"
    "fio-job-write-512.yaml"
)

OUTPUT_CSV="fio_metrics.csv"

echo "Starting FIO Kubernetes Job execution and metric collection..."
echo "---------------------------------------------------------"

# Initialize CSV file with headers
echo "JobName,OperationType,Slat_min_usec,Slat_max_usec,Slat_avg_usec,Clat_min_usec,Clat_max_usec,Clat_avg_usec,Lat_min_usec,Lat_max_usec,Lat_avg_usec,BW_min_KBps,BW_max_KBps,BW_avg_KBps" > "${OUTPUT_CSV}"
echo "Metrics will be saved to: ${OUTPUT_CSV}"

for job_file in "${FIO_JOBS[@]}"; do
    job_name=$(basename "${job_file}" .yaml) # Extract job name from filename

    echo "Processing job: ${job_name} from ${job_file}"

    # 1. Apply the Kubernetes Job
    echo "Applying ${job_file}..."
    kubectl apply -f "${job_file}"

    # Check if apply was successful
    if [ $? -ne 0 ]; then
        echo "Error applying ${job_file}. Skipping to next job."
        continue
    fi

    # 2. Wait for the Job to complete
    echo "Waiting for job ${job_name} to complete..."
    if ! kubectl wait --for=condition=complete job/${job_name} --timeout=5m; then
        echo "Job ${job_name} did not complete within the timeout or failed. Checking for pod errors..."
        pod_name=$(kubectl get pods -l job-name="${job_name}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$pod_name" ]; then
            echo "Logs for failed job ${job_name} (pod: ${pod_name}):"
            kubectl logs "${pod_name}"
        fi
        echo "Skipping to next job."
        kubectl delete job "${job_name}" --ignore-not-found # Clean up failed job if it exists
        continue
    fi
    echo "Job ${job_name} completed."

    # 3. Get the Pod name for the completed Job
    pod_name=$(kubectl get pods -l job-name="${job_name}" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod_name" ]; then
        echo "Could not find pod for job ${job_name}. Skipping log retrieval."
        kubectl delete job "${job_name}" --ignore-not-found
        continue
    fi

    echo "Retrieving logs from pod: ${pod_name}"
    logs=$(kubectl logs "${pod_name}" 2>&1) # Redirect stderr to stdout for potential errors

    # Define a function to extract and print metrics for a given operation type (read/write)
    extract_metrics_and_save_to_csv() {
        local current_job_name=$1
        local operation=$2 # "read" or "write"
        local log_content=$3

        # Use sed to safely extract values, defaulting to N/A if not found
        local slat_min=$(echo "${log_content}" | grep -A 5 "${operation}:" | grep "slat (usec):" | sed -n 's/.*min=\([0-9.]*\).*/\1/p' | head -n 1)
        local slat_max=$(echo "${log_content}" | grep -A 5 "${operation}:" | grep "slat (usec):" | sed -n 's/.*max=\([0-9.]*\).*/\1/p' | head -n 1)
        local slat_avg=$(echo "${log_content}" | grep -A 5 "${operation}:" | grep "slat (usec):" | sed -n 's/.*avg=\([0-9.]*\).*/\1/p' | head -n 1)

        local clat_min=$(echo "${log_content}" | grep -A 5 "${operation}:" | grep "clat (usec):" | sed -n 's/.*min=\([0-9.]*\).*/\1/p' | head -n 1)
        local clat_max=$(echo "${log_content}" | grep -A 5 "${operation}:" | grep "clat (usec):" | sed -n 's/.*max=\([0-9.]*\).*/\1/p' | head -n 1)
        local clat_avg=$(echo "${log_content}" | grep -A 5 "${operation}:" | grep "clat (usec):" | sed -n 's/.*avg=\([0-9.]*\).*/\1/p' | head -n 1)

        local lat_min=$(echo "${log_content}" | grep -A 5 "${operation}:" | grep "lat (usec):" | sed -n 's/.*min=\([0-9.]*\).*/\1/p' | head -n 1)
        local lat_max=$(echo "${log_content}" | grep -A 5 "${operation}:" | grep "lat (usec):" | sed -n 's/.*max=\([0-9.]*\).*/\1/p' | head -n 1)
        local lat_avg=$(echo "${log_content}" | grep -A 5 "${operation}:" | grep "lat (usec):" | sed -n 's/.*avg=\([0-9.]*\).*/\1/p' | head -n 1)

        # For BW, grep the 'bw (KB /s):' line for minb, maxb, avg
        local bw_detail_line=$(echo "${log_content}" | grep -A 5 "${operation}:" | grep "bw (KB /s):" | head -n 1)
        local bw_min=$(echo "$bw_detail_line" | sed -n 's/.*minb=\([0-9.]*\).*/\1/p')
        local bw_max=$(echo "$bw_detail_line" | sed -n 's/.*maxb=\([0-9.]*\).*/\1/p')
        local bw_avg=$(echo "$bw_detail_line" | sed -n 's/.*avg=\([0-9.]*\).*/\1/p')

        # Check if any metrics were found for this operation before writing to CSV
        if [ -n "$slat_min" ] || [ -n "$clat_min" ] || [ -n "$lat_min" ] || [ -n "$bw_min" ]; then
            # Replace empty variables with N/A for CSV consistency
            slat_min="${slat_min:-N/A}"
            slat_max="${slat_max:-N/A}"
            slat_avg="${slat_avg:-N/A}"
            clat_min="${clat_min:-N/A}"
            clat_max="${clat_max:-N/A}"
            clat_avg="${clat_avg:-N/A}"
            lat_min="${lat_min:-N/A}"
            lat_max="${lat_max:-N/A}"
            lat_avg="${lat_avg:-N/A}"
            bw_min="${bw_min:-N/A}"
            bw_max="${bw_max:-N/A}"
            bw_avg="${bw_avg:-N/A}"

            echo "${current_job_name},${operation},${slat_min},${slat_max},${slat_avg},${clat_min},${clat_max},${clat_avg},${lat_min},${lat_max},${lat_avg},${bw_min},${bw_max},${bw_avg}" >> "${OUTPUT_CSV}"
            echo "  ${operation^} metrics saved to CSV."
        fi
    }

    # Extract and save metrics for write operations
    extract_metrics_and_save_to_csv "${job_name}" "write" "$logs"
    # Extract and save metrics for read operations
    extract_metrics_and_save_to_csv "${job_name}" "read" "$logs"

    echo -e "---------------------------------------------------------\n"

    # 4. Clean up: Delete the Job and its associated Pods
    echo "Deleting job ${job_name}..."
    kubectl delete job "${job_name}"
    if [ $? -ne 0 ]; then
        echo "Error deleting job ${job_name}. Manual cleanup may be required."
    fi
done

echo "All FIO jobs processed. Results saved to ${OUTPUT_CSV}"