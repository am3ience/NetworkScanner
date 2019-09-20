#!/usr/bin/python
import multiprocessing
import subprocess
import os
from socket import inet_aton
import struct


def pinger(job_q, results_q):
    devnull = open(os.devnull, 'w')
    while True:
        ip = job_q.get()
        if ip is None: break

        try:
            subprocess.check_call(['ping', '-c1', ip], stdout=devnull)
            results_q.put(ip)
        except:
            pass


# --------------------------------------------------------------------------------------------------
if __name__ == "__main__":
    subnet = int(input("enter the subnet you want to scan (172.16._.0): "))
    # initialize list
    iplist = []
    # multiprocessing for fast pings
    pool_size = 255  # how many ip's you want to search
    jobs = multiprocessing.Queue()
    results = multiprocessing.Queue()
    pool = [multiprocessing.Process(target=pinger, args=(jobs, results))
            for i in range(pool_size)]

    for p in pool:
        p.start()

    for i in range(1, 255):
        jobs.put(('172.16.%i.{0}'.format(i)) % subnet)

    for p in pool:
        jobs.put(None)

    for p in pool:
        p.join()

    while not results.empty():
        ip = results.get()
        iplist.append(ip)

    # sort and print the list
    iplist.sort(key=lambda s: map(int, s.split('.')))
    for i in zip(iplist):
        print(''.join(i))