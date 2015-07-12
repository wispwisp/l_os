#!/bin/bash

make clean && make && make make_disk && hexdump -C my_boot.img
