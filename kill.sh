kubectl delete sts --all 
kubectl delete secrets --all
# kubectl get pods --no-headers=true | awk '{print $1}' | grep "bench-us-east" |  xargs kubectl delete pod
kubectl delete pvc --all
kubectl delete serviceaccount bench-us-east-aptos-node
kubectl delete serviceaccount bench-us-east-aptos-node-haproxy
kubectl delete serviceaccount bench-us-east-aptos-node-validator
kubectl delete serviceaccount bench-us-east-aptos-node-fullnode
rm genesis/genesis.blob
rm genesis/waypoint.txt
