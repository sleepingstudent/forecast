sudo mn --topo linear,3 --switch ovsk,protocols=OpenFlow13 --controller remote,ip=127.0.0.1,port=6653
./runos_poller.py --ip 127.0.0.1 --port 8000 --interval 1 > rule31.csv
