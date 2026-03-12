make clean && make
timestamp=$(date "+%Y-%m-%d %H:%M:%S")

./cudaBandwidthTest > "./result_${timestamp}.log" 2>&1