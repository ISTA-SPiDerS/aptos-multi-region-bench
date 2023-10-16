for load in nft dexavg dexbursty p2p solana
do
	echo $load >> finaloutput.txt
	for i in {1..5}
	do
		yes | ./bin/cluster.py upgrade --new --vfn-enabled

		sleep 30

		./bin/cluster.py genesis create --generate-keys

		sleep 60

		./bin/loadtest.py 0xE25708D90C72A53B400B27FC7602C4D546C7B7469FA6E12544F0EBFB2F16AE19 7 --apply --txn-expiration-time-secs=160 --mempool-backlog=500000 --duration=300 --only-within-cluster --coin-transfer --workload $load
	
		sleep 30

		kubectl logs -f loadtest > output.txt
		kubectl logs -f loadtest > output.txt

		tail -n 4 output.txt >> finaloutput.txt
		./kill.sh
	done
done

