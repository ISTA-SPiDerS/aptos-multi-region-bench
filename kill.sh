kubectl delete sts --all 
kubectl delete secrets --all
kubectl delete pods --all
kubectl delete pvc --all
kubectl delete serviceaccount bench-us-west-aptos-node
kubectl delete serviceaccount bench-us-west-aptos-node-haproxy
kubectl delete serviceaccount bench-us-west-aptos-node-validator
kubectl delete serviceaccount bench-us-west-aptos-node-fullnode
rm genesis/genesis.blob
rm genesis/waypoint.txt
