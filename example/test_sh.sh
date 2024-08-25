#!/bin/bash
#
# a test program

function a() {
    sleep 0.1
}

function b() {
    sleep 1
}

function c() {
    sleep 0.2
}

a
b
c
./test_sh1.sh
a
c
b
