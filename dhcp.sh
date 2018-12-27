#!/bin/bash

nc -l 0.0.0.0 -up 67 | (
read -n1 op
echo "op: $op"
)
