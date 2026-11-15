#!/bin/bash
# Generate traffic + errors so CloudWatch graphs/alarms have data to show.
#   ./load-test.sh <public-ip> [requests]
IP=${1:?usage: $0 <public-ip> [requests]}; N=${2:-300}
echo "Sending $N requests to http://$IP ..."
for i in $(seq 1 $N); do
  curl -s -o /dev/null "http://$IP/" &
  curl -s -o /dev/null "http://$IP/api/products" &
  (( i % 20 == 0 )) && curl -s -o /dev/null "http://$IP/does-not-exist-$i"   # creates ERROR log lines
  (( i % 50 == 0 )) && { wait; echo "  $i done"; }
done
wait
curl -s "http://$IP/metrics"; echo
echo "Now check CloudWatch > Log groups > /medicart/app and the MediCart-Dashboard."
